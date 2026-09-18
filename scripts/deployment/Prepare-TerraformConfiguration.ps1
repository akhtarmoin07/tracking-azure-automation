#Requires -Version 7.4
<# Reads HCL with Terraform itself. Emits only nonsecret resolved inputs, never password/state JSON. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InfraDirectory,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ActivationOutputPath,
    [string]$Terraform = 'terraform'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AzureDeployment.Core.psm1" -Force
$infra = (Resolve-Path -LiteralPath $InfraDirectory).Path
$source = Get-Content (Join-Path $infra 'terraform.tfvars') -Raw
if ($source -match '"[^"\r\n]*REPLACE') { throw 'Complete the marked tenant, image, package and contact inputs in infra/terraform.tfvars.' }
if ($source -match '(?m)^\s*admin_password\s*=') { throw 'Remove admin_password from tfvars; supply TF_VAR_admin_password through your secret store.' }
if (-not $env:TF_VAR_admin_password) { throw 'Supply TF_VAR_admin_password through your secret store.' }
$declarations = Get-Content (Join-Path $infra 'variables.tf') -Raw
$names = @([regex]::Matches($declarations,'(?m)^variable "([a-z][a-z0-9_]*)"') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne 'admin_password' })
$expression = 'jsonencode({' + (($names | ForEach-Object { "${_}=var.$_" }) -join ',') + '})'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("sportfive-inputs-$([guid]::NewGuid())")
$null = New-Item -ItemType Directory -Path $scratch
Copy-Item -LiteralPath (Join-Path $infra 'variables.tf') -Destination (Join-Path $scratch 'variables.tf')
# Parse inputs in a variables-only module: no backend, resource refresh or provider authentication.
$arguments = @("-chdir=$scratch",'console',"-var-file=$(Join-Path $infra 'terraform.tfvars')")
foreach ($pair in @(@('ARM_SUBSCRIPTION_ID','subscription_id'),@('ARM_TENANT_ID','tenant_id'))) {
    $value = [Environment]::GetEnvironmentVariable($pair[0])
    if ($value) { $arguments += "-var=$($pair[1])=$value" }
}
try {
    $encoded = $expression | & $Terraform @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Terraform could not read the configuration. No deployment was attempted.' }
} finally {
    foreach ($file in Get-ChildItem -LiteralPath $scratch -File -Force) { Remove-Item -LiteralPath $file.FullName }
    Remove-Item -LiteralPath $scratch
}
$config = ($encoded -join "`n" | ConvertFrom-Json) | ConvertFrom-Json -AsHashtable
# Verify state ownership and retain the initial budget month on subsequent deployments.
$deployed = @{}
    $previous = & $Terraform "-chdir=$infra" output -json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect existing output identity.' }
    $outputs = $previous -join "`n" | ConvertFrom-Json -AsHashtable
    if ($outputs['deployment']) {
        $deployed = $outputs['deployment']['value']
        if ($deployed['subscription_id'] -ne $config.subscription_id -or $deployed['tenant_id'] -ne $config.tenant_id -or
            $deployed['resource_group'] -ne "rg-$($config.prefix)-$($config.environment)") { throw 'Backend belongs to another target environment.' }
        if (-not $config['budget_start_date'] -and $deployed['budget_start_date']) { $config['budget_start_date'] = $deployed['budget_start_date'] }
    } else {
        $resources = & $Terraform "-chdir=$infra" show -json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect state ownership.' }
        $state = $resources -join "`n" | ConvertFrom-Json -AsHashtable
        if ($state['values']) { throw 'Backend has state without a verifiable deployment identity.' }
    }
$resolved = Resolve-AvdDeploymentConfiguration $config
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$null = New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force
$activation = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ActivationOutputPath)
$null = New-Item -ItemType Directory -Path (Split-Path $activation -Parent) -Force
[IO.File]::WriteAllText($activation,($resolved | ConvertTo-Json -Depth 20))
$provisioning = Get-AvdProvisioningConfiguration -Desired $resolved -Previous $deployed
[IO.File]::WriteAllText($destination,($provisioning | ConvertTo-Json -Depth 20))
Write-Host "Resolved nonsecret configuration: $destination"
