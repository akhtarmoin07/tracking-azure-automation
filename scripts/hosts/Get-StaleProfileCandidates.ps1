#Requires -Version 5.1
<# Inventory only. LastWriteTime is not authoritative last logon; never deletes profiles. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\\\\[a-z0-9]{3,24}\.file\.core\.windows\.net\\[a-z0-9-]+$')][string]$ProfileUnc,
    [ValidateRange(30,3650)][int]$RetentionDays=90
)
$ErrorActionPreference = 'Stop'
$cutoff = [datetime]::UtcNow.AddDays(-$RetentionDays)
$candidates = @(Get-ChildItem -LiteralPath $ProfileUnc -File -Recurse -ErrorAction Stop |
    Where-Object { $_.Extension -in @('.vhd','.vhdx') -and $_.LastWriteTimeUtc -lt $cutoff } |
    Select-Object FullName,Length,LastWriteTimeUtc)
[ordered]@{
    collectedUtc=[datetimeoffset]::UtcNow.ToString('o'); retentionDays=$RetentionDays
    candidates=$candidates; action='ReviewOnly'
    requiredReview='Correlate sign-ins, active/disconnected sessions, profile locks, owner, legal retention and a verified backup before any separately approved removal.'
} | ConvertTo-Json -Depth 5
