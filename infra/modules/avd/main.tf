resource "azurerm_virtual_desktop_host_pool" "finance" {
  name                     = "hp-${var.name}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  friendly_name            = "SPORTFIVE Finance ${var.environment}"
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = var.max_sessions_per_host
  preferred_app_group_type = "Desktop"
  start_vm_on_connect      = true
  validate_environment     = var.environment == "lab"
  custom_rdp_properties    = "targetisaadjoined:i:1;enablerdsaadauth:i:1;redirectclipboard:i:0;drivestoredirect:s:;audiocapturemode:i:0;"
  tags                     = var.tags
  lifecycle {
    # Native scaling plan owns phase-specific load balancing after creation.
    ignore_changes = [load_balancer_type]
  }
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "finance" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.finance.id
  expiration_date = var.registration_token_expiration
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                = "dag-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.finance.id
  friendly_name       = "Finance Desktop"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace" "finance" {
  name                = "ws-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = "SPORTFIVE Finance"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "desktop" {
  workspace_id         = azurerm_virtual_desktop_workspace.finance.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

resource "azurerm_role_assignment" "desktop_users" {
  count                = var.enable_user_access ? 1 : 0
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = var.finance_group_object_id
  principal_type       = "Group"
}
