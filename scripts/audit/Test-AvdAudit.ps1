#Requires -Version 7.2
# Offline behavioral checks. No Azure modules, credentials, or resources required.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AvdAudit.Core.psm1" -Force
$now = [datetimeoffset]'2026-09-09T07:45:00Z'
$config = @{
    HostPoolId='/pool'; ScalingPlanId='/plan'; ExpectedTimeZone='UTC'; ExpectedMaxSessionLimit=10
    MinimumReadyHosts=3; MinimumFreeSessions=10; MaxOffPeakEmptyRunningHosts=0; MaxHeartbeatAgeMinutes=10
}
function New-Snapshot {
    return @{
        pool=@{hostPoolType='Pooled'; maxSessionLimit=10}
        plan=@{timeZone='UTC'; exclusionTag='exclude'; hostPoolReferences=@(@{hostPoolArmPath='/pool'; scalingPlanEnabled=$true})
            schedules=@(@{daysOfWeek=@('Wednesday')})}
        hosts=@(1..3 | ForEach-Object {
            @{name="host$_"; tags=@{}; collectionError=$false; powerState='PowerState/running'
              properties=@{sessions=0; status='Available'; allowNewSession=$true; lastHeartBeat=$now.ToString('o')}}
        })
    }
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Output "PASS: $Message"
}
function Evaluate([hashtable]$Snapshot, [string]$Mode='PrePeak') {
    Get-AvdAuditFindings -Snapshot $Snapshot -Config $config -Mode $Mode -Now $now
}
function Has-Code($Result, [string]$Code) { @($Result.findings | Where-Object code -eq $Code).Count -gt 0 }

$r = Evaluate (New-Snapshot)
Assert-True ($r.readyHosts -eq 3 -and $r.freeSessionSlots -eq 30 -and $r.findings.Count -eq 0) 'Healthy pre-peak baseline'
$s = New-Snapshot; $s.hosts[0].properties.allowNewSession = $false
Assert-True (Has-Code (Evaluate $s) 'InsufficientReadyHosts') 'Drain mode is not ready for new sessions'
$s = New-Snapshot; $s.hosts[0].properties.lastHeartBeat = $now.AddMinutes(-20).ToString('o')
$r = Evaluate $s
Assert-True ((Has-Code $r 'StaleHeartbeat') -and $r.readyHosts -eq 3 -and $r.freeSessionSlots -eq 30) 'Stale heartbeat warns without removing Available capacity'
$s = New-Snapshot; $s.hosts[0].properties.status = 'Unavailable'
Assert-True ((Evaluate $s).readyHosts -eq 2) 'Unavailable host is excluded from capacity'
$s = New-Snapshot; $s.hosts[0].collectionError = $true
Assert-True (Has-Code (Evaluate $s) 'HostDataUnavailable') 'A failed host read cannot appear healthy'
$s = New-Snapshot; $s.hosts[0].properties.Remove('sessions')
Assert-True (Has-Code (Evaluate $s) 'HostDataUnavailable') 'Missing session count is unknown, not zero'
$s = New-Snapshot; $s.plan.hostPoolReferences[0].scalingPlanEnabled = $false
Assert-True (Has-Code (Evaluate $s) 'AutoscaleDisabled') 'Disabled scaling assignment is detected'
$s = New-Snapshot; $s.plan.timeZone = 'W. Europe Standard Time'
Assert-True (Has-Code (Evaluate $s) 'TimeZoneDrift') 'Time zone drift is detected'
$s = New-Snapshot; $s.plan.schedules = @()
Assert-True (Has-Code (Evaluate $s) 'ScheduleCoverage') 'Missing schedule is detected'
$s = New-Snapshot; foreach ($h in $s.hosts) { $h.properties.sessions = 9 }
Assert-True (Has-Code (Evaluate $s) 'InsufficientSessionHeadroom') 'Ready hosts with insufficient free session slots fail headroom check'
$s = New-Snapshot; $s.hosts = @()
Assert-True (Has-Code (Evaluate $s) 'NoSessionHosts') 'Empty inventory is not healthy'
Assert-True (Has-Code (Evaluate (New-Snapshot) 'OffPeak') 'ExcessEmptyRunningHosts') 'Empty running hosts are flagged off-peak'
$s = New-Snapshot; foreach ($h in $s.hosts) { $h.properties.sessions = 1 }
Assert-True (-not (Has-Code (Evaluate $s 'OffPeak') 'ExcessEmptyRunningHosts')) 'Occupied hosts are not classified as empty'
$s = New-Snapshot; foreach ($h in $s.hosts) { $h.tags.exclude = '' }
Assert-True (-not (Has-Code (Evaluate $s 'OffPeak') 'ExcessEmptyRunningHosts')) 'Exclusion tag presence is respected, even with empty value'
$s = New-Snapshot; foreach ($h in $s.hosts) { $h.powerState = 'PowerState/stopped' }
Assert-True (Has-Code (Evaluate $s 'OffPeak') 'StoppedButAllocated') 'Stopped allocated hosts are flagged'
$s = New-Snapshot; foreach ($h in $s.hosts) { $h.powerState = 'PowerState/deallocated' }
Assert-True (-not (Has-Code (Evaluate $s 'OffPeak') 'StoppedButAllocated')) 'Deallocated hosts are not classified as allocated'
Write-Output 'All 16 offline checks passed.'
