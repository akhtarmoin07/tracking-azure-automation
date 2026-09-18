variable "avd_time_zone" {
  type    = string
  default = "W. Europe Standard Time"
}

variable "enable_backup" {
  type    = bool
  default = true
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

variable "share_name" {
  type = string
}

variable "storage_account_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}
