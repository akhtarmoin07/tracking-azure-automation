#Requires -Version 5.1
<# Local read-only service/DNS/TCP probe. SYSTEM cannot prove a user's Kerberos or profile access.
   Optional WriteEvent emits evidence through Application -> AMA -> Event table. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\\\\[a-z0-9]{3,24}\.file\.core\.windows\.net\\[a-z0-9-]+$')][string]$ProfileUnc,
    [switch]$WriteEvent
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$findings = [Collections.Generic.List[string]]::new()
$server = $ProfileUnc.Split('\')[2]
$services = foreach ($name in @('RDAgentBootLoader','frxsvc','WinHttpAutoProxySvc','iphlpsvc')) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne 'Running') { $findings.Add("ServiceUnavailable:$name") }
    [pscustomobject]@{name=$name; status=if ($service) { [string]$service.Status } else { 'Missing' }}
}
try {
    $addresses = @([Net.Dns]::GetHostAddresses($server) | ForEach-Object IPAddressToString)
    if ($addresses.Count -eq 0) { throw 'Empty DNS response' }
} catch { $addresses = @(); $findings.Add('StorageDnsFailed') }
$client = [Net.Sockets.TcpClient]::new()
try {
    $connect = $client.ConnectAsync($server,445)
    if (-not $connect.Wait(10000) -or -not $client.Connected) { throw 'SMB connection failed' }
} catch { $findings.Add('StorageSmbUnreachable') } finally { $client.Dispose() }
try {
    $profile = Get-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles'
    if ($profile.Enabled -ne 1 -or @($profile.VHDLocations) -notcontains $ProfileUnc) { $findings.Add('FSLogixConfigurationDrift') }
    $kerberos = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
    if ($kerberos.CloudKerberosTicketRetrievalEnabled -ne 1) { $findings.Add('KerberosConfigurationDrift') }
} catch { $findings.Add('ConfigurationUnavailable') }
$report = [ordered]@{
    schemaVersion='1.0'; completedUtc=[datetimeoffset]::UtcNow.ToString('o')
    computer=$env:COMPUTERNAME; status=if ($findings.Count) { 'Error' } else { 'Healthy' }
    services=@($services); storageAddresses=$addresses; findings=$findings.ToArray()
    scope='Local service, registry, DNS and TCP only; no user profile attachment test.'
}
$json = $report | ConvertTo-Json -Depth 6 -Compress
Write-Output $json
if ($WriteEvent) {
    $kind = if ($findings.Count) { 'Error' } else { 'Information' }
    Write-EventLog -LogName Application -Source 'SPORTFIVE-AVD-Health' -EventId 4100 -EntryType $kind -Message $json
}
if ($findings.Count) { throw 'Local AVD health check failed; see JSON findings.' }
