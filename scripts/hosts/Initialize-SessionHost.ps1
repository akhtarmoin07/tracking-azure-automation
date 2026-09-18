#Requires -Version 5.1
#Requires -RunAsAdministrator
<# Invoked by managed VM Run Command. Installers must be pinned and Microsoft signed.
   Does not reboot, log off users, erase local profiles, or repair a registered agent. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationJson,
    [Parameter(Mandatory)][string]$RegistrationToken
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$config = $ConfigurationJson | ConvertFrom-Json
if ($config.ProfileUnc -notmatch '^\\\\[a-z0-9]{3,24}\.file\.core\.windows\.net\\[a-z0-9-]+$') {
    throw 'Invalid Azure Files profile UNC.'
}
$work = Join-Path $env:ProgramData 'SPORTFIVE\AVD'
New-Item -ItemType Directory -Path $work -Force | Out-Null
# Local scripts run as SYSTEM. Users must not be able to replace their contents.
& icacls.exe $work /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot secure configuration directory.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Get-VerifiedPackage([string]$Name, [string]$Extension) {
    $package = $config.Packages.$Name
    if ($package.uri -notmatch '^https://' -or $package.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid package manifest.' }
    $destination = Join-Path $work "$Name.$Extension"
    if (-not (Test-Path -LiteralPath $destination) -or
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $package.sha256) {
        Invoke-WebRequest -Uri $package.uri -OutFile $destination -UseBasicParsing
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $package.sha256) {
        throw "Checksum failed for $Name."
    }
    return $destination
}
function Assert-MicrosoftSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw 'Installer must have a valid Microsoft signature.'
    }
}
function Invoke-Installer([string]$Path, [string]$Arguments) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -notin @(0,3010)) { throw "Installer failed with exit code $($process.ExitCode)." }
    if ($process.ExitCode -eq 3010) { Write-Output 'Reboot required during the approved maintenance window.' }
}
# RDAgentBootLoader is the AVD loader. RdAgent alone may refer to a different Azure component.
if (-not (Get-Service RDAgentBootLoader -ErrorAction SilentlyContinue)) {
    $agent = Get-VerifiedPackage 'agent' 'msi'
    $loader = Get-VerifiedPackage 'bootloader' 'msi'
    Assert-MicrosoftSignature $agent
    Assert-MicrosoftSignature $loader
    if ($RegistrationToken -notmatch '^[A-Za-z0-9_.=-]+$') { throw 'Unexpected registration token format.' }
    Invoke-Installer 'msiexec.exe' "/i `"$agent`" /quiet /norestart REGISTRATIONTOKEN=$RegistrationToken"
    Invoke-Installer 'msiexec.exe' "/i `"$loader`" /quiet /norestart"
}
if (-not (Test-Path -LiteralPath 'C:\Program Files\FSLogix\Apps\frxsvc.exe')) {
    $fslogix = Get-VerifiedPackage 'fslogix' 'zip'
    $expanded = Join-Path $work 'fslogix-package'
    Expand-Archive -LiteralPath $fslogix -DestinationPath $expanded -Force
    $setup = Join-Path $expanded 'x64\Release\FSLogixAppsSetup.exe'
    Assert-MicrosoftSignature $setup
    Invoke-Installer $setup '/install /quiet /norestart'
}
$profileKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'
New-Item -Path $profileKey -Force | Out-Null
foreach ($setting in @{
    Enabled=1; IsDynamic=1; SizeInMBs=30000
    PreventLoginWithFailure=1; PreventLoginWithTempProfile=1
    DeleteLocalProfileWhenVHDShouldApply=0; FlipFlopProfileDirectoryName=0
}.GetEnumerator()) {
    New-ItemProperty -Path $profileKey -Name $setting.Key -Value $setting.Value -PropertyType DWord -Force | Out-Null
}
New-ItemProperty -Path $profileKey -Name VolumeType -Value VHDX -PropertyType String -Force | Out-Null
New-ItemProperty -Path $profileKey -Name VHDLocations -Value @($config.ProfileUnc) -PropertyType MultiString -Force | Out-Null
$kerberosKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
New-Item -Path $kerberosKey -Force | Out-Null
New-ItemProperty -Path $kerberosKey -Name CloudKerberosTicketRetrievalEnabled -PropertyType DWord -Value 1 -Force | Out-Null
foreach ($name in @('RDAgentBootLoader','frxsvc','WinHttpAutoProxySvc','iphlpsvc')) {
    if ((Get-Service $name).Status -ne 'Running') { Start-Service $name }
}
$healthPath = Join-Path $work 'Test-SessionHostHealth.ps1'
[IO.File]::WriteAllBytes($healthPath, [Convert]::FromBase64String($config.HealthScriptBase64))
if (-not [Diagnostics.EventLog]::SourceExists('SPORTFIVE-AVD-Health')) {
    New-EventLog -LogName Application -Source 'SPORTFIVE-AVD-Health'
}
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument (
    '-NoProfile -NonInteractive -File "{0}" -ProfileUnc "{1}" -WriteEvent' -f $healthPath, $config.ProfileUnc)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 15)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName 'SPORTFIVE-AVD-Health' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output 'Host configured. Validate Entra join, reboot requirements, AVD status, Kerberos and user profile attachment before admitting users. Review heartbeat telemetry separately.'
