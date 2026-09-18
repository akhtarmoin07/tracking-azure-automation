output "account_id" { value = azurerm_automation_account.audit.id }
output "account_name" { value = azurerm_automation_account.audit.name }
output "audit_config" { value = local.audit_config }
output "policy" {
  value = { reader_role = azurerm_role_assignment.audit_reader.role_definition_name, job_count = length(azurerm_automation_job_schedule.audit), fail_on_warning = [for job in azurerm_automation_job_schedule.audit : job.parameters["failonwarning"]] }
}
