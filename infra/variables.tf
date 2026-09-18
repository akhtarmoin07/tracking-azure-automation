variable "subscription_id" {
  type        = string
  description = "Target Azure public-cloud subscription. No credentials in tfvars."
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id)) && var.subscription_id != "00000000-0000-0000-0000-000000000000"
    error_message = "Supply a real subscription UUID."
  }
}
variable "tenant_id" {
  type = string
}
variable "prefix" {
  type    = string
  default = "sfavd"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,7}$", var.prefix))
    error_message = "Use 3-8 lowercase letters/digits, starting with a letter."
  }
}
variable "environment" {
  type    = string
  default = "lab"
  validation {
    condition     = contains(["lab", "pilot", "prod"], var.environment)
    error_message = "Use lab, pilot or prod."
  }
}
variable "location" {
  type    = string
  default = "northeurope"
}
variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}
variable "finance_group_object_id" {
  type        = string
  description = "Existing Entra security group for desktop and profile access."
}
variable "profile_admin_group_object_id" {
  type        = string
  description = "Existing, separate group for profile ACL administration."
}
variable "avd_service_principal_object_id" {
  type        = string
  description = "Tenant object ID of Azure Virtual Desktop enterprise application (app ID 9cdead84-a844-4324-93f2-b2e6bb768d07). NOT its application ID."
}
variable "storage_account_name" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account must be a globally unique 3-24 character lowercase alphanumeric name."
  }
}
variable "profile_share_quota_gb" {
  type    = number
  default = 5625
  validation {
    condition     = var.profile_share_quota_gb >= 100 && var.profile_share_quota_gb <= 102400 && floor(var.profile_share_quota_gb) == var.profile_share_quota_gb
    error_message = "Premium v1 share quota must be an integer from 100 to 102400 GiB."
  }
  validation {
    condition     = var.profile_share_quota_gb >= ceil(var.target_concurrent_users * 30000 / 1024 * 1.25)
    error_message = "Provision at least the configured population's 30000-MiB profile maximum plus 25% free space. Reassess IOPS, throughput and snapshot growth separately."
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
variable "target_concurrent_users" {
  type        = number
  default     = 150
  description = "Planning peak concurrency. The 150-user brief is conservatively treated as 150 simultaneous sessions."
  validation {
    condition     = var.target_concurrent_users >= 1 && floor(var.target_concurrent_users) == var.target_concurrent_users
    error_message = "Target concurrent users must be a positive integer."
  }
}
variable "host_failure_reserve" {
  type        = number
  default     = 1
  description = "Number of unavailable hosts for which configured session capacity is reserved. Does not preserve sessions on a failed VM."
  validation {
    condition     = var.host_failure_reserve >= 0 && floor(var.host_failure_reserve) == var.host_failure_reserve
    error_message = "Host failure reserve must be a nonnegative integer."
  }
}
variable "host_count" {
  type    = number
  default = 31
  validation {
    condition     = var.host_count >= 2 && var.host_count <= 99 && floor(var.host_count) == var.host_count
    error_message = "Use 2-99 hosts."
  }
  validation {
    condition     = (var.host_count - var.host_failure_reserve) * var.max_sessions_per_host >= var.target_concurrent_users
    error_message = "Host count must cover target concurrency after the configured host failure reserve: ceil(target_concurrent_users / max_sessions_per_host) + host_failure_reserve."
  }
}
variable "vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}
variable "max_sessions_per_host" {
  type        = number
  default     = 5
  description = "Provisional sessions/host for capacity arithmetic. Validate against measured CPU/RAM/logon performance before production."
  validation {
    condition     = var.max_sessions_per_host >= 1 && var.max_sessions_per_host <= 100 && floor(var.max_sessions_per_host) == var.max_sessions_per_host
    error_message = "Session limit must be an integer from 1 to 100."
  }
}
variable "admin_username" {
  type    = string
  default = "avdlocaladmin"
}
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Break-glass VM credential supplied via TF_VAR_admin_password; encrypted backend still contains this value."
  validation {
    condition     = length(var.admin_password) >= 16
    error_message = "Use a unique secret at least 16 characters long."
  }
}
variable "image" {
  type        = object({ publisher = string, offer = string, sku = string, version = string })
  description = "Explicit Windows 11 Enterprise multi-session image version, fully patched for chosen Kerberos identity mode."
  validation {
    condition     = var.image.version != "latest" && length(var.image.version) > 0
    error_message = "Pin an actual regional image version; do not use latest."
  }
}
variable "vnet_cidr" {
  type    = string
  default = "10.60.0.0/16"
}
variable "host_subnet_cidr" {
  type    = string
  default = "10.60.1.0/24"
}
variable "endpoint_subnet_cidr" {
  type    = string
  default = "10.60.2.0/24"
}
variable "avd_time_zone" {
  type    = string
  default = "W. Europe Standard Time"
}
variable "schedule_time_zone" {
  type    = string
  default = "Europe/Berlin"
}
variable "audit_schedule_start" {
  type        = object({ prepeak = string, offpeak = string })
  default     = null
  description = "Future ISO8601 times, at least 10 minutes after apply; align 07:35 and 20:30 Europe/Berlin with DST offset."
}
variable "minimum_ready_hosts" {
  type    = number
  default = 30
  validation {
    condition     = var.minimum_ready_hosts >= 1 && var.minimum_ready_hosts <= var.host_count && floor(var.minimum_ready_hosts) == var.minimum_ready_hosts
    error_message = "Minimum ready hosts must fit host_count."
  }
}
variable "minimum_free_sessions" {
  type    = number
  default = 150
  validation {
    condition     = var.minimum_free_sessions >= 1 && var.minimum_free_sessions <= var.host_count * var.max_sessions_per_host && floor(var.minimum_free_sessions) == var.minimum_free_sessions
    error_message = "Required headroom must fit configured pool capacity."
  }
}
variable "operations_email" {
  type = string
}
variable "monthly_budget" {
  type        = number
  description = "Budget in subscription billing currency. Notification only; not a spending cap."
  validation {
    condition     = var.monthly_budget > 0
    error_message = "Budget must be positive."
  }
}
variable "budget_start_date" {
  type        = string
  default     = null
  description = "First day of deployment month, for example 2026-09-01T00:00:00Z."
}
variable "enable_audit_schedules" {
  type        = bool
  default     = false
  description = "Enable after host registration, runtime module import and manual audit acceptance."
}
variable "enable_backup" {
  type    = bool
  default = true
}
variable "registration_token_expiration" {
  type        = string
  default     = null
  description = "Explicit future UTC timestamp, 1 hour to 27 days away. Renew deliberately for new hosts."
}
variable "host_packages" {
  description = "Reviewed immutable Microsoft installer URLs and SHA256 digests. FSLogix ZIP must contain x64/Release/FSLogixAppsSetup.exe."
  type        = map(object({ uri = string, sha256 = string }))
  validation {
    condition = alltrue([for name in ["agent", "bootloader", "fslogix"] :
      can(regex("^https://", var.host_packages[name].uri)) && can(regex("^[a-fA-F0-9]{64}$", var.host_packages[name].sha256))
    ])
    error_message = "Supply agent, bootloader and fslogix HTTPS URLs with exact SHA256 digests."
  }
}
variable "enable_user_access" {
  type        = bool
  default     = false
  description = "Publish desktop to finance group after storage ACLs and identity prerequisites are complete."
}
