#Requires -Version 7.4
[CmdletBinding()]
param([switch]$Analyze)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem "$root/scripts" -Recurse -File | Where-Object Extension -in @('.ps1','.psm1','.psd1'))
$errors = @()
foreach ($file in $files) {
    $parseErrors = $null
    $tokens = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    $errors += @($parseErrors)
}
if ($errors.Count) { $errors | Format-List; throw 'PowerShell parsing failed.' }
Write-Output "Parsed $($files.Count) PowerShell files."
& "$PSScriptRoot/audit/Test-AvdAudit.ps1"
& "$PSScriptRoot/tests/Test-AuditEdgeCases.ps1"
& "$PSScriptRoot/tests/Test-Deployment.ps1"
& "$PSScriptRoot/tests/Test-DeploymentRuntime.ps1"
# Check the actual bundled runbook that Terraform constructs, including its top-level param block.
$source = Get-Content "$PSScriptRoot/audit/Invoke-AvdAudit.ps1" -Raw
$core = (Get-Content "$PSScriptRoot/audit/AvdAudit.Core.psm1" -Raw).Replace('Export-ModuleMember -Function Get-AvdAuditFindings','')
$bundled = $source.Replace('# INLINE_CORE',$core)
$tokens = $null; $bundleErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($bundled,[ref]$tokens,[ref]$bundleErrors)
if ($bundleErrors.Count -or $ast.ParamBlock.Parameters.Count -ne 7) { throw 'Bundled runbook is invalid.' }
Write-Output 'Bundled Automation runbook parses with expected parameters.'
if ($Analyze) {
    Import-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -ErrorAction Stop
    $issues = @(Invoke-ScriptAnalyzer -Path "$root/scripts" -Recurse -Severity Error)
    if ($issues.Count) { $issues | Format-Table; throw 'PSScriptAnalyzer errors.' }
    Write-Output 'PSScriptAnalyzer: no errors.'
}
