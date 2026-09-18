#Requires -Version 7.4
<# Shared post-apply path for local and CI deployment. A failed stage prevents first publication. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InfraDirectory,
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][string]$ActivationConfigPath,
    [string]$Terraform = 'terraform',
    [ValidateRange(1,60)][int]$VerificationTimeoutMinutes = 30
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AzureDeployment.Core.psm1" -Force
Import-Module "$PSScriptRoot/AzureCli.psm1" -Force
$infra = (Resolve-Path -LiteralPath $InfraDirectory).Path
$artifact = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
$activation = (Resolve-Path -LiteralPath $ActivationConfigPath).Path
function Invoke-Terraform([string[]]$Arguments,[switch]$Capture) {
    if ($Capture) { $result = & $Terraform "-chdir=$infra" @Arguments }
    else { & $Terraform "-chdir=$infra" @Arguments | Out-Host }
    if ($LASTEXITCODE -ne 0) { throw "Terraform $($Arguments[0]) failed." }
    if ($Capture) { return $result -join "`n" }
}
function Export-Deployment {
    foreach ($name in 'deployment','audit_config') {
        $json = Invoke-Terraform -Arguments @('output','-json',$name) -Capture
        [IO.File]::WriteAllText((Join-Path $artifact "$name.json"),$json)
    }
}
Export-Deployment
$deploymentPath = Join-Path $artifact 'deployment.json'
& "$PSScriptRoot/Initialize-ProfileAccess.ps1" -DeploymentPath $deploymentPath -ReportPath (Join-Path $artifact 'profile-access.json')
& "$PSScriptRoot/Test-AzureDeployment.ps1" -DeploymentPath $deploymentPath -AuditConfigPath (Join-Path $artifact 'audit_config.json') `
    -ReportPath (Join-Path $artifact 'verification.json') -TimeoutMinutes $VerificationTimeoutMinutes
$desired = Get-Content -LiteralPath $activation -Raw | ConvertFrom-Json -AsHashtable
$current = Get-Content -LiteralPath $deploymentPath -Raw | ConvertFrom-Json -AsHashtable
if ($desired.enable_user_access) {
    # The tenant security owner also confirms the storage-app CA policy described in the identity guide.
    $sp = Invoke-AvdAzureCli -SubscriptionId $current.subscription_id -Arguments @('ad','sp','show','--id','270efc09-cd0d-444b-a71f-39af4910ec45')
    $rdp = Invoke-AvdAzureCli -SubscriptionId $current.subscription_id -Arguments @('rest','--method','get',
        '--url',"https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/remoteDesktopSecurityConfiguration")
    if ($rdp['isRemoteDesktopProtocolEnabled'] -ne $true) { throw 'Tenant Windows Cloud Login RDP authentication is not enabled. Complete the identity prerequisites before publishing.' }
}
if ($desired.enable_user_access -ne $current.user_access_enabled -or $desired.enable_audit_schedules -ne $current.audit_schedules_enabled) {
    $planPath = Join-Path $artifact 'activation.tfplan'
    Invoke-Terraform @('plan','-input=false',"-var-file=$activation","-out=$planPath")
    $plan = Invoke-Terraform -Arguments @('show','-json',$planPath) -Capture | ConvertFrom-Json -AsHashtable
    Assert-AvdActivationPlan $plan
    $plan = $null
    Invoke-Terraform @('apply','-input=false',$planPath)
    Export-Deployment
}
$final = Get-Content -LiteralPath $deploymentPath -Raw | ConvertFrom-Json -AsHashtable
if ($final.user_access_enabled -ne $desired.enable_user_access -or $final.audit_schedules_enabled -ne $desired.enable_audit_schedules) {
    throw 'Final publication settings do not match the requested configuration.'
}
[IO.File]::WriteAllText((Join-Path $artifact 'completion.json'),(@{
    schemaVersion='1.0';completedUtc=[datetimeoffset]::UtcNow.ToString('o');passed=$true
    userAccessEnabled=$final.user_access_enabled;auditSchedulesEnabled=$final.audit_schedules_enabled
    userSignInValidated=$false;profileIsolationValidated=$false;performanceValidated=$false
} | ConvertTo-Json))
Write-Host "Deployment sequence completed. Evidence: $artifact. Real-user acceptance remains required."
