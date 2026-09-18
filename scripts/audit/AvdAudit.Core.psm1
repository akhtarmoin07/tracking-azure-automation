Set-StrictMode -Version Latest

function Get-AvdAuditFindings {
    <# Evaluates a collected snapshot. No Azure calls and no mutations. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Snapshot,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][ValidateSet('PrePeak','OffPeak','Configuration')][string]$Mode,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    $findings = [System.Collections.Generic.List[object]]::new()
    # v1.1: heartbeat age is telemetry evidence, not a capacity gate.
    # Accept the original configuration key for existing lab configurations.
    $heartbeatWarningAge = if ($Config.ContainsKey('HeartbeatWarningAgeMinutes')) {
        $Config['HeartbeatWarningAgeMinutes']
    } else { $Config['MaxHeartbeatAgeMinutes'] }
    function Add-Finding([string]$Code, [string]$Severity, [string]$Resource, [string]$Message) {
        $findings.Add([pscustomobject]@{code=$Code; severity=$Severity; resource=$Resource; message=$Message})
    }
    $pool = $Snapshot['pool']
    $plan = $Snapshot['plan']
    if ($pool['hostPoolType'] -ne 'Pooled') {
        Add-Finding 'UnsupportedPool' 'Error' $Config['HostPoolId'] 'This audit supports pooled host pools only.'
    }
    if ($pool['maxSessionLimit'] -ne $Config['ExpectedMaxSessionLimit']) {
        Add-Finding 'SessionLimitDrift' 'Warning' $Config['HostPoolId'] "Expected maxSessionLimit $($Config['ExpectedMaxSessionLimit']); found $($pool['maxSessionLimit'])."
    }
    $assigned = @($plan['hostPoolReferences'] | Where-Object {
        $_.hostPoolArmPath -ieq $Config['HostPoolId'] -and $_.scalingPlanEnabled -eq $true
    })
    if ($assigned.Count -ne 1) {
        Add-Finding 'AutoscaleDisabled' 'Error' $Config['ScalingPlanId'] 'Expected scaling plan is not enabled for this pool.'
    }
    if ($plan['timeZone'] -ne $Config['ExpectedTimeZone']) {
        Add-Finding 'TimeZoneDrift' 'Error' $Config['ScalingPlanId'] "Expected $($Config['ExpectedTimeZone']); found $($plan['timeZone'])."
    }
    # Evaluate schedule coverage against the intended business time zone, even if the plan drifted.
    $zone = [TimeZoneInfo]::FindSystemTimeZoneById($Config['ExpectedTimeZone'])
    $day = [TimeZoneInfo]::ConvertTime($Now, $zone).DayOfWeek.ToString()
    $today = @($plan['schedules'] | Where-Object { $_.daysOfWeek -contains $day })
    if ($today.Count -ne 1) {
        Add-Finding 'ScheduleCoverage' 'Error' $Config['ScalingPlanId'] "Expected one schedule for $day; found $($today.Count)."
    }
    $ready = 0
    $freeSlots = 0
    $emptyRunning = 0
    foreach ($entry in $Snapshot['hosts']) {
        if ($entry['collectionError']) {
            Add-Finding 'HostDataUnavailable' 'Error' $entry['name'] 'Could not read complete host/VM data; readiness is unknown.'
            continue
        }
        $hostData = $entry['properties']
        if ($null -eq $hostData['sessions'] -or $hostData['sessions'] -lt 0 -or
            $null -eq $hostData['allowNewSession'] -or -not $hostData['status'] -or -not $entry['powerState']) {
            Add-Finding 'HostDataUnavailable' 'Error' $entry['name'] 'Required host or power-state fields are missing or invalid.'
            continue
        }
        $running = $entry['powerState'] -eq 'PowerState/running'
        $excluded = $false
        if ($plan['exclusionTag'] -and $entry['tags']) {
            $excluded = $entry['tags'].ContainsKey([string]$plan['exclusionTag'])
        }
        $fresh = $false
        if ($hostData['lastHeartBeat']) {
            $heartbeat = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse([string]$hostData['lastHeartBeat'], [ref]$heartbeat)) {
                $age = ($Now - $heartbeat).TotalMinutes
                $fresh = $age -ge -1 -and $age -le $heartbeatWarningAge
            }
        }
        if ($running -and $hostData['status'] -eq 'Available' -and $hostData['allowNewSession'] -eq $true) {
            $slots = [Math]::Max(0, [int]$pool['maxSessionLimit'] - [int]$hostData['sessions'])
            if ($slots -gt 0) { $ready++; $freeSlots += $slots }
        }
        if ($Mode -eq 'PrePeak' -and $running -and -not $fresh) {
            Add-Finding 'StaleHeartbeat' 'Warning' $entry['name'] 'Running host has missing, invalid, or stale AVD heartbeat.'
        }
        if ($Mode -eq 'OffPeak') {
            if ($entry['powerState'] -eq 'PowerState/stopped') {
                Add-Finding 'StoppedButAllocated' 'Warning' $entry['name'] 'VM is stopped but still allocated; investigate compute charges.'
            }
            if ($running -and $hostData['sessions'] -eq 0) {
                if ($excluded) {
                    Add-Finding 'ExcludedEmptyHost' 'Info' $entry['name'] 'Empty running VM has the scaling exclusion tag; review whether the exception is still needed.'
                } else {
                    $emptyRunning++
                }
            }
        }
    }
    if ($Snapshot['hosts'].Count -eq 0) {
        Add-Finding 'NoSessionHosts' 'Error' $Config['HostPoolId'] 'No registered session hosts found.'
    }
    if ($Mode -eq 'PrePeak') {
        if ($ready -lt $Config['MinimumReadyHosts']) {
            Add-Finding 'InsufficientReadyHosts' 'Error' $Config['HostPoolId'] "Ready hosts: $ready; required: $($Config['MinimumReadyHosts'])."
        }
        if ($freeSlots -lt $Config['MinimumFreeSessions']) {
            Add-Finding 'InsufficientSessionHeadroom' 'Error' $Config['HostPoolId'] "Free configured session slots: $freeSlots; required: $($Config['MinimumFreeSessions'])."
        }
    }
    if ($Mode -eq 'OffPeak' -and $emptyRunning -gt $Config['MaxOffPeakEmptyRunningHosts']) {
        Add-Finding 'ExcessEmptyRunningHosts' 'Warning' $Config['HostPoolId'] "Non-excluded empty running hosts: $emptyRunning; allowed: $($Config['MaxOffPeakEmptyRunningHosts']). Check autoscale after its ramp-down grace period."
    }
    return [pscustomobject]@{readyHosts=$ready; freeSessionSlots=$freeSlots; findings=$findings.ToArray()}
}
Export-ModuleMember -Function Get-AvdAuditFindings
