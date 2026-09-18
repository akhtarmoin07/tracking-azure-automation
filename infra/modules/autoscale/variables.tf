variable "avd_service_principal_object_id" {
  type        = string
  description = "Tenant object ID of Azure Virtual Desktop enterprise application (app ID 9cdead84-a844-4324-93f2-b2e6bb768d07). NOT its application ID."
}

variable "avd_time_zone" {
  type    = string
  default = "W. Europe Standard Time"
}

variable "host_pool_id" {
  type = string
}

variable "location" {
  type    = string
  default = "northeurope"
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
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
