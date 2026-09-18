output "storage_account_id" { value = azurerm_storage_account.profiles.id }
output "storage_account_name" { value = azurerm_storage_account.profiles.name }
output "share_id" { value = azurerm_storage_share.profiles.id }
output "share_name" { value = azurerm_storage_share.profiles.name }
output "unc" { value = "\\\\${azurerm_storage_account.profiles.name}.file.core.windows.net\\profiles" }
output "ready" { value = azurerm_private_endpoint.files.id }
output "policy" {
  value = { public_access = azurerm_storage_account.profiles.public_network_access_enabled, shared_key = azurerm_storage_account.profiles.shared_access_key_enabled, location = azurerm_storage_account.profiles.location }
}
