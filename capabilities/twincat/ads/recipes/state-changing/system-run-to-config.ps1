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

# CAPABILITY: Request TwinCAT system transition Run -> Config
# SAFETY: STATE_CHANGING
# VERIFICATION: EXPERIMENTAL; FINAL CONFIG READBACK NOT YET PRESERVED
# This changes runtime state and can alter physical plant behavior.

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
    if ($before.AdsState -ne [TwinCAT.Ads.AdsState]::Run) {
        throw "Expected TwinCAT Run state, actual state: $($before.AdsState)"
    }

    [PSCustomObject]@{
        Phase       = 'Before'
        AdsState    = $before.AdsState
        DeviceState = $before.DeviceState
    }

    $newState = New-Object TwinCAT.Ads.StateInfo(
        [TwinCAT.Ads.AdsState]::Reconfig,
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
    if ($after.AdsState -ne [TwinCAT.Ads.AdsState]::Config) {
        throw "TwinCAT did not reach Config state; actual state: $($after.AdsState)"
    }
}
finally {
    $check.Dispose()
}
