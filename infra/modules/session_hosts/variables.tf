variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Break-glass VM credential supplied via TF_VAR_admin_password; encrypted backend still contains this value."
  validation {
    condition     = length(var.admin_password) >= 16
    error_message = "Use a unique secret at least 16 characters long."
  }
}

variable "admin_username" {
  type    = string
  default = "avdlocaladmin"
}

variable "bootstrap_script" {
  type = string
}

variable "finance_group_object_id" {
  type        = string
  description = "Existing Entra security group for desktop and profile access."
}

variable "health_script" {
  type = string
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

variable "host_subnet_id" {
  type = string
}

variable "hosts" {
  type = map(string)
}

variable "image" {
  type        = object({ publisher = string, offer = string, sku = string, version = string })
  description = "Explicit Windows 11 Enterprise multi-session image version, fully patched for chosen Kerberos identity mode."
  validation {
    condition     = var.image.version != "latest" && length(var.image.version) > 0
    error_message = "Pin an actual regional image version; do not use latest."
  }
}

variable "location" {
  type    = string
  default = "northeurope"
}

variable "profile_unc" {
  type = string
}

variable "registration_token" {
  type      = string
  sensitive = true
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}

variable "vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}
