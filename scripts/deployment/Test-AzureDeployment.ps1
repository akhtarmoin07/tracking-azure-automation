#Requires -Version 7.4
<# Starts a read-only Automation audit and verifies deployed host/bootstrap and telemetry evidence. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DeploymentPath,
    [Parameter(Mandatory)][string]$AuditConfigPath,
    [Parameter(Mandatory)][string]$ReportPath,
    [ValidateRange(1,60)][int]$TimeoutMinutes = 30
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AzureCli.psm1" -Force
Import-Module "$PSScriptRoot/AzureDeployment.Core.psm1" -Force
$deployment = Get-Content -LiteralPath $DeploymentPath -Raw | ConvertFrom-Json -AsHashtable
$audit = Get-Content -LiteralPath $AuditConfigPath -Raw | ConvertFrom-Json -AsHashtable
$subscription = $deployment.subscription_id
$checks = [Collections.Generic.List[object]]::new()
$started = [datetimeoffset]::UtcNow
$deadline = $started.AddMinutes($TimeoutMinutes)
function Wait-ForEvidence([string]$Name,[scriptblock]$Probe) {
    do {
        if (& $Probe) { $checks.Add(@{name=$Name; passed=$true}); return }
        if ([datetimeoffset]::UtcNow -ge $deadline) { throw "Timed out waiting for $Name. Re-run Verify after correcting the reported issue." }
        Write-Host "Waiting for $Name..."
        Start-Sleep -Seconds 20
    } while ($true)
}
try {
    $account = Invoke-AvdAzureCli -Arguments @('account','show') -SubscriptionId $subscription
    if ($account.id -ne $subscription -or $account.tenantId -ne $deployment.tenant_id -or
        $audit.SubscriptionId -ne $subscription -or $audit.HostPoolId -ne $deployment.host_pool_id) { throw 'Deployment, audit and Azure account scope differ.' }
    if ($deployment.hosts.Count -lt 1) { throw 'Deployment output contains no expected hosts.' }
    foreach ($vm in $deployment.hosts.Values) {
        Wait-ForEvidence "Bootstrap:$($vm.name)" {
            $result = Invoke-AvdArm -SubscriptionId $subscription -Path "$($vm.id)/runCommands/Configure-SPORTFIVE?api-version=2024-07-01&`$expand=instanceView"
            $view = $result['properties']['instanceView']
            if (-not $view) { return $false }
            if ($view['executionState'] -in @('Failed','Canceled','TimedOut') -or
                ($view['executionState'] -eq 'Succeeded' -and $view['exitCode'] -ne 0)) { throw "Guest bootstrap failed on $($vm.name). Inspect managed Run Command instanceView." }
            return $view['executionState'] -eq 'Succeeded' -and $view['exitCode'] -eq 0
        }
    }
    $script:registered = @()
    Wait-ForEvidence 'EveryExpectedHostRegistered' {
        $items = [Collections.Generic.List[object]]::new()
        $path = "$($deployment.host_pool_id)/sessionHosts?api-version=2024-04-03"
        $seen = [Collections.Generic.HashSet[string]]::new()
        while ($path) {
            if (-not $seen.Add($path) -or $seen.Count -gt 1000) { throw 'Invalid session-host pagination.' }
            $page = Invoke-AvdArm -SubscriptionId $subscription -Path $path
            foreach ($item in $page['value']) { $items.Add($item) }
            $path = $page['nextLink']
        }
        $script:registered = $items.ToArray()
        $ids = @($script:registered | ForEach-Object { $_['properties']['resourceId'] })
        return @($deployment.hosts.Values | Where-Object { $_.id -notin $ids }).Count -eq 0
    }
    # Configuration mode works outside peak hours without starting deallocated hosts.
    $jobId = [guid]::NewGuid().ToString()
    $jobPath = "$($deployment.automation_account_id)/jobs/$jobId"
    $null = Invoke-AvdArm -SubscriptionId $subscription -Method put -Path "${jobPath}?api-version=2024-10-23" -Body @{
        properties = @{runbook=@{name='Invoke-AvdAudit'}; parameters=@{
            configjson=($audit | ConvertTo-Json -Depth 10 -Compress); mode='Configuration'; authentication='ManagedIdentity'; failonwarning='false'
        }}
    }
    Wait-ForEvidence 'ManagedIdentityAuditCompleted' {
        $job = Invoke-AvdArm -SubscriptionId $subscription -Path "${jobPath}?api-version=2024-10-23"
        $status = $job['properties']['status']
        if ($status -in @('Failed','Suspended','Stopped')) { throw "Automation job $jobId ended with $status. Inspect its output/errors; identity propagation may need time." }
        return $status -eq 'Completed'
    }
    $runtime = Invoke-AvdArm -SubscriptionId $subscription -Path "$jobPath/output?api-version=2024-10-23"
    if ($runtime -is [string]) { $runtime = $runtime | ConvertFrom-Json -AsHashtable }
    if ($runtime -isnot [hashtable] -or -not (Test-AvdRuntimeReport $runtime)) { throw 'Audit output is missing, incomplete or reports an error.' }
    $checks.Add(@{name='AuditReport'; passed=$true; report=$runtime; jobId=$jobId})

    # Require Perf from every expected VM and output from this exact audit job.
    # AMA telemetry freshness is separate from the AVD lastHeartBeat warning policy.
    $hostIds = @($deployment.hosts.Values | ForEach-Object { $_.id.ToLowerInvariant() }) | ConvertTo-Json -Compress -AsArray
    $query = @"
let expected = dynamic($hostIds);
let hostCount = toscalar(Perf | where TimeGenerated > ago(45m) | where tolower(_ResourceId) in (expected) | summarize dcount(tolower(_ResourceId)));
let jobCount = toscalar(AzureDiagnostics | where TimeGenerated > ago(45m) | where Category == 'JobStreams' and StreamType_s == 'Output' | where tostring(JobId_g) == '$jobId' | count);
print hostCount=hostCount, jobCount=jobCount
"@
    $queryFile = Join-Path ([IO.Path]::GetTempPath()) ("sf-avd-query-$([guid]::NewGuid()).json")
    try {
        [IO.File]::WriteAllText($queryFile,(@{query=$query} | ConvertTo-Json -Compress))
        Wait-ForEvidence 'HostAndAuditTelemetryIngested' {
            # A new workspace may not have tables yet. Keep the failure visible and retry within the deadline.
            try {
                $logs = Invoke-AvdAzureCli -SubscriptionId $subscription -Arguments @('rest','--method','post','--resource','https://api.loganalytics.io',
                    '--url',"https://api.loganalytics.azure.com/v1/workspaces/$($deployment.log_analytics_customer_id)/query",'--body',"@$queryFile")
                if ($logs['error'] -or -not $logs['tables'] -or -not $logs['tables'][0]['rows']) { return $false }
                $row = $logs['tables'][0]['rows'][0]
                return [int]$row[0] -eq $deployment.hosts.Count -and [int]$row[1] -gt 0
            } catch { Write-Warning $_.Exception.Message; return $false }
        }
    } finally { if (Test-Path -LiteralPath $queryFile) { Remove-Item -LiteralPath $queryFile } }
} catch { $checks.Add(@{name='RuntimeVerification'; passed=$false; detail=$_.Exception.Message}) }
$passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
$report = @{schemaVersion='1.0'; startedUtc=$started.ToString('o'); completedUtc=[datetimeoffset]::UtcNow.ToString('o');
    passed=$passed; checks=$checks.ToArray(); userSignInValidated=$false; profileIsolationValidated=$false;
    userAccessEnabled=$deployment.user_access_enabled; auditSchedulesEnabled=$deployment.audit_schedules_enabled}
[IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath),($report | ConvertTo-Json -Depth 20))
if (-not $passed) { throw "Azure runtime verification failed. See $ReportPath. Resources are retained for investigation." }
Write-Host "Infrastructure verification passed. Evidence: $ReportPath. User sign-in/profile acceptance remains a separate pilot check."
