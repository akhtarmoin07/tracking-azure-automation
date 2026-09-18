variable "endpoint_subnet_cidr" {
  type    = string
  default = "10.60.2.0/24"
}

variable "host_subnet_cidr" {
  type    = string
  default = "10.60.1.0/24"
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

variable "tags" {
  type    = map(string)
  default = { Workload = "Finance-AVD", Owner = "PlatformOperations", CostCenter = "Finance" }
}

variable "vnet_cidr" {
  type    = string
  default = "10.60.0.0/16"
}
