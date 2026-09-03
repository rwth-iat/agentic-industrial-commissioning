[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [switch]$HumanApproved,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 10000,

    [ValidateRange(0, 300)]
    [int]$WaitSeconds = 5,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Request TwinCAT system transition Config -> Run
# SAFETY: STATE_CHANGING
# This can start runtime behavior and affect physical outputs.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $HumanApproved) {
    throw 'STATE-CHANGING CAPABILITY BLOCKED: explicit human approval and a verified safe plant state are required.'
}

Add-Type -LiteralPath $AdsDll
$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $before = $ads.ReadState()
    if ($before.AdsState -ne [TwinCAT.Ads.AdsState]::Config) {
        throw "Expected TwinCAT Config state, actual state: $($before.AdsState)"
    }

    [PSCustomObject]@{
        Phase       = 'Before'
        AdsState    = $before.AdsState
        DeviceState = $before.DeviceState
    }

    $newState = New-Object TwinCAT.Ads.StateInfo(
        [TwinCAT.Ads.AdsState]::Reset,
        0
    )
    $ads.WriteControl($newState)
}
finally {
    $ads.Dispose()
}

Start-Sleep -Seconds $WaitSeconds
$check = New-Object TwinCAT.Ads.TcAdsClient
try {
    $check.Connect($NetId, $Port)
    $after = $check.ReadState()
    [PSCustomObject]@{
        Phase       = 'After'
        AdsState    = $after.AdsState
        DeviceState = $after.DeviceState
    }
    if ($after.AdsState -ne [TwinCAT.Ads.AdsState]::Run) {
        throw "TwinCAT did not reach Run state; actual state: $($after.AdsState)"
    }
}
finally {
    $check.Dispose()
}
