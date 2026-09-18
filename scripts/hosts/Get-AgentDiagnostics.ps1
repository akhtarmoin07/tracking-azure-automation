#Requires -Version 5.1
<# Run on the Windows session host (elevated or VM Run Command), not Linux Cloud Shell.
   Collects evidence without restarting services or changing registration. #>
[CmdletBinding()]
param([ValidatePattern('^[A-Za-z0-9.-]+\.wvd\.microsoft\.com$')][string]$BrokerHost)
$ErrorActionPreference = 'Stop'
$services = @(Get-CimInstance Win32_Service | Where-Object {
    $_.Name -in @('RdAgent','RDAgentBootLoader','frxsvc')
} | Select-Object Name,State,StartMode,ProcessId,PathName)
$processes = foreach ($service in $services) {
    if ($service.ProcessId -gt 0) {
        Get-Process -Id $service.ProcessId -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,StartTime,Path
    }
}
$locations = @('C:\ProgramData\Microsoft\RDInfraAgent','C:\Program Files\Microsoft RDInfra','C:\ProgramData\FSLogix\Logs\Profile')
$logs = foreach ($path in $locations) {
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 10 FullName,LastWriteTimeUtc,Length
    }
}
$result = [ordered]@{
    collectedUtc=[datetimeoffset]::UtcNow.ToString('o'); computer=$env:COMPUTERNAME
    timeZone=(Get-TimeZone).Id; services=$services; processes=@($processes); recentLogs=@($logs)
    note='A service name/process name alone does not prove AVD agent liveness; correlate AVD heartbeat and health checks.'
}
if ($BrokerHost) { $result.brokerTcp443 = Test-NetConnection -ComputerName $BrokerHost -Port 443 -InformationLevel Quiet }
$result | ConvertTo-Json -Depth 6
