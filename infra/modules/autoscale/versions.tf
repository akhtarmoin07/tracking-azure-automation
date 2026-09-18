terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.69.0, < 5.0.0" }
    time    = { source = "hashicorp/time", version = "~> 0.13.0" }
  }
}
