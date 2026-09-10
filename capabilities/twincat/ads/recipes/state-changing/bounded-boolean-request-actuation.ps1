[CmdletBinding()]
param(
    [Parameter(Mandatory)][switch]$HumanApproved,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$EnterModeRequestSymbol,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ModeAcknowledgementSymbol,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ActivateRequestSymbol,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ActiveAcknowledgementSymbol,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DeactivateRequestSymbol,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExitModeRequestSymbol,
    [Parameter(Mandatory)][ValidateSet('Run')][string]$ExpectedAdsState,
    [ValidateRange(1, 300)][int]$HoldSeconds = 5,
    [ValidateRange(10, 60000)][int]$PulseMilliseconds = 100,
    [ValidateRange(0, 300)][int]$AcknowledgementTimeoutSeconds = 5,
    [ValidateRange(10, 60000)][int]$PollIntervalMilliseconds = 100,
    [object[]]$Preconditions = @(),
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$NetId,
    [ValidateRange(1, 65535)][int]$Port = 851,
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$AdsDll
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

$startedAt = [DateTimeOffset]::UtcNow
$events = [System.Collections.Generic.List[object]]::new()
$timeoutTriggered = $false
$initialState = [ordered]@{ known = $false }
$finalState = [ordered]@{ known = $false }
$restoreStatus = 'unknown'
$executionStatus = 'failed'
$writeOccurred = $false
$ads = $null
$connected = $false

function Add-ProbeEvent {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Outcome,
        [string]$Symbol,
        [AllowNull()][object]$Value,
        [string]$Detail
    )

    $event = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        kind = $Kind
        outcome = $Outcome
    }
    if (-not [string]::IsNullOrWhiteSpace($Symbol)) { $event.symbol = $Symbol }
    if ($PSBoundParameters.ContainsKey('Value')) { $event.value = $Value }
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { $event.detail = $Detail }
    $events.Add([PSCustomObject]$event)
}

function Assert-BooleanSymbol {
    param([Parameter(Mandatory)]$Client, [Parameter(Mandatory)][string]$Symbol, [switch]$Writable)

    $info = $Client.CreateSymbolInfoLoader().FindSymbol($Symbol)
    if ($null -eq $info) { throw "Symbol '$Symbol' was not found." }
    if ([string]$info.Type -ne 'BOOL') { throw "Symbol '$Symbol' is not BOOL." }
    if ($Writable -and $info.IsReadOnly) { throw "Request symbol '$Symbol' is marked read-only." }
}

function Read-BooleanValue {
    param([Parameter(Mandatory)]$Client, [Parameter(Mandatory)][string]$Symbol, [string]$Detail = 'Boolean runtime read')

    try {
        $value = [bool]$Client.ReadSymbol($Symbol, [System.Boolean], $true)
        Add-ProbeEvent -Kind 'read' -Outcome 'succeeded' -Symbol $Symbol -Value $value -Detail $Detail
        return $value
    }
    catch {
        Add-ProbeEvent -Kind 'read' -Outcome 'failed' -Symbol $Symbol -Detail $_.Exception.Message
        throw
    }
}

function Write-BooleanValue {
    param([Parameter(Mandatory)]$Client, [Parameter(Mandatory)][string]$Symbol, [Parameter(Mandatory)][bool]$Value, [string]$Detail)

    try {
        $Client.WriteSymbol($Symbol, $Value, $true)
        $script:writeOccurred = $true
        Add-ProbeEvent -Kind 'write' -Outcome 'succeeded' -Symbol $Symbol -Value $Value -Detail $Detail
    }
    catch {
        Add-ProbeEvent -Kind 'write' -Outcome 'failed' -Symbol $Symbol -Value $Value -Detail $_.Exception.Message
        throw
    }
}

function Wait-BooleanValue {
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Symbol,
        [Parameter(Mandatory)][bool]$Expected,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][int]$PollMilliseconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $actual = Read-BooleanValue -Client $Client -Symbol $Symbol -Detail 'Acknowledgement polling read'
        if ($actual -eq $Expected) { return $actual }
        if ([DateTimeOffset]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($true)
    $script:timeoutTriggered = $true
    Add-ProbeEvent -Kind 'timeout' -Outcome 'failed' -Symbol $Symbol -Value $actual `
        -Detail "Timed out waiting for expected value '$Expected'."
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

    Assert-BooleanSymbol -Client $Client -Symbol $RequestSymbol -Writable
    Assert-BooleanSymbol -Client $Client -Symbol $AcknowledgementSymbol
    $requestBefore = Read-BooleanValue -Client $Client -Symbol $RequestSymbol -Detail "$Phase request precondition"
    $ackBefore = Read-BooleanValue -Client $Client -Symbol $AcknowledgementSymbol -Detail "$Phase acknowledgement precondition"
    if ($requestBefore) { throw "Request symbol '$RequestSymbol' is already TRUE during $Phase." }
    if ($ackBefore -ne $ExpectedInitialAcknowledgement) {
        throw "Acknowledgement precondition failed during ${Phase}: expected '$ExpectedInitialAcknowledgement', actual '$ackBefore'."
    }

    $requestRaised = $false
    try {
        Write-BooleanValue -Client $Client -Symbol $RequestSymbol -Value $true -Detail "$Phase request raised"
        $requestRaised = $true
        Start-Sleep -Milliseconds $PulseMilliseconds
    }
    finally {
        if ($requestRaised) {
            Write-BooleanValue -Client $Client -Symbol $RequestSymbol -Value $false -Detail "$Phase request cleared"
        }
    }
    [void](Wait-BooleanValue -Client $Client -Symbol $AcknowledgementSymbol `
        -Expected $ExpectedFinalAcknowledgement -TimeoutSeconds $AcknowledgementTimeoutSeconds `
        -PollMilliseconds $PollIntervalMilliseconds)
}

function Test-AdditionalPreconditions {
    param([Parameter(Mandatory)]$Client)

    $typeMap = @{
        Boolean = [System.Boolean]
        Byte = [System.Byte]
        Int16 = [System.Int16]
        UInt16 = [System.UInt16]
        Int32 = [System.Int32]
        UInt32 = [System.UInt32]
        Single = [System.Single]
        Double = [System.Double]
    }
    foreach ($condition in @($Preconditions)) {
        $symbol = [string]$condition.Symbol
        $type = [string]$condition.Type
        if (-not $typeMap.ContainsKey($type)) { throw "Unsupported precondition type '$type'." }
        $runtimeType = [string]$condition.RuntimeType
        $expectedAdsType = switch ($runtimeType.ToUpperInvariant()) {
            'BOOLEAN' { 'BOOL' }
            'INT16' { 'INT' }
            'UINT16' { 'UINT' }
            'INT32' { 'DINT' }
            'UINT32' { 'UDINT' }
            'SINGLE' { 'REAL' }
            'DOUBLE' { 'LREAL' }
            default { $runtimeType.ToUpperInvariant() }
        }
        $info = $Client.CreateSymbolInfoLoader().FindSymbol($symbol)
        if ($null -eq $info) { throw "Precondition symbol '$symbol' was not found." }
        if ([string]$info.Type -ne $expectedAdsType) {
            throw "Precondition symbol '$symbol' datatype '$($info.Type)' does not match '$expectedAdsType'."
        }
        $actual = $Client.ReadSymbol($symbol, $typeMap[$type], $true)
        Add-ProbeEvent -Kind 'read' -Outcome 'succeeded' -Symbol $symbol -Value $actual -Detail 'Immediate probe precondition read'
        $expectedText = [string]$condition.ExpectedValue
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $expected = switch ($type) {
            'Boolean' {
                $parsed = $false
                if (-not [bool]::TryParse($expectedText, [ref]$parsed)) {
                    throw "Expected precondition '$expectedText' is not Boolean."
                }
                $parsed
            }
            'Byte' { [byte]::Parse($expectedText, $culture) }
            'Int16' { [int16]::Parse($expectedText, $culture) }
            'UInt16' { [uint16]::Parse($expectedText, $culture) }
            'Int32' { [int32]::Parse($expectedText, $culture) }
            'UInt32' { [uint32]::Parse($expectedText, $culture) }
            'Single' { [single]::Parse($expectedText, $culture) }
            'Double' { [double]::Parse($expectedText, $culture) }
        }
        if ($actual -ne $expected) {
            throw "Immediate precondition failed for '$symbol': expected '$expected', actual '$actual'."
        }
    }
}

function Invoke-VerifiedRestore {
    param([Parameter(Mandatory)]$Client)

    try {
        foreach ($requestSymbol in @($EnterModeRequestSymbol, $ActivateRequestSymbol, $DeactivateRequestSymbol, $ExitModeRequestSymbol)) {
            Assert-BooleanSymbol -Client $Client -Symbol $requestSymbol -Writable
            if (Read-BooleanValue -Client $Client -Symbol $requestSymbol -Detail 'Restore request-state read') {
                Write-BooleanValue -Client $Client -Symbol $requestSymbol -Value $false -Detail 'Restore clears active request'
            }
        }
        $active = Read-BooleanValue -Client $Client -Symbol $ActiveAcknowledgementSymbol -Detail 'Restore active-state read'
        if ($active) {
            Invoke-BooleanRequestTransition -Client $Client -RequestSymbol $DeactivateRequestSymbol `
                -AcknowledgementSymbol $ActiveAcknowledgementSymbol `
                -ExpectedInitialAcknowledgement $true -ExpectedFinalAcknowledgement $false `
                -Phase 'RestoreDeactivate'
        }
        $mode = Read-BooleanValue -Client $Client -Symbol $ModeAcknowledgementSymbol -Detail 'Restore mode-state read'
        if ($mode) {
            Invoke-BooleanRequestTransition -Client $Client -RequestSymbol $ExitModeRequestSymbol `
                -AcknowledgementSymbol $ModeAcknowledgementSymbol `
                -ExpectedInitialAcknowledgement $true -ExpectedFinalAcknowledgement $false `
                -Phase 'RestoreExitMode'
        }

        $modeAfter = Read-BooleanValue -Client $Client -Symbol $ModeAcknowledgementSymbol -Detail 'Final mode verification'
        $activeAfter = Read-BooleanValue -Client $Client -Symbol $ActiveAcknowledgementSymbol -Detail 'Final actuation verification'
        if ($modeAfter -or $activeAfter) { throw "Restore readback failed: mode='$modeAfter', active='$activeAfter'." }
        $script:finalState = [ordered]@{ known = $true; mode_active = $modeAfter; actuation_active = $activeAfter }
        Add-ProbeEvent -Kind 'restore' -Outcome 'succeeded' -Detail 'Inactive actuation and inactive mode were verified.'
        return $true
    }
    catch {
        Add-ProbeEvent -Kind 'restore' -Outcome 'failed' -Detail $_.Exception.Message
        return $false
    }
}

function Test-NoWriteFinalState {
    param([Parameter(Mandatory)]$Client)

    try {
        $modeAfter = Read-BooleanValue -Client $Client -Symbol $ModeAcknowledgementSymbol -Detail 'No-write final mode observation'
        $activeAfter = Read-BooleanValue -Client $Client -Symbol $ActiveAcknowledgementSymbol -Detail 'No-write final actuation observation'
        $script:finalState = [ordered]@{ known = $true; mode_active = $modeAfter; actuation_active = $activeAfter }
        if ([bool]$initialState.known -and
            [bool]$initialState.mode_active -eq $modeAfter -and
            [bool]$initialState.actuation_active -eq $activeAfter) {
            Add-ProbeEvent -Kind 'restore' -Outcome 'observed' -Detail 'No write occurred; the observed state remained unchanged.'
            return 'verified'
        }
        Add-ProbeEvent -Kind 'restore' -Outcome 'observed' -Detail 'No write occurred; no known initial state was available for comparison.'
        return 'unknown'
    }
    catch {
        Add-ProbeEvent -Kind 'restore' -Outcome 'failed' -Detail "No-write final observation failed: $($_.Exception.Message)"
        return 'unknown'
    }
}

try {
    Add-Type -LiteralPath $AdsDll
    $ads = New-Object TwinCAT.Ads.TcAdsClient
    $ads.Connect($NetId, $Port)
    $connected = $true
    $runtimeState = $ads.ReadState()
    Add-ProbeEvent -Kind 'runtime_observation' -Outcome 'observed' -Value ([string]$runtimeState.AdsState) -Detail 'PLC ADS state'
    if ([string]$runtimeState.AdsState -ne $ExpectedAdsState) {
        throw "Expected PLC ADS state '$ExpectedAdsState', actual '$($runtimeState.AdsState)'."
    }

    foreach ($symbol in $operationSymbols) {
        Assert-BooleanSymbol -Client $ads -Symbol $symbol -Writable:($symbol -in @(
            $EnterModeRequestSymbol, $ActivateRequestSymbol, $DeactivateRequestSymbol, $ExitModeRequestSymbol
        ))
    }
    Test-AdditionalPreconditions -Client $ads

    $modeBefore = Read-BooleanValue -Client $ads -Symbol $ModeAcknowledgementSymbol -Detail 'Initial mode read'
    $activeBefore = Read-BooleanValue -Client $ads -Symbol $ActiveAcknowledgementSymbol -Detail 'Initial actuation read'
    $initialState = [ordered]@{ known = $true; mode_active = $modeBefore; actuation_active = $activeBefore }
    if ($modeBefore -or $activeBefore) {
        throw "Initial-state precondition failed: mode='$modeBefore', active='$activeBefore'; both must be False."
    }

    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $EnterModeRequestSymbol `
        -AcknowledgementSymbol $ModeAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $false -ExpectedFinalAcknowledgement $true -Phase 'EnterMode'
    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $ActivateRequestSymbol `
        -AcknowledgementSymbol $ActiveAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $false -ExpectedFinalAcknowledgement $true -Phase 'Activate'

    $holdDeadline = [DateTimeOffset]::UtcNow.AddSeconds($HoldSeconds)
    while ([DateTimeOffset]::UtcNow -lt $holdDeadline) {
        if (-not (Read-BooleanValue -Client $ads -Symbol $ActiveAcknowledgementSymbol -Detail 'Bounded hold observation')) {
            throw "Active acknowledgement '$ActiveAcknowledgementSymbol' became False during the bounded hold."
        }
        $remainingMilliseconds = [Math]::Max(1, [Math]::Min(
            $PollIntervalMilliseconds,
            [int][Math]::Ceiling(($holdDeadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
        ))
        Start-Sleep -Milliseconds $remainingMilliseconds
    }

    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $DeactivateRequestSymbol `
        -AcknowledgementSymbol $ActiveAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $true -ExpectedFinalAcknowledgement $false -Phase 'Deactivate'
    Invoke-BooleanRequestTransition -Client $ads -RequestSymbol $ExitModeRequestSymbol `
        -AcknowledgementSymbol $ModeAcknowledgementSymbol `
        -ExpectedInitialAcknowledgement $true -ExpectedFinalAcknowledgement $false -Phase 'ExitMode'
    $executionStatus = 'succeeded'
}
catch {
    Add-ProbeEvent -Kind $(if ($timeoutTriggered) { 'abort' } else { 'error' }) -Outcome 'failed' -Detail $_.Exception.Message
    $executionStatus = if ($timeoutTriggered) { 'aborted' } else { 'failed' }
}
finally {
    if ($connected) {
        if ($writeOccurred) {
            if (Invoke-VerifiedRestore -Client $ads) { $restoreStatus = 'verified' }
            else { $restoreStatus = 'failed'; $executionStatus = 'failed' }
        }
        else {
            $restoreStatus = Test-NoWriteFinalState -Client $ads
        }
    }
    if ($null -ne $ads) { $ads.Dispose() }
}

[PSCustomObject]@{
    schema_version = '0.1.0'
    kind = 'bounded_boolean_probe_facts'
    started_at = $startedAt.ToString('o')
    finished_at = [DateTimeOffset]::UtcNow.ToString('o')
    initial_state = $initialState
    events = @($events)
    timeouts = [ordered]@{
        overall_seconds = [Math]::Max(1, $HoldSeconds + (4 * $AcknowledgementTimeoutSeconds))
        triggered = $timeoutTriggered
    }
    restore = [ordered]@{ attempted = $true; status = $restoreStatus }
    final_state = $finalState
    execution_status = $executionStatus
} | ConvertTo-Json -Depth 30 -Compress
