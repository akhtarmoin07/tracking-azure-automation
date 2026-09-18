variable "enable_user_access" {
  type        = bool
  default     = false
  description = "Publish desktop to finance group after storage ACLs and identity prerequisites are complete."
}

variable "environment" {
  type    = string
  default = "lab"
  validation {
    condition     = contains(["lab", "pilot", "prod"], var.environment)
    error_message = "Use lab, pilot or prod."
  }
}

variable "finance_group_object_id" {
  type        = string
  description = "Existing Entra security group for desktop and profile access."
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

variable "name" {
  type = string
}

variable "registration_token_expiration" {
  type        = string
  description = "Explicit future UTC timestamp, 1 hour to 27 days away. Renew deliberately for new hosts."
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}
