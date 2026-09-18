#Requires -Version 7.4
<# Integration fixtures for the verifier's CLI boundary. No Azure traffic or credentials. #>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$folder = Join-Path ([IO.Path]::GetTempPath()) ("sportfive-runtime-tests-$([guid]::NewGuid())")
$null = New-Item -ItemType Directory -Path $folder
$previousAzFunction = Get-Item Function:az -ErrorAction SilentlyContinue
$global:AvdRuntimeFixture = @{mode='healthy'; calls=0}
function global:az {
    $global:AvdRuntimeFixture.calls++
    $global:LASTEXITCODE = 0
    $arguments = @($args)
    if ($arguments[0] -eq 'account') {
        return (@{id='11111111-1111-1111-1111-111111111111';tenantId='22222222-2222-2222-2222-222222222222'} | ConvertTo-Json -Compress)
    }
    if ($arguments[0] -ne 'rest') { throw 'Unexpected fixture command; no real CLI is called.' }
    $url = $arguments[[array]::IndexOf($arguments,'--url')+1]
    $value = switch -Wildcard ($url) {
        '*runCommands*' {
            $state = if ($global:AvdRuntimeFixture.mode -eq 'bootstrap-failed') { 'Failed' } else { 'Succeeded' }
            @{properties=@{instanceView=@{executionState=$state;exitCode=0}}}; break
        }
        '*sessionHosts*' { @{value=@(@{properties=@{resourceId=$global:AvdRuntimeFixture.vmId}})}; break }
        '*jobs/*/output*' {
            if ($global:AvdRuntimeFixture.mode -eq 'invalid-report') { 'not-json'; break }
            $severity = if ($global:AvdRuntimeFixture.mode -eq 'error-finding') { 'Error' } else { 'Warning' }
            @{schemaVersion='1.0';status='Warning';mode='Configuration';completedUtc='2026-09-13T08:00:00Z';findings=@(@{severity=$severity})}; break
        }
        '*jobs/*' {
            $status = if ($global:AvdRuntimeFixture.mode -eq 'job-failed') { 'Failed' } else { 'Completed' }
            @{properties=@{status=$status}}; break
        }
        'https://api.loganalytics.azure.com/*' { @{tables=@(@{rows=,@(1,1)})}; break }
        default { throw "Unexpected fixture route: $url" }
    }
    return $value | ConvertTo-Json -Depth 15 -Compress
}
try {
    $groupId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-fixture-lab'
    $vmId = "$groupId/providers/Microsoft.Compute/virtualMachines/fixture-00"
    $global:AvdRuntimeFixture.vmId = $vmId
    $poolId = "$groupId/providers/Microsoft.DesktopVirtualization/hostPools/fixture"
    $deployment = @{subscription_id='11111111-1111-1111-1111-111111111111';tenant_id='22222222-2222-2222-2222-222222222222';
        host_pool_id=$poolId;hosts=@{'00'=@{id=$vmId;name='fixture-00'}};automation_account_id="$groupId/providers/Microsoft.Automation/automationAccounts/fixture";
        log_analytics_customer_id='33333333-3333-3333-3333-333333333333';user_access_enabled=$false;audit_schedules_enabled=$false}
    $deployment | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $folder 'deployment.json')
    @{SubscriptionId=$deployment.subscription_id;HostPoolId=$poolId} | ConvertTo-Json | Set-Content (Join-Path $folder 'audit.json')
    foreach ($mode in @('healthy','bootstrap-failed','job-failed','invalid-report','error-finding')) {
        $global:AvdRuntimeFixture.mode=$mode; $global:AvdRuntimeFixture.calls=0
        $reportPath = Join-Path $folder "$mode.json"
        $threw = $false
        try {
            & "$PSScriptRoot/../deployment/Test-AzureDeployment.ps1" -DeploymentPath (Join-Path $folder 'deployment.json') `
                -AuditConfigPath (Join-Path $folder 'audit.json') -ReportPath $reportPath
        } catch { $threw=$true }
        $report = Get-Content $reportPath -Raw | ConvertFrom-Json -AsHashtable
        $expected = $mode -eq 'healthy'
        if ($report.passed -ne $expected -or $threw -eq $expected -or $report.userSignInValidated -or $report.profileIsolationValidated) {
            throw "Runtime fixture failed: $mode"
        }
        if ($mode -eq 'bootstrap-failed' -and $global:AvdRuntimeFixture.calls -ne 2) { throw 'Failed bootstrap did not stop before Automation.' }
        Write-Output "PASS: Runtime verifier $mode"
    }
    Write-Output 'All 5 runtime integration fixtures passed without Azure access.'
} finally {
    Remove-Item Function:az
    if ($previousAzFunction) { Set-Item Function:global:az -Value $previousAzFunction.ScriptBlock }
    Remove-Variable AvdRuntimeFixture -Scope Global
    # Delete only explicitly enumerated fixture files from the unique directory owned by this invocation.
    foreach ($file in Get-ChildItem -LiteralPath $folder -File) { Remove-Item -LiteralPath $file.FullName }
    Remove-Item -LiteralPath $folder
}
