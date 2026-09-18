Set-StrictMode -Version Latest

function Resolve-AvdDeploymentConfiguration {
    <# Resolve time-dependent values at plan time. Does not access Azure or write files. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration, [datetimeoffset]$Now = [datetimeoffset]::UtcNow)
    $config = @{}
    foreach ($key in $Configuration.Keys) { $config[$key] = $Configuration[$key] }
    foreach ($key in @('subscription_id','tenant_id','finance_group_object_id','profile_admin_group_object_id','avd_service_principal_object_id')) {
        $id = [guid]::Empty
        if (-not [guid]::TryParse([string]$config[$key],[ref]$id) -or $id -eq [guid]::Empty) { throw "Set a real $key." }
    }
    if ($config.ContainsKey('admin_password')) { throw 'Supply the password using TF_VAR_admin_password; exclude it from configuration JSON.' }
    if (-not $config['prefix']) { $config['prefix'] = 'sfavd' }
    if (-not $config['environment']) { $config['environment'] = 'lab' }
    if (-not $config['location']) { $config['location'] = 'northeurope' }
    if (-not $config['host_count']) { $config['host_count'] = 31 }
    if (-not $config['vm_size']) { $config['vm_size'] = 'Standard_D4s_v5' }
    if (-not $config['schedule_time_zone']) { $config['schedule_time_zone'] = 'Europe/Berlin' }
    if (-not $config['avd_time_zone']) { $config['avd_time_zone'] = 'W. Europe Standard Time' }
    if (-not $config['image'] -or $config['image']['version'] -in @($null,'','latest')) { throw 'Pin the regional image version.' }
    foreach ($name in @('agent','bootloader','fslogix')) {
        if (-not $config['host_packages'] -or -not $config['host_packages'][$name] -or
            $config['host_packages'][$name]['uri'] -notmatch '^https://' -or
            $config['host_packages'][$name]['sha256'] -notmatch '^[a-fA-F0-9]{64}$') { throw "Set the immutable $name URL and SHA256." }
    }
    if (-not $config['registration_token_expiration']) { $config['registration_token_expiration'] = $Now.AddDays(7).ToString('o') }
    $expiry = [datetimeoffset]::Parse($config['registration_token_expiration'])
    if ($expiry -lt $Now.AddHours(1) -or $expiry -gt $Now.AddDays(27)) { throw 'Registration expiry must be 1 hour to 27 days ahead; omit it to generate at plan time.' }
    if (-not $config['budget_start_date']) { $config['budget_start_date'] = $Now.UtcDateTime.ToString('yyyy-MM-01T00:00:00Z') }
    if (-not $config['audit_schedule_start']) {
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById($config['schedule_time_zone'])
        # First schedules start tomorrow or later, leaving room for full-fleet provisioning.
        $localDate = [TimeZoneInfo]::ConvertTime($Now,$zone).Date.AddDays(1)
        $starts = @{}
        foreach ($mode in @('prepeak','offpeak')) {
            $candidate = $localDate.AddHours(7).AddMinutes(35)
            if ($mode -eq 'offpeak') { $candidate = $localDate.AddHours(20).AddMinutes(30) }
            while ($true) {
                $utc = [TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($candidate,[DateTimeKind]::Unspecified),$zone)
                $weekend = $candidate.DayOfWeek -in @([DayOfWeek]::Saturday,[DayOfWeek]::Sunday)
                if ($utc -gt $Now.UtcDateTime.AddMinutes(10) -and ($mode -ne 'prepeak' -or -not $weekend)) { break }
                $candidate = $candidate.AddDays(1)
            }
            $starts[$mode] = ([datetimeoffset]$utc).ToString('o')
        }
        $config['audit_schedule_start'] = $starts
    }
    return $config
}

function Assert-AvdPlanHasNoDeletion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Plan)
    $deletions = @($Plan['resource_changes'] | Where-Object { $_['change']['actions'] -contains 'delete' })
    if ($deletions.Count) { throw "Plan contains deletion/replacement at: $($deletions.address -join ', '). Use a separately reviewed maintenance procedure." }
}

function Test-AvdRuntimeReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Report)
    return $Report['schemaVersion'] -eq '1.0' -and $Report['status'] -in @('Healthy','Warning') -and
        $Report['mode'] -in @('Configuration','PrePeak') -and $null -ne $Report['completedUtc'] -and
        @($Report['findings'] | Where-Object { $_['severity'] -eq 'Error' }).Count -eq 0
}
function Get-AvdProvisioningConfiguration {
    <# Keep existing access intact; first publication follows profile setup and runtime verification. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Desired, [hashtable]$Previous = @{})
    $result = @{} + $Desired
    foreach ($pair in @(@('enable_user_access','user_access_enabled'),@('enable_audit_schedules','audit_schedules_enabled'))) {
        $wasEnabled = $Previous[$pair[1]] -eq $true
        if ($wasEnabled -and $Desired[$pair[0]] -ne $true) { throw "Disabling $($pair[0]) needs a separately reviewed maintenance plan." }
        $result[$pair[0]] = $wasEnabled
    }
    return $result
}
function Assert-AvdActivationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Plan)
    Assert-AvdPlanHasNoDeletion $Plan
    $allowed = @(
        'module.avd.azurerm_role_assignment.desktop_users[0]',
        'module.automation.azurerm_automation_job_schedule.audit["PrePeak"]',
        'module.automation.azurerm_automation_job_schedule.audit["OffPeak"]',
        'module.monitoring.azurerm_monitor_scheduled_query_rules_alert_v2.operations["prepeak-report-missing"]'
    )
    foreach ($change in $Plan['resource_changes']) {
        if ($change['mode'] -eq 'data' -or ($change.change.actions -join ',') -eq 'no-op') { continue }
        if ($change.address -notin $allowed) { throw "Unexpected change during activation: $($change.address). Run a new reviewed deployment." }
    }
}
Export-ModuleMember -Function Resolve-AvdDeploymentConfiguration,Assert-AvdPlanHasNoDeletion,Test-AvdRuntimeReport,Get-AvdProvisioningConfiguration,Assert-AvdActivationPlan
