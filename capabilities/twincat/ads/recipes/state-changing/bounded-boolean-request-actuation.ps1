[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [switch]$HumanApproved,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EnterModeRequestSymbol,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ModeAcknowledgementSymbol,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ActivateRequestSymbol,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ActiveAcknowledgementSymbol,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DeactivateRequestSymbol,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ExitModeRequestSymbol,

    [Parameter(Mandatory)]
    [ValidateSet('Run')]
    [string]$ExpectedAdsState,

    [ValidateRange(1, 300)]
    [int]$HoldSeconds = 5,

    [ValidateRange(10, 60000)]
    [int]$PulseMilliseconds = 100,

    [ValidateRange(0, 300)]
    [int]$AcknowledgementTimeoutSeconds = 5,

    [ValidateRange(10, 60000)]
    [int]$PollIntervalMilliseconds = 100,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 851,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Execute a bounded Boolean actuation through functional request/acknowledgement handshakes
# SAFETY: STATE_CHANGING
# VERIFICATION: EXPERIMENTAL WRAPPER; THE COMPOSED REQUEST PATTERN WAS VERIFIED IN ONE SUPERVISED TWINCAT ADS ENVIRONMENT

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $HumanApproved) {
    throw 'STATE-CHANGING CAPABILITY BLOCKED: explicit human approval and a verified safe plant state are required.'
}

$operationSymbols = @(
    $EnterModeRequestSymbol,
    $ModeAcknowledgementSymbol,
    $ActivateRequestSymbol,
    $ActiveAcknowledgementSymbol,
    $DeactivateRequestSymbol,
    $ExitModeRequestSymbol
)
if (@($operationSymbols | Select-Object -Unique).Count -ne 6) {
    throw 'Six distinct request and acknowledgement symbols are required.'
}

Add-Type -LiteralPath $AdsDll

function Wait-BooleanValue {
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Symbol,
        [Parameter(Mandatory)][bool]$Expected,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][int]$PollMilliseconds
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $actual = [bool]$Client.ReadSymbol($Symbol, [System.Boolean], $true)
        if ($actual -eq $Expected) { return $actual }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($true)
    throw "Timed out waiting for '$Symbol'='$Expected'; last value was '$actual'."
}

function Invoke-BooleanRequestTransition {
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$RequestSymbol,
        [Parameter(Mandatory)][string]$AcknowledgementSymbol,
        [Parameter(Mandatory)][bool]$ExpectedInitialAcknowledgement,
        [Parameter(Mandatory)][bool]$ExpectedFinalAcknowledgement,
        [Parameter(Mandatory)][string]$Phase
    )
    $requestInfo = $Client.CreateSymbolInfoLoader().FindSymbol($RequestSymbol)
    $ackInfo = $Client.CreateSymbolInfoLoader().FindSymbol($AcknowledgementSymbol)
    if ($null -eq $requestInfo) { throw "Request symbol '$RequestSymbol' was not found." }
    if ($null -eq $ackInfo) { throw "Acknowledgement symbol '$AcknowledgementSymbol' was not found." }
    if ($requestInfo.IsReadOnly) { throw "Request symbol '$RequestSymbol' is marked read-only." }
    if ([string]$requestInfo.Type -ne 'BOOL') { throw "Request symbol '$RequestSymbol' is not BOOL." }
    if ([string]$ackInfo.Type -ne 'BOOL') { throw "Acknowledgement symbol '$AcknowledgementSymbol' is not BOOL." }

    $requestBefore = [bool]$Client.ReadSymbol($RequestSymbol, [System.Boolean], $true)
    $ackBefore = [bool]$Client.ReadSymbol($AcknowledgementSymbol, [System.Boolean], $true)
    if ($requestBefore) { throw "Request symbol '$RequestSymbol' is already TRUE during $Phase." }
    if ($ackBefore -ne $ExpectedInitialAcknowledgement) {
        throw "Acknowledgement precondition failed during ${Phase}: expected '$ExpectedInitialAcknowledgement', actual '$ackBefore'."
    }

    $requestRaised = $false
    try {
        $Client.WriteSymbol($RequestSymbol, $true, $true)
        $requestRaised = $true
        Start-Sleep -Milliseconds $PulseMilliseconds
    }
    finally {
        if ($requestRaised) {
            $Client.WriteSymbol($RequestSymbol, $false, $true)
        }
    }

    [void](Wait-BooleanValue -Client $Client -Symbol $AcknowledgementSymbol `
        -Expected $ExpectedFinalAcknowledgement -TimeoutSeconds $AcknowledgementTimeoutSeconds `
        -PollMilliseconds $PollIntervalMilliseconds)

    [PSCustomObject]@{
        Phase                 = $Phase
        RequestSymbol         = $RequestSymbol
        RequestValue          = [bool]$Client.ReadSymbol($RequestSymbol, [System.Boolean], $true)
        AcknowledgementSymbol = $AcknowledgementSymbol
        AcknowledgementValue  = [bool]$Client.ReadSymbol($AcknowledgementSymbol, [System.Boolean], $true)
        Verified              = $true
    }
}

function Invoke-BestEffortRestoreTransition {
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$RequestSymbol,
        [Parameter(Mandatory)][string]$AcknowledgementSymbol,
        [Parameter(Mandatory)][string]$Phase
    )
    try {
        $requestCurrent = [bool]$Client.ReadSymbol($RequestSymbol, [System.Boolean], $true)
        if ($requestCurrent) {
            $Client.WriteSymbol($RequestSymbol, $false, $true)
        }
        $current = [bool]$Client.ReadSymbol($AcknowledgementSymbol, [System.Boolean], $true)
        if ($current) {
            Invoke-BooleanRequestTransition -Client $Client -RequestSymbol $RequestSymbol `
                -AcknowledgementSymbol $AcknowledgementSymbol `
                -ExpectedInitialAcknowledgement $true -ExpectedFinalAcknowledgement $false `
                -Phase $Phase | Out-Null
        }
    }
    catch {
        Write-Warning "Best-effort restore failed during ${Phase}: $($_.Exception.Message)"
    }
}

$ads = New-Object TwinCAT.Ads.TcAdsClient
$connected = $false
try {
    $ads.Connect($NetId, $Port)
    $connected = $true
    $runtimeState = $ads.ReadState()
    if ([string]$runtimeState.AdsState -ne $ExpectedAdsState) {
        throw "Expected PLC ADS state '$ExpectedAdsState', actual state: '$($runtimeState.AdsState)'."
    }

    $modeBefore = [bool]$ads.ReadSymbol($ModeAcknowledgementSymbol, [System.Boolean], $true)
    $activeBefore = [bool]$ads.ReadSymbol($ActiveAcknowledgementSymbol, [System.Boolean], $true)
    if ($modeBefore -or $activeBefore) {
        throw "Initial-state precondition failed: mode='$modeBefore', active='$activeBefore'; both must be False."
    }

    [PSCustomObject]@{
        Phase              = 'Before'
        AdsState           = $runtimeState.AdsState
        ModeActive         = $modeBefore
        ActuationActive    = $activeBefore
        HoldSeconds        = $HoldSeconds
    }

    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $EnterModeRequestSymbol `
        -AcknowledgementSymbol $ModeAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $false -ExpectedFinalAcknowledgement $true `
        -Phase 'EnterMode'
    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $ActivateRequestSymbol `
        -AcknowledgementSymbol $ActiveAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $false -ExpectedFinalAcknowledgement $true `
        -Phase 'Activate'
    $holdDeadline = [DateTime]::UtcNow.AddSeconds($HoldSeconds)
    while ([DateTime]::UtcNow -lt $holdDeadline) {
        $activeDuringHold = [bool]$ads.ReadSymbol($ActiveAcknowledgementSymbol, [System.Boolean], $true)
        if (-not $activeDuringHold) {
            throw "Active acknowledgement '$ActiveAcknowledgementSymbol' became False during the bounded hold."
        }
        $remainingMilliseconds = [Math]::Max(1, [Math]::Min(
            $PollIntervalMilliseconds,
            [int][Math]::Ceiling(($holdDeadline - [DateTime]::UtcNow).TotalMilliseconds)
        ))
        Start-Sleep -Milliseconds $remainingMilliseconds
    }

    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $DeactivateRequestSymbol `
        -AcknowledgementSymbol $ActiveAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $true -ExpectedFinalAcknowledgement $false `
        -Phase 'Deactivate'
    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $ExitModeRequestSymbol `
        -AcknowledgementSymbol $ModeAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $true -ExpectedFinalAcknowledgement $false `
        -Phase 'ExitMode'
    [PSCustomObject]@{
        Phase              = 'After'
        AdsState           = $runtimeState.AdsState
        ModeActive         = [bool]$ads.ReadSymbol($ModeAcknowledgementSymbol, [System.Boolean], $true)
        ActuationActive    = [bool]$ads.ReadSymbol($ActiveAcknowledgementSymbol, [System.Boolean], $true)
        HoldSeconds        = $HoldSeconds
        Verified           = $true
    }
}
finally {
    if ($connected) {
        Invoke-BestEffortRestoreTransition -Client $ads -RequestSymbol $DeactivateRequestSymbol `
            -AcknowledgementSymbol $ActiveAcknowledgementSymbol -Phase 'RestoreDeactivate'
        Invoke-BestEffortRestoreTransition -Client $ads -RequestSymbol $ExitModeRequestSymbol `
            -AcknowledgementSymbol $ModeAcknowledgementSymbol -Phase 'RestoreExitMode'
    }
    $ads.Dispose()
}
