provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    recovery_service {
      vm_backup_stop_protection_and_retain_data_on_destroy = true
    }
  }
}
