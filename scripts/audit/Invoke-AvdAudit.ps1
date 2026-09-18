#Requires -Version 7.2
<#
.SYNOPSIS
Read-only AVD capacity and autoscale audit for Azure Automation or a local Az session.
.DESCRIPTION
Writes one JSON report to the output stream. Throws after reporting errors (or warnings
with -FailOnWarning), so Azure Automation marks the job Failed. No secrets in config.
Terraform embeds AvdAudit.Core for Azure Automation; see docs/GUIDE.md.
#>
[CmdletBinding(DefaultParameterSetName='File')]
param(
    [Parameter(Mandatory,ParameterSetName='File')][string]$ConfigPath,
    [Parameter(Mandatory,ParameterSetName='Inline')][string]$ConfigJson,
    [Parameter(Mandatory)][ValidateSet('PrePeak','OffPeak','Configuration')][string]$Mode,
    [ValidateSet('ManagedIdentity','ExistingContext')][string]$Authentication = 'ManagedIdentity',
    [string]$ManagedIdentityClientId,
    [string]$ReportPath,
    [switch]$FailOnWarning
)
# INLINE_CORE
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$report = [ordered]@{
    schemaVersion='1.0'; runId=[guid]::NewGuid().ToString(); startedUtc=[datetimeoffset]::UtcNow.ToString('o')
    completedUtc=$null; mode=$Mode; status='Incomplete'; summary=$null; findings=@(); hosts=@()
}
$failed = $false
try {
    if ($PSCmdlet.ParameterSetName -eq 'File') { $ConfigJson = Get-Content -LiteralPath $ConfigPath -Raw }
    $config = ConvertFrom-Json -InputObject $ConfigJson -AsHashtable
    if ($config.ContainsKey('MaxHeartbeatAgeMinutes')) {
        if ($config.ContainsKey('HeartbeatWarningAgeMinutes') -and
            $config['HeartbeatWarningAgeMinutes'] -ne $config['MaxHeartbeatAgeMinutes']) {
            throw 'Conflicting heartbeat warning thresholds. Use HeartbeatWarningAgeMinutes only.'
        }
        if (-not $config.ContainsKey('HeartbeatWarningAgeMinutes')) {
            $config['HeartbeatWarningAgeMinutes'] = $config['MaxHeartbeatAgeMinutes']
        }
    }
    foreach ($key in @('TenantId','SubscriptionId','HostPoolId','ScalingPlanId','ExpectedTimeZone',
        'ExpectedMaxSessionLimit','MinimumReadyHosts','MinimumFreeSessions','MaxOffPeakEmptyRunningHosts','HeartbeatWarningAgeMinutes')) {
        if (-not $config.ContainsKey($key) -or $null -eq $config[$key]) { throw "Configuration missing $key." }
    }
    foreach ($key in @('TenantId','SubscriptionId')) {
        if ([guid]::Parse($config[$key]) -eq [guid]::Empty) { throw "Set a real $key." }
    }
    foreach ($key in @('ExpectedMaxSessionLimit','MinimumReadyHosts','MinimumFreeSessions','HeartbeatWarningAgeMinutes')) {
        if ($config[$key] -isnot [long] -and $config[$key] -isnot [int]) { throw "$key must be an integer." }
        if ($config[$key] -lt 1 -or $config[$key] -gt 1000000) { throw "$key is out of range." }
    }
    if (($config['MaxOffPeakEmptyRunningHosts'] -isnot [long] -and $config['MaxOffPeakEmptyRunningHosts'] -isnot [int]) -or
        $config['MaxOffPeakEmptyRunningHosts'] -lt 0 -or $config['MaxOffPeakEmptyRunningHosts'] -gt 1000000) {
        throw 'MaxOffPeakEmptyRunningHosts must be a nonnegative integer up to 1000000.'
    }
    $null = [TimeZoneInfo]::FindSystemTimeZoneById($config['ExpectedTimeZone'])
    $prefix = '^/subscriptions/' + [regex]::Escape($config['SubscriptionId']) + '/resourceGroups/[^/?#]+/providers/'
    if ($config['HostPoolId'] -notmatch ($prefix + 'Microsoft.DesktopVirtualization/hostPools/[^/?#]+$') -or
        $config['ScalingPlanId'] -notmatch ($prefix + 'Microsoft.DesktopVirtualization/scalingPlans/[^/?#]+$')) {
        throw 'Resource IDs must identify a pool and scaling plan in the configured subscription.'
    }
    if (Get-Command Get-AvdAuditFindings -ErrorAction SilentlyContinue) {
        # Terraform embeds the tested core in the Automation runbook.
    } elseif (Test-Path -LiteralPath "$PSScriptRoot/AvdAudit.Core.psm1") {
        Import-Module "$PSScriptRoot/AvdAudit.Core.psm1" -Force
    } else { Import-Module AvdAudit.Core -ErrorAction Stop }
    Import-Module Az.Accounts -ErrorAction Stop
    Disable-AzContextAutosave -Scope Process | Out-Null
    if ($Authentication -eq 'ManagedIdentity') {
        $login = @{Identity=$true; ErrorAction='Stop'}
        if ($ManagedIdentityClientId) { $login.AccountId = $ManagedIdentityClientId }
        $context = (Connect-AzAccount @login).Context
    } else {
        if ($ManagedIdentityClientId) { throw 'ManagedIdentityClientId is only valid with ManagedIdentity authentication.' }
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) { throw 'Sign in with Connect-AzAccount first.' }
    }
    $context = Set-AzContext -SubscriptionId $config['SubscriptionId'] -TenantId $config['TenantId'] -DefaultProfile $context
    if ($context.Subscription.Id -ne $config['SubscriptionId'] -or $context.Tenant.Id -ne $config['TenantId']) {
        throw 'Authenticated context does not match the configured tenant/subscription.'
    }
    if ($context.Environment.Name -ne 'AzureCloud') { throw 'This version targets Azure public cloud only.' }

    function Read-ArmJson([string]$Path) {
        # Pagination URLs are accepted only from the configured ARM endpoint/subscription.
        $uri = [uri]::new([uri]'https://management.azure.com', $Path)
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'management.azure.com' -or $uri.Port -ne 443 -or
            $uri.UserInfo -or $uri.AbsolutePath -notlike "/subscriptions/$($config['SubscriptionId'])/*") {
            throw 'Rejected ARM URL outside the configured scope.'
        }
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
            $status = 0
            $retryAfter = 0
            $retryHeader = $null
            try {
                $response = Invoke-AzRestMethod -Uri $uri.AbsoluteUri -Method GET -DefaultProfile $context -ErrorAction Stop
                $status = [int]$response.StatusCode
                if ($status -eq 200) { return ConvertFrom-Json -InputObject $response.Content -AsHashtable }
                if ($response.Headers -and $response.Headers['Retry-After']) {
                    $retryHeader = [string]($response.Headers['Retry-After'] | Select-Object -First 1)
                }
            } catch {
                # Some Az.Accounts versions throw for HTTP failures. Do not print raw responses/tokens.
                if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                    $status = [int]$_.Exception.Response.StatusCode
                    # If headers cannot be interpreted, fail rather than retrying prematurely.
                    try {
                        $retryHeader = [string]$_.Exception.Response.Headers.RetryAfter
                    } catch { throw 'ARM read failed; retry headers could not be read.' }
                }
            }
            if ($status -notin @(429,500,502,503,504) -or $attempt -eq 3) {
                throw "ARM read failed (HTTP $status). Check job identity, permissions, resource existence, and connectivity."
            }
            if ($retryHeader -and -not [int]::TryParse($retryHeader, [ref]$retryAfter)) {
                $retryDate = [datetimeoffset]::MinValue
                if (-not [datetimeoffset]::TryParse($retryHeader, [ref]$retryDate)) { throw 'ARM returned an unrecognized Retry-After header.' }
                $retryAfter = [int][Math]::Ceiling(($retryDate - [datetimeoffset]::UtcNow).TotalSeconds)
            }
            # Do not retry earlier than a long server-requested delay; fail this run instead.
            if ($retryAfter -gt 30) { throw 'ARM requested a retry delay over 30 seconds; retry on the next scheduled audit.' }
            $delay = [Math]::Max($retryAfter, [Math]::Pow(2,$attempt) + (Get-Random -Minimum 0 -Maximum 3))
            Start-Sleep -Seconds $delay
        }
    }
    function Read-ArmList([string]$Path) {
        $items = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        while ($Path) {
            if (-not $seen.Add($Path) -or $seen.Count -gt 1000) { throw 'Invalid ARM pagination.' }
            $page = Read-ArmJson $Path
            if (-not $page.ContainsKey('value')) { throw 'ARM list response has no value field.' }
            foreach ($item in $page['value']) { $items.Add($item) }
            $Path = $page['nextLink']
        }
        return $items.ToArray()
    }
    $avdVersion = '2024-04-03'
    $pool = Read-ArmJson "$($config['HostPoolId'])?api-version=$avdVersion"
    $plan = Read-ArmJson "$($config['ScalingPlanId'])?api-version=$avdVersion"
    $registeredHosts = @(Read-ArmList "$($config['HostPoolId'])/sessionHosts?api-version=$avdVersion")
    $hosts = @(
        foreach ($item in $registeredHosts) {
            $entry = @{name=$item['name']; properties=$item['properties']; tags=@{}; powerState=$null; collectionError=$false}
            try {
                $vmId = $item['properties'].resourceId
                if (-not $vmId -or $vmId -notmatch ($prefix + 'Microsoft.Compute/virtualMachines/[^/?#]+$')) {
                    throw 'Session host has no valid underlying VM resource ID in the configured subscription.'
                }
                $vm = Read-ArmJson "${vmId}?api-version=2024-07-01&`$expand=instanceView"
                $entry['tags'] = $vm['tags']
                $states = @($vm['properties'].instanceView.statuses | Where-Object { $_.code -like 'PowerState/*' })
                if ($states.Count -ne 1) { throw 'VM power state is missing or ambiguous.' }
                $entry['powerState'] = $states[0].code
            } catch { $entry['collectionError'] = $true }
            $entry
        }
    )
    $result = Get-AvdAuditFindings -Snapshot @{pool=$pool['properties']; plan=$plan['properties']; hosts=$hosts} -Config $config -Mode $Mode
    $report.summary = @{readyHosts=$result.readyHosts; freeSessionSlots=$result.freeSessionSlots; hostCount=$hosts.Count}
    $report.findings = @($result.findings)
    $report.hosts = @($hosts | ForEach-Object {
        @{name=$_.name; powerState=$_.powerState; status=$_.properties.status; sessions=$_.properties.sessions
          allowNewSession=$_.properties['allowNewSession']; lastHeartBeat=$_.properties['lastHeartBeat']
          agentVersion=$_.properties['agentVersion']; collectionError=$_.collectionError}
    })
    $report.status = if (@($result.findings | Where-Object severity -eq 'Error').Count) {'Error'}
        elseif (@($result.findings | Where-Object severity -eq 'Warning').Count) {'Warning'} else {'Healthy'}
    $failed = $report.status -eq 'Error' -or ($FailOnWarning -and $report.status -eq 'Warning')
} catch {
    $failed = $true
    $report.status = 'Incomplete'
    $report.findings += @{code='AuditIncomplete'; severity='Error'; resource='audit'; message=$_.Exception.Message}
}
$report.completedUtc = [datetimeoffset]::UtcNow.ToString('o')
$json = $report | ConvertTo-Json -Depth 12 -Compress
Write-Output $json
if ($ReportPath) {
    # Optional local report; Automation's filesystem is temporary. Job output is the primary sink.
    [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath), $json, [Text.UTF8Encoding]::new($false))
}
if ($failed) { throw "AVD audit requires attention. Status: $($report.status). RunId: $($report.runId). See JSON job output." }
