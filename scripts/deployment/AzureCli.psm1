Set-StrictMode -Version Latest
function Invoke-AvdAzureCli {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$SubscriptionId)
    # Argument arrays and @file JSON payloads; no shell-built commands or printed tokens.
    $result = & az @Arguments --subscription $SubscriptionId --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0]). Check the preceding error and explicit target subscription." }
    if ($result) { return ($result -join "`n") | ConvertFrom-Json -AsHashtable }
}
function Invoke-AvdArm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [ValidateSet('get','put','post')][string]$Method='get',
        [hashtable]$Body
    )
    $uri = [uri]::new([uri]'https://management.azure.com',$Path)
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'management.azure.com' -or $uri.Port -ne 443 -or $uri.UserInfo -or
        $uri.AbsolutePath -notlike "/subscriptions/$SubscriptionId/*") { throw 'Rejected ARM request outside the explicit subscription.' }
    $arguments = @('rest','--method',$Method,'--url',$uri.AbsoluteUri)
    $payload = $null
    try {
        if ($Body) {
            $payload = Join-Path ([IO.Path]::GetTempPath()) ("sf-avd-$([guid]::NewGuid()).json")
            [IO.File]::WriteAllText($payload,($Body | ConvertTo-Json -Depth 30 -Compress))
            $arguments += @('--body',"@$payload")
        }
        Invoke-AvdAzureCli -Arguments $arguments -SubscriptionId $SubscriptionId
    } finally {
        if ($payload -and (Test-Path -LiteralPath $payload)) { Remove-Item -LiteralPath $payload }
    }
}
Export-ModuleMember -Function Invoke-AvdAzureCli,Invoke-AvdArm
