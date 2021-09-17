terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.15.0"
    }
  }
}

# Create NSG
resource "azurerm_network_security_group" "user" {
  name                = "user-nsg"
  location            = var.location
  resource_group_name = var.rg_name

  security_rule {
    name                       = "SiteAllow"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "TCPDenySSH"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "TCPDenyRDP"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "UDPDeny"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "user"
  }
}

# Add DDOS protection
resource "azurerm_network_ddos_protection_plan" "user" {
  name                = "user-ddos"
  location            = var.location
  resource_group_name = var.rg_name
}

# Create VNET
resource "azurerm_virtual_network" "user" {
  name                = "user-vnet"
  location            = var.location
  resource_group_name = var.rg_name
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["10.0.0.4", "10.0.0.5"]

  ddos_protection_plan {
    id     = azurerm_network_ddos_protection_plan.user.id
    enable = true
  }

  tags = {
    environment = "user"
  }
}

# Create subnet
resource "azurerm_subnet" "user" {
  name                 = "usersubnet"
  resource_group_name  = var.rg_name
  virtual_network_name = azurerm_virtual_network.user.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "delegation"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Create network profile
resource "azurerm_network_profile" "user" {
  name                = "examplenetprofile"
  location            = var.location
  resource_group_name = var.rg_name

  container_network_interface {
    name = "usernic"

    ip_configuration {
      name      = "useripconfig"
      subnet_id = azurerm_subnet.user.id
    }
  }
}

# Create ACR
resource "azurerm_container_registry" "user" {
  name                = "useracr"
  location            = var.location
  resource_group_name = var.rg_name
  sku                 = "Basic"
  admin_enabled       = true
}

# Provision docker with ACR access
provider "docker" {
  registry_auth {
    address  = azurerm_container_registry.user.login_server
    username = azurerm_container_registry.user.admin_username
    password = azurerm_container_registry.user.admin_password
  }
  host = "npipe:////.//pipe//docker_engine"
}

# If docker change, wait with ACR to complete setup
resource "time_sleep" "wait" {
  depends_on      = [azurerm_container_registry.user]
  create_duration = "5m"
  triggers = {
    "key" = filesha1(format("%s/build/Dockerfile", path.root))
  }
}

# Push image to ACR
resource "docker_registry_image" "user" {
  name = format("%s/user_image:%s", azurerm_container_registry.user.login_server, filesha1(format("%s/build/Dockerfile", path.root)))
  build {
    #dirname allows Windows compatability
    context = dirname(format("%s/build/Dockerfile", abspath(path.root)))
    build_args = {
      version : "1"
    }
    labels = {
      author : "JS"
    }
  }
  depends_on = [
    time_sleep.wait
  ]
}

# If docker change, wait for image to complete install
resource "time_sleep" "wait_again" {
  depends_on = [
    docker_registry_image.user
  ]
  create_duration = "4m"
  triggers = {
    "key" = filesha1(format("%s/build/Dockerfile", path.root))
  }
}

# Launch image attached to VNET
resource "azurerm_container_group" "user_cg" {
  name                = "user-cg"
  location            = var.location
  resource_group_name = var.rg_name
  ip_address_type     = "private"
  os_type             = "Linux"

  image_registry_credential {
    server   = azurerm_container_registry.user.login_server
    username = azurerm_container_registry.user.admin_username
    password = azurerm_container_registry.user.admin_password
  }

  network_profile_id = azurerm_network_profile.user.id

  exposed_port = [{
    port     = 3000
    protocol = "TCP"
  }]

  container {
    # Dynamic name to prevent resource conflicts on rebuild
    name   = format("user-image-%s", filesha1(format("%s/build/Dockerfile", path.root)))
    image  = format("%s/user_image:%s", azurerm_container_registry.user.login_server, filesha1(format("%s/build/Dockerfile", path.root)))
    cpu    = "0.5"
    memory = "1.5"
    ports {
      port     = 3000
      protocol = "TCP"
    }
  }

  tags = {
    environment = "user"
  }
  depends_on = [
    time_sleep.wait_again
  ]
}
