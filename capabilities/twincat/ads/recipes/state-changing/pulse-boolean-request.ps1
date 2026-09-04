[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [switch]$HumanApproved,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RequestSymbol,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AcknowledgementSymbol,

    [Parameter(Mandatory)]
    [ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')]
    [string]$AcknowledgementType,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$ExpectedInitialAcknowledgement,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$ExpectedFinalAcknowledgement,

    [Parameter(Mandatory)]
    [ValidateSet('Run')]
    [string]$ExpectedAdsState,

    [ValidateRange(10, 60000)]
    [int]$PulseMilliseconds = 100,

    [ValidateRange(0, 300)]
    [int]$AcknowledgementTimeoutSeconds = 5,

    [ValidateRange(10, 60000)]
    [int]$PollIntervalMilliseconds = 100,

    [ValidateRange(0, 1000000000)]
    [double]$NumericTolerance = 0,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 851,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Pulse one Boolean PLC request and wait for a separate primitive acknowledgement
# SAFETY: STATE_CHANGING
# VERIFICATION: VERIFIED IN ONE SUPERVISED TWINCAT ADS ENVIRONMENT

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $HumanApproved) {
    throw 'STATE-CHANGING CAPABILITY BLOCKED: explicit human approval and a verified safe plant state are required.'
}
if ($RequestSymbol -eq $AcknowledgementSymbol) {
    throw 'RequestSymbol and AcknowledgementSymbol must be different symbols.'
}

Add-Type -LiteralPath $AdsDll
$typeMap = @{
    Int16   = [System.Int16]
    UInt16  = [System.UInt16]
    Int32   = [System.Int32]
    UInt32  = [System.UInt32]
    Single  = [System.Single]
    Double  = [System.Double]
    Boolean = [System.Boolean]
    Byte    = [System.Byte]
}
$runtimeTypeMap = @{
    Int16   = 'INT'
    UInt16  = 'UINT'
    Int32   = 'DINT'
    UInt32  = 'UDINT'
    Single  = 'REAL'
    Double  = 'LREAL'
    Boolean = 'BOOL'
    Byte    = 'BYTE'
}

function Convert-PrimitiveValue {
    param([string]$Text, [string]$PrimitiveType)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    switch ($PrimitiveType) {
        'Boolean' { return [System.Boolean]::Parse($Text) }
        'Int16'   { return [System.Int16]::Parse($Text, $culture) }
        'UInt16'  { return [System.UInt16]::Parse($Text, $culture) }
        'Int32'   { return [System.Int32]::Parse($Text, $culture) }
        'UInt32'  { return [System.UInt32]::Parse($Text, $culture) }
        'Single'  { return [System.Single]::Parse($Text, $culture) }
        'Double'  { return [System.Double]::Parse($Text, $culture) }
        'Byte'    { return [System.Byte]::Parse($Text, $culture) }
    }
}

function Test-PrimitiveEqual {
    param($Actual, $Expected, [string]$PrimitiveType, [double]$Tolerance)
    if ($PrimitiveType -in @('Single', 'Double')) {
        return [Math]::Abs(([double]$Actual) - ([double]$Expected)) -le $Tolerance
    }
    return $Actual -eq $Expected
}

$expectedInitialAck = Convert-PrimitiveValue -Text $ExpectedInitialAcknowledgement -PrimitiveType $AcknowledgementType
$expectedFinalAck = Convert-PrimitiveValue -Text $ExpectedFinalAcknowledgement -PrimitiveType $AcknowledgementType
$ads = New-Object TwinCAT.Ads.TcAdsClient
$requestRaised = $false
try {
    $ads.Connect($NetId, $Port)
    $runtimeState = $ads.ReadState()
    if ([string]$runtimeState.AdsState -ne $ExpectedAdsState) {
        throw "Expected PLC ADS state '$ExpectedAdsState', actual state: '$($runtimeState.AdsState)'."
    }

    $loader = $ads.CreateSymbolInfoLoader()
    $requestInfo = $loader.FindSymbol($RequestSymbol)
    $ackInfo = $loader.FindSymbol($AcknowledgementSymbol)
    if ($null -eq $requestInfo) { throw "Request symbol '$RequestSymbol' was not found." }
    if ($null -eq $ackInfo) { throw "Acknowledgement symbol '$AcknowledgementSymbol' was not found." }
    if ($requestInfo.IsReadOnly) { throw "Request symbol '$RequestSymbol' is marked read-only." }
    if ([string]$requestInfo.Type -ne 'BOOL') { throw "Request symbol '$RequestSymbol' is not BOOL." }
    if ([string]$ackInfo.Type -ne $runtimeTypeMap[$AcknowledgementType]) {
        throw "Acknowledgement symbol '$AcknowledgementSymbol' has runtime type '$($ackInfo.Type)', expected '$($runtimeTypeMap[$AcknowledgementType])'."
    }

    $requestBefore = [bool]$ads.ReadSymbol($RequestSymbol, [System.Boolean], $true)
    $ackBefore = $ads.ReadSymbol($AcknowledgementSymbol, $typeMap[$AcknowledgementType], $true)
    if ($requestBefore) {
        throw "Request symbol '$RequestSymbol' is already TRUE."
    }
    if (-not (Test-PrimitiveEqual -Actual $ackBefore -Expected $expectedInitialAck -PrimitiveType $AcknowledgementType -Tolerance $NumericTolerance)) {
        throw "Acknowledgement precondition failed for '$AcknowledgementSymbol': expected '$expectedInitialAck', actual '$ackBefore'."
    }

    [PSCustomObject]@{
        Phase                     = 'Before'
        RequestSymbol             = $RequestSymbol
        RequestValue              = $requestBefore
        AcknowledgementSymbol     = $AcknowledgementSymbol
        AcknowledgementValue      = $ackBefore
        AdsState                  = $runtimeState.AdsState
    }

    $ads.WriteSymbol($RequestSymbol, $true, $true)
    $requestRaised = $true
    Start-Sleep -Milliseconds $PulseMilliseconds
    $ads.WriteSymbol($RequestSymbol, $false, $true)
    $requestRaised = $false

    $deadline = [DateTime]::UtcNow.AddSeconds($AcknowledgementTimeoutSeconds)
    do {
        $requestAfter = [bool]$ads.ReadSymbol($RequestSymbol, [System.Boolean], $true)
        $ackAfter = $ads.ReadSymbol($AcknowledgementSymbol, $typeMap[$AcknowledgementType], $true)
        if (-not $requestAfter -and
            (Test-PrimitiveEqual -Actual $ackAfter -Expected $expectedFinalAck -PrimitiveType $AcknowledgementType -Tolerance $NumericTolerance)) {
            [PSCustomObject]@{
                Phase                     = 'After'
                RequestSymbol             = $RequestSymbol
                RequestValue              = $requestAfter
                AcknowledgementSymbol     = $AcknowledgementSymbol
                AcknowledgementValue      = $ackAfter
                AdsState                  = $runtimeState.AdsState
                Verified                  = $true
            }
            return
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    } while ($true)

    throw "Request acknowledgement failed: request '$RequestSymbol'='$requestAfter', acknowledgement '$AcknowledgementSymbol'='$ackAfter'."
}
catch {
    if ($requestRaised) {
        try {
            $ads.WriteSymbol($RequestSymbol, $false, $true)
        }
        catch {
            Write-Warning "Failed to clear request symbol '$RequestSymbol' after an error."
        }
    }
    throw
}
finally {
    $ads.Dispose()
}
