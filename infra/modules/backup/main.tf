resource "azurerm_recovery_services_vault" "profiles" {
  count               = var.enable_backup ? 1 : 0
  name                = "rsv-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  storage_mode_type   = "LocallyRedundant"
  tags                = var.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_backup_container_storage_account" "profiles" {
  count               = var.enable_backup ? 1 : 0
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.profiles[0].name
  storage_account_id  = var.storage_account_id
}
resource "azurerm_backup_policy_file_share" "profiles" {
  count               = var.enable_backup ? 1 : 0
  name                = "daily-profiles"
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.profiles[0].name
  timezone            = var.avd_time_zone
  backup_tier         = "snapshot"
  backup {
    frequency = "Daily"
    time      = "23:00"
  }
  retention_daily { count = 14 }
  retention_weekly {
    count    = 4
    weekdays = ["Sunday"]
  }
}
resource "azurerm_backup_protected_file_share" "profiles" {
  count                     = var.enable_backup ? 1 : 0
  resource_group_name       = var.resource_group_name
  recovery_vault_name       = azurerm_recovery_services_vault.profiles[0].name
  source_storage_account_id = azurerm_backup_container_storage_account.profiles[0].storage_account_id
  source_file_share_name    = var.share_name
  backup_policy_id          = azurerm_backup_policy_file_share.profiles[0].id
  lifecycle { prevent_destroy = true }
}
