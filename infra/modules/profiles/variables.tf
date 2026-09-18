variable "endpoint_subnet_id" {
  type = string
}

variable "file_dns_zone_id" {
  type = string
}

variable "finance_group_object_id" {
  type        = string
  description = "Existing Entra security group for desktop and profile access."
}

variable "location" {
  type    = string
  default = "northeurope"
}

variable "name" {
  type = string
}

variable "profile_admin_group_object_id" {
  type        = string
  description = "Existing, separate group for profile ACL administration."
}

variable "profile_share_quota_gb" {
  type    = number
  default = 100
  validation {
    condition     = var.profile_share_quota_gb >= 100 && var.profile_share_quota_gb <= 102400 && floor(var.profile_share_quota_gb) == var.profile_share_quota_gb
    error_message = "Premium v1 share quota must be an integer from 100 to 102400 GiB."
  }
}

variable "resource_group_name" {
  type = string
}

variable "storage_account_name" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account must be a globally unique 3-24 character lowercase alphanumeric name."
  }
}

variable "storage_replication" {
  type    = string
  default = "LRS"
  validation {
    condition     = contains(["LRS", "ZRS"], var.storage_replication)
    error_message = "Use LRS or region-supported ZRS for Premium Files."
  }
}

variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}
