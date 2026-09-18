variable "automation_account_id" {
  type = string
}

variable "budget_start_date" {
  type        = string
  description = "First day of deployment month, for example 2026-09-01T00:00:00Z."
}

variable "desktop_id" {
  type = string
}

variable "enable_audit_schedules" {
  type        = bool
  default     = false
  description = "Enable after host registration, runtime module import and manual audit acceptance."
}

variable "host_ids" {
  type = map(string)
}

variable "host_pool_id" {
  type = string
}

variable "location" {
  type    = string
  default = "northeurope"
}

variable "monthly_budget" {
  type        = number
  description = "Budget in subscription billing currency. Notification only; not a spending cap."
  validation {
    condition     = var.monthly_budget > 0
    error_message = "Budget must be positive."
  }
}

variable "name" {
  type = string
}

variable "operations_email" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "schedule_time_zone" {
  type    = string
  default = "Europe/Berlin"
}

variable "storage_account_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}

variable "workspace_id" {
  type = string
}
