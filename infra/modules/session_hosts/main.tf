resource "azurerm_network_interface" "host" {
  for_each            = var.hosts
  name                = "nic-${each.value}"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.host_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
  tags = var.tags
}
resource "azurerm_windows_virtual_machine" "host" {
  for_each              = var.hosts
  name                  = each.value
  computer_name         = each.value
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.host[each.key].id]
  license_type          = "Windows_Client"
  provision_vm_agent    = true
  secure_boot_enabled   = true
  vtpm_enabled          = true
  patch_mode            = "AutomaticByOS"
  identity { type = "SystemAssigned" }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }
  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }
  boot_diagnostics {}
  tags = var.tags

  lifecycle {
    # Operations may temporarily exclude hosts while draining for maintenance.
    ignore_changes = [tags["AVD-Maintenance"]]
  }
}
resource "azurerm_virtual_machine_extension" "entra" {
  for_each                   = var.hosts
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[each.key].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}
resource "azurerm_role_assignment" "vm_users" {
  for_each             = var.hosts
  scope                = azurerm_windows_virtual_machine.host[each.key].id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.finance_group_object_id
  principal_type       = "Group"
}
resource "azurerm_virtual_machine_extension" "monitor" {
  for_each                   = var.hosts
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.host[each.key].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags
}

resource "azurerm_virtual_machine_run_command" "bootstrap" {
  for_each           = var.hosts
  name               = "Configure-SPORTFIVE"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.host[each.key].id
  source { script = var.bootstrap_script }
  parameter {
    name = "ConfigurationJson"
    value = jsonencode({
      ProfileUnc         = var.profile_unc
      Packages           = var.host_packages
      HealthScriptBase64 = base64encode(var.health_script)
    })
  }
  protected_parameter {
    name  = "RegistrationToken"
    value = var.registration_token
  }
  tags       = var.tags
  depends_on = [azurerm_virtual_machine_extension.entra]
}
