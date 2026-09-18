# Nonsecret settings for the NEW environment targeting 150 finance users.
# Commit this file; replace every REPLACE value. The Azure environment is still labelled lab.
# Keep passwords and tokens in secrets, never here.
subscription_id = "7cc1ef1a-4150-4526-b064-92476f36d815"
tenant_id       = "92869f7a-10fb-48a8-b446-decfe48d58f8"
prefix          = "sfavd"
environment     = "lab"
location        = "northeurope"
tags = {
  Workload   = "Finance-AVD"
  Owner      = "PlatformOperations"
  CostCenter = "Finance"
}

# Existing Entra object IDs, not application/client IDs.
finance_group_object_id         = "REPLACE-FINANCE-GROUP-OBJECT-ID"
profile_admin_group_object_id   = "REPLACE-PROFILE-ADMIN-GROUP-OBJECT-ID"
avd_service_principal_object_id = "REPLACE-AVD-ENTERPRISE-APP-OBJECT-ID"

# Planning assumption: all 150 users concurrent; retain the provisional 5 sessions/host.
# ceil(150 / 5) + 1 spare = 31 hosts. Validate workload density before deployment.
target_concurrent_users = 150
host_failure_reserve    = 1
host_count              = 31
vm_size                 = "Standard_D4s_v5"
admin_username          = "avdlocaladmin"
max_sessions_per_host   = 5
minimum_ready_hosts     = 30
minimum_free_sessions   = 150
# admin_password comes from GitHub secret VM_ADMIN_PASSWORD / TF_VAR_admin_password.
image = {
  publisher = "MicrosoftWindowsDesktop"
  offer     = "windows-11"
  sku       = "win11-24h2-avd"
  version   = "REPLACE-EXACT-PATCHED-IMAGE-VERSION"
}
host_packages = {
  agent = {
    uri    = "https://REPLACE/immutable/agent.msi"
    sha256 = "REPLACE-SHA256"
  }
  bootloader = {
    uri    = "https://REPLACE/immutable/bootloader.msi"
    sha256 = "REPLACE-SHA256"
  }
  fslogix = {
    uri    = "https://REPLACE/immutable/FSLogix.zip"
    sha256 = "REPLACE-SHA256"
  }
}
vnet_cidr            = "10.60.0.0/16"
host_subnet_cidr     = "10.60.1.0/24"
endpoint_subnet_cidr = "10.60.2.0/24"

# NEW Premium FSLogix storage, separate from the statetfmoin backend.
storage_account_name = "REPLACE-UNIQUE-PROFILE-STORAGE-NAME"
# 150 x 30 GiB allowance x 1.25 headroom = 5625 GiB; profile cap is 30000 MiB.
# Premium v1 baseline: 8625 IOPS, 663 MiB/s. Snapshot growth is budgeted separately.
profile_share_quota_gb = 5625
storage_replication    = "LRS"
enable_backup          = true
operations_email       = "REPLACE-OPERATIONS-EMAIL"
monthly_budget         = 10000 # Planning alert envelope in billing currency; see docs/GUIDE.md.
budget_start_date      = null  # Generated once at deployment; keep the established month on later runs.
avd_time_zone          = "W. Europe Standard Time"
schedule_time_zone     = "Europe/Berlin"

# UTC timestamp 1 hour to 27 days ahead when deploying/adding hosts.
registration_token_expiration = null # Deployment script generates seven days ahead.
# Future 07:35 weekday / 20:30 Berlin dates, with the correct offset and time for deployment to finish.
audit_schedule_start = null # Deployment script generates future Berlin schedule times.
# Publication is opt-in after tenant policy/pilot acceptance. The deployment runner stages
# first-time access and recurring checks until profile setup and runtime verification pass.
enable_user_access     = false
enable_audit_schedules = true
