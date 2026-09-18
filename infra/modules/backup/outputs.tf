output "protected_share_count" { value = length(azurerm_backup_protected_file_share.profiles) }
output "vault_id" { value = try(azurerm_recovery_services_vault.profiles[0].id, null) }
