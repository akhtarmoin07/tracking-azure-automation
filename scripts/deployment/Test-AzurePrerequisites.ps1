#Requires -Version 7.4
<# Read-only. Does not select a different default account or register providers. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath, [string]$ReportPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AzureCli.psm1" -Force
Import-Module "$PSScriptRoot/AzureDeployment.Core.psm1" -Force
$config = Resolve-AvdDeploymentConfiguration (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable)
$subscription = $config.subscription_id
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name,[bool]$Passed,[string]$Detail) {
    $checks.Add(@{name=$Name; passed=$Passed; detail=$Detail})
}
try {
    $account = Invoke-AvdAzureCli -Arguments @('account','show') -SubscriptionId $subscription
    Add-Check 'ExplicitAccount' ($account.id -eq $subscription -and $account.tenantId -eq $config.tenant_id -and $account.state -eq 'Enabled') 'Subscription and tenant must match the approved configuration.'
    $providers = Invoke-AvdAzureCli -Arguments @('provider','list') -SubscriptionId $subscription
    foreach ($provider in @('Microsoft.Compute','Microsoft.Network','Microsoft.Storage','Microsoft.DesktopVirtualization','Microsoft.Insights','Microsoft.OperationalInsights','Microsoft.Automation','Microsoft.RecoveryServices')) {
        $entry = @($providers | Where-Object { $_['namespace'] -eq $provider })
        Add-Check "Provider:$provider" ($entry.Count -eq 1 -and $entry[0].registrationState -eq 'Registered') 'Must be registered by the subscription platform setup.'
    }
    $skus = @(Invoke-AvdAzureCli -Arguments @('vm','list-skus','--location',$config.location,'--size',$config.vm_size,'--all') -SubscriptionId $subscription |
        Where-Object { $_['name'] -eq $config.vm_size -and $_['resourceType'] -eq 'virtualMachines' })
    $sku = if ($skus.Count -eq 1) { $skus[0] } else { $null }
    $blocked = if ($sku) { @($sku.restrictions | Where-Object { $_['type'] -eq 'Location' }) } else { @('Unknown SKU') }
    Add-Check 'RegionalVmSku' ($null -ne $sku -and $blocked.Count -eq 0) 'Exact SKU must be available without a location restriction.'
    if ($sku) {
        $cores = @($sku.capabilities | Where-Object { $_['name'] -eq 'vCPUs' })
        $existing = @(Invoke-AvdAzureCli -Arguments @('vm','list') -SubscriptionId $subscription | Where-Object {
            $_['resourceGroup'] -ieq "rg-$($config.prefix)-$($config.environment)" -and $_['hardwareProfile']['vmSize'] -eq $config.vm_size -and
            $_['name'] -in @(0..([int]$config.host_count-1) | ForEach-Object { '{0}-{1:00}' -f $config.prefix,$_ })
        })
        $needed = [int]$cores[0].value * [Math]::Max(0,([int]$config.host_count - $existing.Count))
        $usage = Invoke-AvdAzureCli -Arguments @('vm','list-usage','--location',$config.location) -SubscriptionId $subscription
        foreach ($quotaName in @('cores',$sku.family)) {
            $quota = @($usage | Where-Object { $_['name']['value'] -ieq $quotaName })
            Add-Check "Quota:$quotaName" ($quota.Count -eq 1 -and ($quota[0].limit-$quota[0].currentValue) -ge $needed) "Additional hosts require $needed free vCPUs. This does not reserve regional capacity or adopt existing VMs."
        }
    }
    $image = $config.image
    $imagePath = "/subscriptions/$subscription/providers/Microsoft.Compute/locations/$($config.location)/publishers/$($image.publisher)/artifacttypes/vmimage/offers/$($image.offer)/skus/$($image.sku)/versions/$($image.version)?api-version=2024-03-01"
    $null = Invoke-AvdArm -Path $imagePath -SubscriptionId $subscription
    Add-Check 'PinnedImageExists' $true 'Regional image lookup succeeded; OS/FSLogix suitability still needs release acceptance.'
    foreach ($id in @($config.finance_group_object_id,$config.profile_admin_group_object_id)) {
        $group = Invoke-AvdAzureCli -Arguments @('ad','group','show','--group',$id) -SubscriptionId $subscription
        Add-Check 'SecurityGroup' ($group.securityEnabled -eq $true) 'Configured group resolves in the intended tenant.'
    }
    $principal = Invoke-AvdAzureCli -Arguments @('ad','sp','show','--id',$config.avd_service_principal_object_id) -SubscriptionId $subscription
    Add-Check 'AvdServicePrincipal' ($principal.appId -eq '9cdead84-a844-4324-93f2-b2e6bb768d07') 'Object ID must belong to the Azure Virtual Desktop enterprise application.'
} catch { Add-Check 'PreflightRead' $false $_.Exception.Message }
$passed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
$report = @{schemaVersion='1.0'; completedUtc=[datetimeoffset]::UtcNow.ToString('o'); passed=$passed; checks=$checks.ToArray()}
$json = $report | ConvertTo-Json -Depth 8
if ($ReportPath) { [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath),$json) }
Write-Output $json
if (-not $passed) { throw 'Azure preflight failed; no deployment was attempted.' }
