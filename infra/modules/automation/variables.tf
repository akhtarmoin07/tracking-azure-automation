variable "audit_core_source" {
  type = string
}

variable "audit_runbook_source" {
  type = string
}

variable "audit_schedule_start" {
  type        = object({ prepeak = string, offpeak = string })
  description = "Future ISO8601 times, at least 10 minutes after apply; align 07:35 and 20:30 Europe/Berlin with DST offset."
}

variable "avd_time_zone" {
  type    = string
  default = "W. Europe Standard Time"
}

variable "enable_audit_schedules" {
  type        = bool
  default     = false
  description = "Enable after host registration, runtime module import and manual audit acceptance."
}

variable "host_pool_id" {
  type = string
}

variable "location" {
  type    = string
  default = "northeurope"
}

variable "max_sessions_per_host" {
  type        = number
  default     = 5
  description = "LAB limit only; set from measured CPU/RAM/logon performance for pilot/production."
  validation {
    condition     = var.max_sessions_per_host >= 1 && var.max_sessions_per_host <= 100 && floor(var.max_sessions_per_host) == var.max_sessions_per_host
    error_message = "Session limit must be an integer from 1 to 100."
  }
}

variable "minimum_free_sessions" {
  type = number
}

variable "minimum_ready_hosts" {
  type = number
}

variable "name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "scaling_plan_id" {
  type = string
}

variable "schedule_time_zone" {
  type    = string
  default = "Europe/Berlin"
}

variable "subscription_id" {
  type        = string
  description = "Target Azure public-cloud subscription. No credentials in tfvars."
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id)) && var.subscription_id != "00000000-0000-0000-0000-000000000000"
    error_message = "Supply a real subscription UUID."
  }
}

variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}

variable "tenant_id" {
  type = string
}
