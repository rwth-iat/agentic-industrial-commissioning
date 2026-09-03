[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 10000,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Read TwinCAT system state
# SAFETY: READ_ONLY

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -LiteralPath $AdsDll

$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $state = $ads.ReadState()
    [PSCustomObject]@{
        NetId       = $NetId
        Port        = $Port
        Connected   = $ads.IsConnected
        AdsState    = $state.AdsState
        DeviceState = $state.DeviceState
    }
}
finally {
    $ads.Dispose()
}
