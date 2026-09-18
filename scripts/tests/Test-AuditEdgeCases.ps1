#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/../audit/AvdAudit.Core.psm1" -Force
$now = [datetimeoffset]'2026-09-09T05:35:00Z'
$config = @{
    HostPoolId='/pool'; ScalingPlanId='/plan'; ExpectedTimeZone='W. Europe Standard Time'; ExpectedMaxSessionLimit=5
    MinimumReadyHosts=1; MinimumFreeSessions=1; MaxOffPeakEmptyRunningHosts=0; HeartbeatWarningAgeMinutes=10
}
function New-Fixture {
    @{
        pool=@{hostPoolType='Pooled'; maxSessionLimit=5}
        plan=@{timeZone='W. Europe Standard Time'; exclusionTag='maintenance'
            hostPoolReferences=@(@{hostPoolArmPath='/pool'; scalingPlanEnabled=$true})
            schedules=@(@{daysOfWeek=@('Wednesday')})}
        hosts=@(@{name='host'; tags=@{}; collectionError=$false; powerState='PowerState/running'
            properties=@{sessions=0; status='Available'; allowNewSession=$true; lastHeartBeat=$now.ToString('o')}})
    }
}
function Assert-Case([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }; Write-Output "PASS: $Name"
}
foreach ($heartbeat in @('2026-09-09T07:35:00+02:00','2026-09-09T05:25:00Z')) {
    $s = New-Fixture; $s.hosts[0].properties.lastHeartBeat = $heartbeat
    $r = Get-AvdAuditFindings $s $config PrePeak $now
    Assert-Case ($r.readyHosts -eq 1 -and $r.findings.Count -eq 0) "UTC normalization / inclusive warning threshold $heartbeat"
}
foreach ($heartbeat in @('invalid','2026-09-09T05:24:59Z','2026-09-09T06:35:00Z',$null)) {
    $s = New-Fixture; $s.hosts[0].properties.lastHeartBeat = $heartbeat
    $r = Get-AvdAuditFindings $s $config PrePeak $now
    Assert-Case ($r.readyHosts -eq 1 -and $r.freeSessionSlots -eq 5 -and
        @($r.findings | Where-Object { $_.code -eq 'StaleHeartbeat' -and $_.severity -eq 'Warning' }).Count -eq 1 -and
        @($r.findings | Where-Object severity -eq 'Error').Count -eq 0) "Invalid/stale/future/missing heartbeat warns without zeroing capacity: $heartbeat"
}
$s = New-Fixture; $s.hosts[0].properties.sessions = 5
$r = Get-AvdAuditFindings $s $config PrePeak $now
Assert-Case ($r.readyHosts -eq 0 -and $r.freeSessionSlots -eq 0) 'Full host is not free capacity'
$s = New-Fixture; $s.hosts[0].properties.sessions = 8
$r = Get-AvdAuditFindings $s $config PrePeak $now
Assert-Case ($r.freeSessionSlots -eq 0) 'Over-limit sessions never create negative headroom'
$s = New-Fixture; $s.plan.schedules += @{daysOfWeek=@('Wednesday')}
$r = Get-AvdAuditFindings $s $config Configuration $now
Assert-Case (@($r.findings | Where-Object code -eq 'ScheduleCoverage').Count -eq 1) 'Duplicate schedule is rejected'
$s = New-Fixture; $s.hosts[0].properties.lastHeartBeat = $now.AddHours(-12).ToString('o')
$r = Get-AvdAuditFindings $s $config Configuration $now
Assert-Case ($r.readyHosts -eq 1 -and $r.findings.Count -eq 0) 'Configuration mode does not enforce prepeak telemetry warnings'
# Reproduce the shared v1.1 lab result using sanitized IDs and the observed counts/timestamps.
$s = New-Fixture
$s.hosts[0].properties.sessions = 2
$s.hosts[0].properties.lastHeartBeat = '2026-09-09T08:10:06.43Z'
$second = (New-Fixture).hosts[0]
$second.name = 'host-two'
$second.properties.sessions = 1
$second.properties.lastHeartBeat = '2026-09-09T08:10:27.26Z'
$s.hosts += $second
$labConfig = $config.Clone()
$labConfig.MinimumReadyHosts = 2
$labConfig.MinimumFreeSessions = 4
$r = Get-AvdAuditFindings $s $labConfig PrePeak ([datetimeoffset]'2026-09-09T21:17:27Z')
Assert-Case ($r.readyHosts -eq 2 -and $r.freeSessionSlots -eq 7 -and $r.findings.Count -eq 2 -and
    @($r.findings | Where-Object { $_.code -ne 'StaleHeartbeat' -or $_.severity -ne 'Warning' }).Count -eq 0) 'v1.1 lab replay: two ready hosts, seven free slots, two warnings'
$s.hosts[1].properties.allowNewSession = $false
$r = Get-AvdAuditFindings $s $labConfig PrePeak ([datetimeoffset]'2026-09-09T21:17:27Z')
Assert-Case ($r.readyHosts -eq 1 -and $r.freeSessionSlots -eq 3 -and
    @($r.findings | Where-Object severity -eq 'Error').Count -eq 2) 'Real readiness/headroom failures still fail despite warning-only heartbeat'
Write-Output 'All 12 edge-case checks passed.'
