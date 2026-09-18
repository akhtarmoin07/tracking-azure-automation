mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

variables {
  enable_user_access     = false
  enable_audit_schedules = false
  # Small offline fixture; the real configuration targets 150 concurrent users.
  target_concurrent_users         = 5
  host_failure_reserve            = 1
  host_count                      = 2
  max_sessions_per_host           = 5
  minimum_ready_hosts             = 2
  minimum_free_sessions           = 3
  subscription_id                 = "11111111-1111-1111-1111-111111111111"
  tenant_id                       = "22222222-2222-2222-2222-222222222222"
  finance_group_object_id         = "33333333-3333-3333-3333-333333333333"
  profile_admin_group_object_id   = "44444444-4444-4444-4444-444444444444"
  avd_service_principal_object_id = "55555555-5555-5555-5555-555555555555"
  storage_account_name            = "sfofflinetest"
  operations_email                = "ops@example.com"
  admin_password                  = "Offline-test-only!123456"
  monthly_budget                  = 500
  budget_start_date               = "2026-09-01T00:00:00Z"
  registration_token_expiration   = "2026-09-15T00:00:00Z"
  audit_schedule_start            = { prepeak = "2026-09-14T07:35:00+02:00", offpeak = "2026-09-14T20:30:00+02:00" }
  image                           = { publisher = "MicrosoftWindowsDesktop", offer = "windows-11", sku = "win11-24h2-avd", version = "26100.8116.260401" }
  host_packages = {
    agent      = { uri = "https://example.com/agent.msi", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    bootloader = { uri = "https://example.com/loader.msi", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
    fslogix    = { uri = "https://example.com/fslogix.zip", sha256 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }
  }
}

run "isolated_small_fixture" {
  command = plan
  assert {
    condition     = length(module.session_hosts.hosts) == 2 && module.avd.policy.type == "Pooled"
    error_message = "The offline smoke fixture must be a two-host pooled pool."
  }
  assert {
    condition     = !module.profiles.policy.public_access && !module.profiles.policy.shared_key
    error_message = "Profiles must require private connectivity and identity authentication."
  }
  assert {
    condition     = module.profiles.policy.location == module.avd.policy.location
    error_message = "Profile storage and hosts must be colocated."
  }
  assert {
    condition     = alltrue([for schedule in module.autoscale.schedules : !schedule.ramp_down_force_logoff_users && schedule.ramp_down_stop_hosts_when == "ZeroSessions"])
    error_message = "Autoscale must preserve active and disconnected user sessions."
  }
  assert {
    condition     = module.automation.policy.job_count == 0 && module.avd.policy.access_assignments == 0
    error_message = "New environments must wait for identity/ACL and audit acceptance before publishing."
  }
  assert {
    condition     = module.automation.policy.reader_role == "Reader"
    error_message = "Read-only audit must not gain power or storage-data privileges."
  }
  assert {
    condition     = module.backup.protected_share_count == 1
    error_message = "Profile backup must be configured by default."
  }
}

run "accepted_lab" {
  command = plan
  variables {
    enable_user_access     = true
    enable_audit_schedules = true
  }
  assert {
    condition     = module.avd.policy.access_assignments == 1 && module.automation.policy.job_count == 2
    error_message = "Accepted configuration must publish the desktop and link both audit jobs."
  }
  assert {
    condition     = module.monitoring.alert_policy["prepeak-report-missing"].enabled
    error_message = "Missing-report monitoring must follow enabled audit schedules."
  }
  assert {
    condition     = alltrue([for flag in module.automation.policy.fail_on_warning : flag == "false"])
    error_message = "Heartbeat telemetry warnings must not fail scheduled jobs by default."
  }
  assert {
    condition     = module.monitoring.alert_policy["audit-warnings"].enabled && module.monitoring.alert_policy["audit-warnings"].severity == 3
    error_message = "Warning-only audit reports must remain visible through a separate warning alert."
  }
}

run "reject_impossible_headroom" {
  command = plan
  variables { minimum_free_sessions = 11 }
  expect_failures = [var.minimum_free_sessions]
}
run "reject_unpinned_image" {
  command = plan
  variables {
    image = { publisher = "MicrosoftWindowsDesktop", offer = "windows-11", sku = "win11-24h2-avd", version = "latest" }
  }
  expect_failures = [var.image]
}

run "finance_150_user_capacity" {
  command = plan
  variables {
    target_concurrent_users = 150
    host_failure_reserve    = 1
    host_count              = 31
    minimum_ready_hosts     = 30
    minimum_free_sessions   = 150
  }
  assert {
    condition     = length(module.session_hosts.hosts) == 31 && output.planned_capacity.slots_after_host_loss >= 150
    error_message = "The finance plan must retain 150 configured session slots after one host is unavailable."
  }
}

run "reject_150_users_without_spare" {
  command = plan
  variables {
    target_concurrent_users = 150
    host_failure_reserve    = 1
    host_count              = 30
  }
  expect_failures = [var.host_count]
}

run "reject_undersized_profile_share" {
  command = plan
  variables {
    profile_share_quota_gb = 100
  }
  expect_failures = [var.profile_share_quota_gb]
}
