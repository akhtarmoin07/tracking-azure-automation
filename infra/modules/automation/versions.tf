terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.69.0, < 5.0.0" }
    azapi   = { source = "Azure/azapi", version = ">= 2.4.0, < 3.0.0" }
  }
}
