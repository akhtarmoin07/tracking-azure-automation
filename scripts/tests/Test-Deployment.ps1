#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/../deployment/AzureDeployment.Core.psm1" -Force
Import-Module "$PSScriptRoot/../deployment/AzureCli.psm1" -Force
$script:passed = 0
function Check([string]$Name,[scriptblock]$Test) {
    if (-not (& $Test)) { throw "FAIL: $Name" }
    $script:passed++; Write-Output "PASS: $Name"
}
function Rejects([scriptblock]$Action) { try { & $Action | Out-Null; return $false } catch { return $true } }
function Fixture {
    $value = @{}
    foreach ($key in @('subscription_id','tenant_id','finance_group_object_id','profile_admin_group_object_id','avd_service_principal_object_id')) { $value[$key] = '11111111-1111-1111-1111-111111111111' }
    $value.image = @{publisher='MicrosoftWindowsDesktop';offer='windows-11';sku='fixture';version='1.2.3'}
    $value.host_packages = @{}
    foreach ($name in @('agent','bootloader','fslogix')) { $value.host_packages[$name]=@{uri="https://example.test/$name";sha256=('a'*64)} }
    return $value
}
Check 'Sunday schedules leave provisioning time and start Monday in Berlin' {
    $result = Resolve-AvdDeploymentConfiguration (Fixture) ([datetimeoffset]'2026-09-13T08:00:00Z')
    [datetimeoffset]$result.audit_schedule_start.prepeak -eq [datetimeoffset]'2026-09-14T05:35:00Z' -and
    [datetimeoffset]$result.audit_schedule_start.offpeak -eq [datetimeoffset]'2026-09-14T18:30:00Z'
}
Check 'Prepeak schedule crosses winter DST correctly' {
    $result = Resolve-AvdDeploymentConfiguration (Fixture) ([datetimeoffset]'2026-10-23T18:00:00Z')
    [datetimeoffset]$result.audit_schedule_start.prepeak -eq [datetimeoffset]'2026-10-26T06:35:00Z'
}
Check 'Schedule never starts within ten minutes' {
    $result = Resolve-AvdDeploymentConfiguration (Fixture) ([datetimeoffset]'2026-09-14T05:30:00Z')
    [datetimeoffset]$result.audit_schedule_start.prepeak -eq [datetimeoffset]'2026-09-15T05:35:00Z'
}
Check 'Dates are resolved without mutating source configuration' {
    $fixture = Fixture; $result = Resolve-AvdDeploymentConfiguration $fixture ([datetimeoffset]'2026-09-13T08:00:00Z')
    -not $fixture.ContainsKey('budget_start_date') -and $result.budget_start_date -eq '2026-09-01T00:00:00Z' -and
    [datetimeoffset]$result.registration_token_expiration -eq [datetimeoffset]'2026-09-20T08:00:00Z'
}
Check 'Plaintext password configuration is rejected' { $v=Fixture; $v.admin_password='test'; Rejects { Resolve-AvdDeploymentConfiguration $v } }
Check 'Unselected subscription is rejected' { $v=Fixture; $v.subscription_id=[guid]::Empty.ToString(); Rejects { Resolve-AvdDeploymentConfiguration $v } }
Check 'Expired registration is rejected' { $v=Fixture; $v.registration_token_expiration='2020-01-01T00:00:00Z'; Rejects { Resolve-AvdDeploymentConfiguration $v } }
Check 'Unpinned image is rejected' { $v=Fixture; $v.image.version='latest'; Rejects { Resolve-AvdDeploymentConfiguration $v } }
Check 'Missing installer integrity is rejected' { $v=Fixture; $v.host_packages.agent.sha256=''; Rejects { Resolve-AvdDeploymentConfiguration $v } }
Check 'Create and update plans pass' {
    -not (Rejects { Assert-AvdPlanHasNoDeletion @{resource_changes=@(@{change=@{actions=@('create')}},@{change=@{actions=@('update')}})} })
}
Check 'Replacement plans are rejected' { Rejects { Assert-AvdPlanHasNoDeletion @{resource_changes=@(@{address='vm';change=@{actions=@('create','delete')}})} } }
Check 'Delete plans are rejected' { Rejects { Assert-AvdPlanHasNoDeletion @{resource_changes=@(@{address='vm';change=@{actions=@('delete')}})} } }
Check 'Heartbeat warnings remain acceptable runtime evidence' { Test-AvdRuntimeReport @{schemaVersion='1.0';status='Warning';mode='PrePeak';completedUtc='2026-09-13T08:00:00Z';findings=@(@{severity='Warning'})} }
Check 'Errors cannot be hidden behind a healthy status' { -not (Test-AvdRuntimeReport @{schemaVersion='1.0';status='Healthy';mode='Configuration';completedUtc='2026-09-13T08:00:00Z';findings=@(@{severity='Error'})}) }
Check 'Incomplete output is rejected' { -not (Test-AvdRuntimeReport @{schemaVersion='1.0';status='Incomplete';mode='Configuration';completedUtc=$null;findings=@()}) }
Check 'Cross-subscription ARM URL is rejected before CLI execution' { Rejects { Invoke-AvdArm -SubscriptionId '11111111-1111-1111-1111-111111111111' -Path '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/test' } }
Check 'External ARM URL is rejected before CLI execution' { Rejects { Invoke-AvdArm -SubscriptionId '11111111-1111-1111-1111-111111111111' -Path 'https://example.test/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test' } }
Check 'New publication is held until post-provisioning checks' {
    $desired=@{enable_user_access=$true;enable_audit_schedules=$true;host_count=31}
    $base=Get-AvdProvisioningConfiguration $desired
    -not $base.enable_user_access -and -not $base.enable_audit_schedules -and $base.host_count -eq 31 -and $desired.enable_user_access
}
Check 'Existing access and schedules remain enabled during updates' {
    $base=Get-AvdProvisioningConfiguration @{enable_user_access=$true;enable_audit_schedules=$true} @{user_access_enabled=$true;audit_schedules_enabled=$true}
    $base.enable_user_access -and $base.enable_audit_schedules
}
Check 'Unexpected unpublishing is refused' {
    Rejects { Get-AvdProvisioningConfiguration @{enable_user_access=$false} @{user_access_enabled=$true} }
}
Write-Output "All $script:passed deployment checks passed."
