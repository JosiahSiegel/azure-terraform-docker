terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.15.0"
    }
  }
  backend "azurerm" {
  }
}

provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "user" {
  name     = "demo-user-rg"
  location = "eastus2"
}

# Initial module
module "initial_resources" {
  source = "./modules/initial_resources"
  location = azurerm_resource_group.user.location
  rg_name  = azurerm_resource_group.user.name
}

# Final module
module "final_resources" {
  source   = "./modules/final_resources"
  location = azurerm_resource_group.user.location
  rg_name  = azurerm_resource_group.user.name
}
