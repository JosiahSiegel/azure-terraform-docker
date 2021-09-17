variable "location" {
  description = "Azure region"
}
variable "rg_name" {
  description = "Resource Group name"
}
variable "is_windows" {
  type        = bool
  description = "Host is windows"
}
