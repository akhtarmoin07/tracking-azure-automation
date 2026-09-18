resource "azurerm_storage_account" "profiles" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "FileStorage"
  account_tier                    = "Premium"
  account_replication_type        = var.storage_replication
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
  azure_files_authentication {
    directory_type                 = "AADKERB"
    default_share_level_permission = "None"
  }
  share_properties {
    retention_policy { days = 14 }
    smb {
      versions                        = ["SMB3.1.1"]
      authentication_types            = ["Kerberos"]
      kerberos_ticket_encryption_type = ["AES-256"]
      channel_encryption_type         = ["AES-128-GCM", "AES-256-GCM"]
    }
  }
  tags = var.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_storage_share" "profiles" {
  name               = "profiles"
  storage_account_id = azurerm_storage_account.profiles.id
  quota              = var.profile_share_quota_gb
  enabled_protocol   = "SMB"
  access_tier        = "Premium"
  lifecycle { prevent_destroy = true }
}
resource "azurerm_private_endpoint" "files" {
  name                = "pe-files-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.endpoint_subnet_id
  private_service_connection {
    name                           = "files"
    private_connection_resource_id = azurerm_storage_account.profiles.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "files"
    private_dns_zone_ids = [var.file_dns_zone_id]
  }
  tags = var.tags
}
resource "azurerm_role_assignment" "profile_users" {
  scope                = azurerm_storage_share.profiles.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.finance_group_object_id
  principal_type       = "Group"
}
resource "azurerm_role_assignment" "profile_admins" {
  scope                = azurerm_storage_share.profiles.id
  role_definition_name = "Storage File Data SMB Share Elevated Contributor"
  principal_id         = var.profile_admin_group_object_id
  principal_type       = "Group"
}
