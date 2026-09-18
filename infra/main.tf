locals {
  name  = "${var.prefix}-${var.environment}"
  tags  = merge(var.tags, { Environment = var.environment, ManagedBy = "Terraform" })
  hosts = { for n in range(var.host_count) : format("%02d", n) => "${var.prefix}-${format("%02d", n)}" }
}

resource "azurerm_resource_group" "avd" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

module "network" {
  source               = "./modules/network"
  endpoint_subnet_cidr = var.endpoint_subnet_cidr
  host_subnet_cidr     = var.host_subnet_cidr
  location             = var.location
  name                 = local.name
  resource_group_name  = azurerm_resource_group.avd.name
  tags                 = local.tags
  vnet_cidr            = var.vnet_cidr
}

module "avd" {
  source                        = "./modules/avd"
  enable_user_access            = var.enable_user_access
  environment                   = var.environment
  finance_group_object_id       = var.finance_group_object_id
  location                      = var.location
  max_sessions_per_host         = var.max_sessions_per_host
  name                          = local.name
  registration_token_expiration = var.registration_token_expiration
  resource_group_name           = azurerm_resource_group.avd.name
  tags                          = local.tags
}

module "profiles" {
  source                        = "./modules/profiles"
  endpoint_subnet_id            = module.network.endpoint_subnet_id
  file_dns_zone_id              = module.network.file_dns_zone_id
  finance_group_object_id       = var.finance_group_object_id
  location                      = var.location
  name                          = local.name
  profile_admin_group_object_id = var.profile_admin_group_object_id
  profile_share_quota_gb        = var.profile_share_quota_gb
  resource_group_name           = azurerm_resource_group.avd.name
  storage_account_name          = var.storage_account_name
  storage_replication           = var.storage_replication
  tags                          = local.tags
}

module "session_hosts" {
  source                  = "./modules/session_hosts"
  admin_password          = var.admin_password
  admin_username          = var.admin_username
  bootstrap_script        = file("${path.module}/../scripts/hosts/Initialize-SessionHost.ps1")
  finance_group_object_id = var.finance_group_object_id
  health_script           = file("${path.module}/../scripts/hosts/Test-SessionHostHealth.ps1")
  host_packages           = var.host_packages
  host_subnet_id          = module.network.host_subnet_id
  hosts                   = local.hosts
  image                   = var.image
  location                = var.location
  profile_unc             = module.profiles.unc
  registration_token      = module.avd.registration_token
  resource_group_name     = azurerm_resource_group.avd.name
  tags                    = local.tags
  vm_size                 = var.vm_size
  depends_on              = [module.network, module.profiles]
}

module "autoscale" {
  source                          = "./modules/autoscale"
  avd_service_principal_object_id = var.avd_service_principal_object_id
  avd_time_zone                   = var.avd_time_zone
  host_pool_id                    = module.avd.host_pool_id
  location                        = var.location
  name                            = local.name
  resource_group_name             = azurerm_resource_group.avd.name
  subscription_id                 = var.subscription_id
  tags                            = local.tags
}

module "automation" {
  source                 = "./modules/automation"
  audit_core_source      = file("${path.module}/../scripts/audit/AvdAudit.Core.psm1")
  audit_runbook_source   = file("${path.module}/../scripts/audit/Invoke-AvdAudit.ps1")
  audit_schedule_start   = var.audit_schedule_start
  avd_time_zone          = var.avd_time_zone
  enable_audit_schedules = var.enable_audit_schedules
  host_pool_id           = module.avd.host_pool_id
  location               = var.location
  max_sessions_per_host  = var.max_sessions_per_host
  minimum_free_sessions  = var.minimum_free_sessions
  minimum_ready_hosts    = var.minimum_ready_hosts
  name                   = local.name
  resource_group_id      = azurerm_resource_group.avd.id
  resource_group_name    = azurerm_resource_group.avd.name
  scaling_plan_id        = module.autoscale.id
  schedule_time_zone     = var.schedule_time_zone
  subscription_id        = var.subscription_id
  tags                   = local.tags
  tenant_id              = var.tenant_id
}

module "backup" {
  source              = "./modules/backup"
  avd_time_zone       = var.avd_time_zone
  enable_backup       = var.enable_backup
  location            = var.location
  name                = local.name
  resource_group_name = azurerm_resource_group.avd.name
  share_name          = module.profiles.share_name
  storage_account_id  = module.profiles.storage_account_id
  tags                = local.tags
}

module "monitoring" {
  source                 = "./modules/monitoring"
  automation_account_id  = module.automation.account_id
  budget_start_date      = var.budget_start_date
  desktop_id             = module.avd.desktop_id
  enable_audit_schedules = var.enable_audit_schedules
  host_ids               = module.session_hosts.host_ids
  host_pool_id           = module.avd.host_pool_id
  location               = var.location
  monthly_budget         = var.monthly_budget
  name                   = local.name
  operations_email       = var.operations_email
  resource_group_id      = azurerm_resource_group.avd.id
  resource_group_name    = azurerm_resource_group.avd.name
  schedule_time_zone     = var.schedule_time_zone
  storage_account_id     = module.profiles.storage_account_id
  tags                   = local.tags
  workspace_id           = module.avd.workspace_id
}
