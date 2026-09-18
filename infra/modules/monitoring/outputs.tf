output "workspace_id" { value = azurerm_log_analytics_workspace.avd.id }
output "workspace_customer_id" { value = azurerm_log_analytics_workspace.avd.workspace_id }
output "action_group_id" { value = azurerm_monitor_action_group.operations.id }
output "alert_policy" { value = { for key, rule in azurerm_monitor_scheduled_query_rules_alert_v2.operations : key => { enabled = rule.enabled, severity = rule.severity } } }
