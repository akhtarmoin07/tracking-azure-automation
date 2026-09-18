output "host_pool_id" { value = azurerm_virtual_desktop_host_pool.finance.id }
output "host_pool_name" { value = azurerm_virtual_desktop_host_pool.finance.name }
output "workspace_id" { value = azurerm_virtual_desktop_workspace.finance.id }
output "desktop_id" { value = azurerm_virtual_desktop_application_group.desktop.id }
output "registration_token" {
  value     = azurerm_virtual_desktop_host_pool_registration_info.finance.token
  sensitive = true
}
output "policy" {
  value = { type = azurerm_virtual_desktop_host_pool.finance.type, location = azurerm_virtual_desktop_host_pool.finance.location, access_assignments = length(azurerm_role_assignment.desktop_users) }
}
