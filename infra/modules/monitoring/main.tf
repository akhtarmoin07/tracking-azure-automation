resource "azurerm_log_analytics_workspace" "avd" {
  name                = "law-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
resource "azurerm_monitor_action_group" "operations" {
  name                = "ag-${var.name}"
  resource_group_name = var.resource_group_name
  short_name          = "AVDOps"
  email_receiver {
    name                    = "Operations"
    email_address           = var.operations_email
    use_common_alert_schema = true
  }
  tags = var.tags
}
locals {
  diagnostics = {
    hostpool   = var.host_pool_id
    desktop    = var.desktop_id
    workspace  = var.workspace_id
    automation = var.automation_account_id
    files      = "${var.storage_account_id}/fileServices/default"
  }
}
resource "azurerm_monitor_diagnostic_setting" "avd" {
  for_each                       = local.diagnostics
  name                           = "to-log-analytics"
  target_resource_id             = each.value
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.avd.id
  log_analytics_destination_type = each.key == "automation" ? "AzureDiagnostics" : "Dedicated"
  enabled_log { category_group = "allLogs" }
}
resource "azurerm_monitor_data_collection_rule" "hosts" {
  name                = "dcr-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Windows"
  destinations {
    log_analytics {
      name                  = "workspace"
      workspace_resource_id = azurerm_log_analytics_workspace.avd.id
    }
  }
  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Event"]
    destinations = ["workspace"]
  }
  data_sources {
    performance_counter {
      name                          = "avd-performance"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor Information(_Total)\\% Processor Time",
        "\\Memory\\Available MBytes",
        "\\Memory\\% Committed Bytes In Use",
        "\\LogicalDisk(C:)\\% Free Space",
        "\\Terminal Services\\Active Sessions",
        "\\Terminal Services\\Inactive Sessions",
        "\\User Input Delay per Session(*)\\Max Input Delay",
        "\\RemoteFX Network(*)\\Current TCP RTT"
      ]
    }
    windows_event_log {
      name    = "avd-events"
      streams = ["Microsoft-Event"]
      x_path_queries = [
        "System!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Application!*[System[Provider[@Name='SPORTFIVE-AVD-Health']]]",
        "Microsoft-FSLogix-Apps/Operational!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Microsoft-FSLogix-Apps/Admin!*",
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*",
        "Microsoft-Windows-RemoteDesktopServices-RdpCoreCDV/Operational!*[System[(EventID=131 or EventID=140)]]"
      ]
    }
  }
  tags = var.tags
}
resource "azurerm_monitor_data_collection_rule_association" "host" {
  for_each                = var.host_ids
  name                    = "avd-insights"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.hosts.id
}
locals {
  log_alerts = {
    audit-failed = {
      enabled = true
      query   = <<-KQL
        AzureDiagnostics
        | where _ResourceId =~ '${var.automation_account_id}'
        | where Category == 'JobLogs' and RunbookName_s == 'Invoke-AvdAudit'
        | where ResultType in ('Failed', 'Suspended', 'Stopped')
        | summarize arg_max(TimeGenerated, *) by JobId_g
      KQL
    }
    audit-warnings = {
      enabled = true
      query   = <<-KQL
        AzureDiagnostics
        | where _ResourceId =~ '${var.automation_account_id}'
        | where Category == 'JobStreams' and StreamType_s == 'Output'
        | where RunbookName_s == 'Invoke-AvdAudit'
        | extend Report = parse_json(ResultDescription)
        | where tostring(Report.schemaVersion) == '1.0' and tostring(Report.status) == 'Warning'
        | summarize arg_max(TimeGenerated, *) by JobId_g
      KQL
    }
    fslogix-errors = {
      enabled = true
      query   = <<-KQL
        Event
        | where (Source has 'FSLogix' or Source == 'SPORTFIVE-AVD-Health')
        | where EventLevelName in ('Error', 'Warning')
      KQL
    }
    scaling-errors = {
      enabled = true
      query   = <<-KQL
        WVDAutoscaleEvaluationPooled
        | where _ResourceId =~ '${var.host_pool_id}'
        | where ResultType == 'Failed'
      KQL
    }
    prepeak-report-missing = {
      enabled = var.enable_audit_schedules
      query = templatefile("${path.module}/queries/missing-prepeak.kql", {
        account_id = var.automation_account_id
        timezone   = var.schedule_time_zone
      })
    }
  }
}
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "operations" {
  for_each             = local.log_alerts
  name                 = "${each.key}-${var.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  scopes               = [azurerm_log_analytics_workspace.avd.id]
  evaluation_frequency = "PT5M"
  window_duration      = each.key == "prepeak-report-missing" ? "PT1H" : "PT15M"
  severity             = each.key == "audit-warnings" ? 3 : 2
  enabled              = each.value.enabled
  # Tables appear after first ingestion. Validate KQL against real lab data before activation.
  skip_query_validation = true
  criteria {
    query                   = each.value.query
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  action { action_groups = [azurerm_monitor_action_group.operations.id] }
  tags = var.tags
}
resource "azurerm_monitor_metric_alert" "files_throttling" {
  name                = "files-throttling-${var.name}"
  resource_group_name = var.resource_group_name
  scopes              = ["${var.storage_account_id}/fileServices/default"]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts/fileServices"
    metric_name      = "Transactions"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    dimension {
      name     = "ResponseType"
      operator = "Include"
      values   = ["ClientThrottlingError", "ServerBusyError", "SuccessWithThrottling", "SuccessWithShareIopsThrottling", "SuccessWithShareBandwidthThrottling"]
    }
  }
  action { action_group_id = azurerm_monitor_action_group.operations.id }
  tags = var.tags
}
resource "azurerm_consumption_budget_resource_group" "avd" {
  name              = "budget-${var.name}"
  resource_group_id = var.resource_group_id
  amount            = var.monthly_budget
  time_grain        = "Monthly"
  time_period { start_date = var.budget_start_date }
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.operations_email]
  }
  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.operations_email]
  }
}
