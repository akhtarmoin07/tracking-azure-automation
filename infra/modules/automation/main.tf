locals {
  audit_config = {
    TenantId                    = var.tenant_id
    SubscriptionId              = var.subscription_id
    HostPoolId                  = var.host_pool_id
    ScalingPlanId               = var.scaling_plan_id
    ExpectedTimeZone            = var.avd_time_zone
    ExpectedMaxSessionLimit     = var.max_sessions_per_host
    MinimumReadyHosts           = var.minimum_ready_hosts
    MinimumFreeSessions         = var.minimum_free_sessions
    MaxOffPeakEmptyRunningHosts = 0
    HeartbeatWarningAgeMinutes  = 10
  }
  audit_core    = replace(var.audit_core_source, "Export-ModuleMember -Function Get-AvdAuditFindings", "")
  audit_content = replace(var.audit_runbook_source, "# INLINE_CORE", local.audit_core)
  audit_schedules = {
    PrePeak = { start = var.audit_schedule_start.prepeak, days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] }
    OffPeak = { start = var.audit_schedule_start.offpeak, days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] }
  }
}
resource "azurerm_automation_account" "audit" {
  name                = "aa-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  identity { type = "SystemAssigned" }
  tags = var.tags
}
resource "azapi_resource" "audit_runtime" {
  type      = "Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23"
  name      = "PowerShell74-Audit"
  parent_id = azurerm_automation_account.audit.id
  location  = var.location
  body = {
    properties = {
      runtime         = { language = "PowerShell", version = "7.4" }
      defaultPackages = { Az = "12.3.0" }
      description     = "Pinned audit runtime. Validate managed-identity ARM reads before enabling schedules."
    }
  }
  tags = var.tags
}
resource "azurerm_role_assignment" "audit_reader" {
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = azurerm_automation_account.audit.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_automation_runbook" "audit" {
  name                     = "Invoke-AvdAudit"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  automation_account_name  = azurerm_automation_account.audit.name
  runbook_type             = "PowerShell"
  runtime_environment_name = azapi_resource.audit_runtime.name
  log_progress             = false
  log_verbose              = false
  description              = "Read-only readiness and autoscale audit. Embedded core from scripts/audit."
  content                  = local.audit_content
  tags                     = var.tags
}
resource "azurerm_automation_schedule" "audit" {
  for_each                = local.audit_schedules
  name                    = each.key
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.audit.name
  frequency               = "Week"
  interval                = 1
  timezone                = var.schedule_time_zone
  start_time              = each.value.start
  week_days               = each.value.days
  description             = "${each.key} in finance business time zone."
  lifecycle { ignore_changes = [start_time] }
}
# Unlinked schedules do not run. Enable after a successful manual audit and host bootstrap.
resource "azurerm_automation_job_schedule" "audit" {
  for_each                = var.enable_audit_schedules ? local.audit_schedules : {}
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.audit.name
  schedule_name           = azurerm_automation_schedule.audit[each.key].name
  runbook_name            = azurerm_automation_runbook.audit.name
  parameters = {
    configjson     = jsonencode(local.audit_config)
    mode           = each.key
    authentication = "ManagedIdentity"
    # Warnings remain visible in JSON and have their own Monitor rule.
    # Do not turn the v1.1 stale-heartbeat warning back into a failed job.
    failonwarning = "false"
  }
  depends_on = [azurerm_role_assignment.audit_reader]
}
