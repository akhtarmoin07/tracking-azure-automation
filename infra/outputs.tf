output "deployment" {
  value = {
    subscription_id           = var.subscription_id
    tenant_id                 = var.tenant_id
    budget_start_date         = var.budget_start_date
    resource_group            = azurerm_resource_group.avd.name
    resource_group_id         = azurerm_resource_group.avd.id
    host_pool_name            = module.avd.host_pool_name
    host_pool_id              = module.avd.host_pool_id
    workspace_id              = module.avd.workspace_id
    hosts                     = module.session_hosts.hosts
    profile_unc               = module.profiles.unc
    storage_account           = module.profiles.storage_account_name
    profile_share_id          = module.profiles.share_id
    finance_group_id          = var.finance_group_object_id
    profile_admin_group_id    = var.profile_admin_group_object_id
    automation_account        = module.automation.account_name
    automation_account_id     = module.automation.account_id
    log_analytics_id          = module.monitoring.workspace_id
    log_analytics_customer_id = module.monitoring.workspace_customer_id
    backup_vault_id           = module.backup.vault_id
    audit_schedules_enabled   = var.enable_audit_schedules
    user_access_enabled       = var.enable_user_access
  }
}
output "audit_config" { value = module.automation.audit_config }
# Registration tokens remain sensitive module-internal values, never root outputs.
output "planned_capacity" {
  value = {
    target_concurrent_users = var.target_concurrent_users
    host_count              = var.host_count
    sessions_per_host       = var.max_sessions_per_host
    host_failure_reserve    = var.host_failure_reserve
    total_session_slots     = var.host_count * var.max_sessions_per_host
    slots_after_host_loss   = (var.host_count - var.host_failure_reserve) * var.max_sessions_per_host
  }
}
