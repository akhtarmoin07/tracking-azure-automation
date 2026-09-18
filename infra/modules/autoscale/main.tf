# Microsoft requires subscription scope for the AVD service-principal power role.
resource "azurerm_role_assignment" "autoscale" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Desktop Virtualization Power On Off Contributor"
  principal_id         = var.avd_service_principal_object_id
  principal_type       = "ServicePrincipal"
}
resource "time_sleep" "autoscale_rbac" {
  depends_on      = [azurerm_role_assignment.autoscale]
  create_duration = "60s"
}
resource "azurerm_virtual_desktop_scaling_plan" "finance" {
  name                = "sp-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  time_zone           = var.avd_time_zone
  exclusion_tag       = "AVD-Maintenance"
  host_pool {
    hostpool_id          = var.host_pool_id
    scaling_plan_enabled = true
  }
  schedule {
    name                                 = "finance-weekdays"
    days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    ramp_up_start_time                   = "07:00"
    ramp_up_load_balancing_algorithm     = "BreadthFirst"
    ramp_up_minimum_hosts_percent        = 100
    ramp_up_capacity_threshold_percent   = 60
    peak_start_time                      = "08:00"
    peak_load_balancing_algorithm        = "BreadthFirst"
    ramp_down_start_time                 = "18:00"
    ramp_down_load_balancing_algorithm   = "DepthFirst"
    ramp_down_minimum_hosts_percent      = 0
    ramp_down_capacity_threshold_percent = 90
    ramp_down_force_logoff_users         = false
    ramp_down_wait_time_minutes          = 30
    ramp_down_notification_message       = "Please sign out when finished."
    ramp_down_stop_hosts_when            = "ZeroSessions"
    off_peak_start_time                  = "20:00"
    off_peak_load_balancing_algorithm    = "DepthFirst"
  }
  schedule {
    name                                 = "weekends"
    days_of_week                         = ["Saturday", "Sunday"]
    ramp_up_start_time                   = "07:00"
    ramp_up_load_balancing_algorithm     = "DepthFirst"
    ramp_up_minimum_hosts_percent        = 0
    ramp_up_capacity_threshold_percent   = 90
    peak_start_time                      = "08:00"
    peak_load_balancing_algorithm        = "DepthFirst"
    ramp_down_start_time                 = "18:00"
    ramp_down_load_balancing_algorithm   = "DepthFirst"
    ramp_down_minimum_hosts_percent      = 0
    ramp_down_capacity_threshold_percent = 90
    ramp_down_force_logoff_users         = false
    ramp_down_wait_time_minutes          = 30
    ramp_down_notification_message       = "Please sign out when finished."
    ramp_down_stop_hosts_when            = "ZeroSessions"
    off_peak_start_time                  = "20:00"
    off_peak_load_balancing_algorithm    = "DepthFirst"
  }
  tags       = var.tags
  depends_on = [time_sleep.autoscale_rbac]
}
