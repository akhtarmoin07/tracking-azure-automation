#Requires -Version 5.1
<# Runs on a new session host via Run Command. Uses its temporary share-scoped identity role; no account keys.
   Only an empty share can be initialized. Existing expected ACLs are verified without rewriting profiles. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigurationJson)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$config = $ConfigurationJson | ConvertFrom-Json
if ($config.Account -notmatch '^[a-z0-9]{3,24}$' -or $config.Share -ne 'profiles') { throw 'Unexpected profile endpoint.' }
foreach ($sid in @($config.FinanceSid,$config.AdminSid)) {
    if ($sid -notmatch '^S-1-(5-21|12-1)-\d+-\d+-\d+-\d+$') { throw 'Use a directory-supplied user/group SID.' }
}
if ($config.FinanceSid -eq $config.AdminSid) { throw 'Finance and profile administration must use separate groups.' }
$base = "https://$($config.Account).file.core.windows.net/$($config.Share)"
$token = Invoke-RestMethod -Headers @{Metadata='true'} -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F'
$headers = @{Authorization="Bearer $($token.access_token)";'x-ms-version'='2023-11-03';'x-ms-file-request-intent'='backup'}
function Invoke-FileRequest([string]$Suffix,[string]$Method='GET',[hashtable]$Extra=@{}) {
    $requestHeaders = @{} + $headers + @{'x-ms-date'=[datetime]::UtcNow.ToString('R')}
    foreach ($key in $Extra.Keys) { $requestHeaders[$key]=$Extra[$key] }
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        try { return Invoke-WebRequest -UseBasicParsing -Uri ($base+$Suffix) -Method $Method -Headers $requestHeaders -ErrorAction Stop }
        catch {
            $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
            if ($status -notin @(403,429,500,503) -or $attempt -eq 19) { throw "Azure Files request failed (HTTP $status). Check identity propagation, private DNS and role assignment." }
            Start-Sleep -Seconds 15
        }
    }
}
# Finance: list/traverse/read and create directories on root only. Creator owner: modify descendants.
$sddl = "O:$($config.AdminSid)G:$($config.AdminSid)D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;$($config.AdminSid))(A;;0x1200ad;;;$($config.FinanceSid))(A;OICIIO;0x1301bf;;;CO)"
function Normalize-Sddl([string]$Value) {
    return ([Security.AccessControl.RawSecurityDescriptor]::new($Value)).GetSddlForm([Security.AccessControl.AccessControlSections]::All)
}
function Read-RootPermission {
    $properties = Invoke-FileRequest '/?restype=directory'
    $key = [string]$properties.Headers['x-ms-file-permission-key']
    if (-not $key) { throw 'Root permission key is missing.' }
    $permission = Invoke-FileRequest ("?restype=share&comp=filepermission&filepermissionkey="+[uri]::EscapeDataString($key))
    return (ConvertFrom-Json $permission.Content).permission
}
$before = Read-RootPermission
$changed = $false
if ((Normalize-Sddl $before) -ne (Normalize-Sddl $sddl)) {
    $listing = Invoke-FileRequest '/?restype=directory&comp=list&maxresults=1'
    [xml]$xml = $listing.Content
    $next = $xml.SelectSingleNode('//NextMarker')
    if ($xml.SelectNodes('//Entries/*').Count -gt 0 -or ($null -ne $next -and $next.InnerText)) {
        throw 'Profile share is populated and ACL differs. Refusing to change existing user data permissions.'
    }
    $null = Invoke-FileRequest '/?restype=directory&comp=properties' 'PUT' @{
        'x-ms-file-permission'=$sddl; 'x-ms-file-attributes'='preserve';
        'x-ms-file-creation-time'='preserve'; 'x-ms-file-last-write-time'='preserve'
    }
    $changed = $true
}
$after = Read-RootPermission
if ((Normalize-Sddl $after) -ne (Normalize-Sddl $sddl)) { throw 'Root permission readback does not match the expected isolated policy.' }
@{schemaVersion='1.0';passed=$true;changed=$changed;before=$before;after=$after;scope='empty-profile-share-root'} | ConvertTo-Json -Compress
