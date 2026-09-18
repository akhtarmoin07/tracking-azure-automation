#Requires -Version 7.4
<# Local entry point. Plan is read-only for workload resources; Deploy applies the saved plan then verifies it. #>
[CmdletBinding()]
param(
    [ValidateSet('Plan','Deploy','Verify')][string]$Mode = 'Plan',
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [string]$Terraform = 'terraform',
    [ValidateRange(1,60)][int]$VerificationTimeoutMinutes = 30
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AzureDeployment.Core.psm1" -Force
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$work = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkingDirectory)
# Working copy keeps provider cache, state metadata and sensitive plans out of this OneDrive source tree.
$sourceRoot = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ([IO.Path]::GetFullPath($work).TrimEnd([IO.Path]::DirectorySeparatorChar) -eq $sourceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) -or
    [IO.Path]::GetFullPath($work).StartsWith($sourceRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Use a private working directory outside the source repository.' }
$null = New-Item -ItemType Directory -Path $work -Force
$infra = Join-Path $work 'infra'
$null = New-Item -ItemType Directory -Path $infra -Force
$artifact = Join-Path $work ("artifacts/" + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$null = New-Item -ItemType Directory -Path $artifact -Force
$lock = $null
try {
    $lock = [IO.File]::Open((Join-Path $work '.deployment.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    # Synchronize only owned source files, preserving Terraform backend/cache in the work directory.
    $manifestPath = Join-Path $work 'source-manifest.json'
    $sources = @('infra','scripts','monitoring') | ForEach-Object {
        Get-ChildItem (Join-Path $root $_) -Recurse -File | Where-Object {
            $_.FullName -notmatch '[\\/]\.terraform[\\/]' -and
            ($_.Extension -in @('.tf','.ps1','.psm1','.psd1','.kql') -or $_.Name -in @('.terraform.lock.hcl','terraform.tfvars') -or $_.Name -like '*.tftest.hcl')
        }
    }
    $relative = @($sources | ForEach-Object { [IO.Path]::GetRelativePath($root,$_.FullName) })
    if (Test-Path -LiteralPath $manifestPath) {
        foreach ($old in @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)) {
            if ($old -notin $relative) {
                $target = [IO.Path]::GetFullPath((Join-Path $work $old))
                if (-not $target.StartsWith(([IO.Path]::GetFullPath($work).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid source manifest path.' }
                if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target }
            }
        }
    }
    foreach ($file in $sources) {
        $target = Join-Path $work ([IO.Path]::GetRelativePath($root,$file.FullName))
        $null = New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
    [IO.File]::WriteAllText($manifestPath,($relative | ConvertTo-Json -AsArray))
    $resolvedPath = Join-Path $artifact 'resolved.tfvars.json'
    $activationPath = Join-Path $artifact 'activation.tfvars.json'
    function Invoke-Terraform([string[]]$Arguments,[switch]$Capture) {
        if ($Capture) { $value = & $Terraform "-chdir=$infra" @Arguments }
        else { & $Terraform "-chdir=$infra" @Arguments | Out-Host }
        if ($LASTEXITCODE -ne 0) { throw "Terraform $($Arguments[0]) failed (exit $LASTEXITCODE)." }
        if ($Capture) { return $value -join "`n" }
    }
    & "$root/scripts/Test-Repository.ps1" | Out-Host
    Invoke-Terraform @('init','-input=false','-lockfile=readonly')
    Invoke-Terraform @('validate')
    if ($Mode -ne 'Verify') {
        & "$PSScriptRoot/Prepare-TerraformConfiguration.ps1" -InfraDirectory $infra -OutputPath $resolvedPath -ActivationOutputPath $activationPath -Terraform $Terraform
        & "$PSScriptRoot/Test-AzurePrerequisites.ps1" -ConfigPath $resolvedPath -ReportPath (Join-Path $artifact 'preflight.json') | Out-Host
        $planPath = Join-Path $artifact 'reviewed.tfplan'
        Invoke-Terraform @('plan','-input=false',"-var-file=$resolvedPath","-out=$planPath")
        $plan = Invoke-Terraform -Arguments @('show','-json',$planPath) -Capture | ConvertFrom-Json -AsHashtable
        Assert-AvdPlanHasNoDeletion $plan
        $plan = $null # Never serialize or print the unsanitized plan JSON.
        if ($Mode -eq 'Plan') { Write-Host "Plan complete: $planPath. Deploy creates a fresh plan and applies that exact plan."; return }
        Invoke-Terraform @('apply','-input=false',$planPath)
        & "$PSScriptRoot/Complete-Deployment.ps1" -InfraDirectory $infra -ArtifactDirectory $artifact -ActivationConfigPath $activationPath `
            -Terraform $Terraform -VerificationTimeoutMinutes $VerificationTimeoutMinutes
        return
    }
    foreach ($name in @('deployment','audit_config')) {
        $json = Invoke-Terraform -Arguments @('output','-json',$name) -Capture
        [IO.File]::WriteAllText((Join-Path $artifact "$name.json"),$json)
    }
    $deployed = Get-Content (Join-Path $artifact 'deployment.json') -Raw | ConvertFrom-Json -AsHashtable
    if (-not $deployed.subscription_id -or -not $deployed.tenant_id) { throw 'Backend outputs have no deployment identity.' }
    & "$PSScriptRoot/Test-AzureDeployment.ps1" -DeploymentPath (Join-Path $artifact 'deployment.json') `
        -AuditConfigPath (Join-Path $artifact 'audit_config.json') -ReportPath (Join-Path $artifact 'verification.json') -TimeoutMinutes $VerificationTimeoutMinutes
} finally { if ($lock) { $lock.Dispose() } }
