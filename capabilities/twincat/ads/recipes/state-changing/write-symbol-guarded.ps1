[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [switch]$HumanApproved,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Symbol,

    [Parameter(Mandatory)]
    [ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')]
    [string]$Type,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$ExpectedValue,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$Value,

    [Parameter(Mandatory)]
    [ValidateSet('Run')]
    [string]$ExpectedAdsState,

    [AllowEmptyString()]
    [string]$MinimumValue,

    [AllowEmptyString()]
    [string]$MaximumValue,

    [ValidateRange(0, 300)]
    [int]$ReadbackTimeoutSeconds = 5,

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

# CAPABILITY: Guarded write of one primitive PLC symbol with compare-before-write and readback
# SAFETY: STATE_CHANGING
# VERIFICATION: EXPERIMENTAL; NOT YET EXECUTED THROUGH THE REPOSITORY PATH

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $HumanApproved) {
    throw 'STATE-CHANGING CAPABILITY BLOCKED: explicit human approval and a verified safe plant state are required.'
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

$expected = Convert-PrimitiveValue -Text $ExpectedValue -PrimitiveType $Type
$desired = Convert-PrimitiveValue -Text $Value -PrimitiveType $Type
$numericTypes = @('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Byte')
if ($Type -in $numericTypes) {
    if ([string]::IsNullOrWhiteSpace($MinimumValue) -or [string]::IsNullOrWhiteSpace($MaximumValue)) {
        throw "Numeric write type '$Type' requires MinimumValue and MaximumValue."
    }
    $minimum = Convert-PrimitiveValue -Text $MinimumValue -PrimitiveType $Type
    $maximum = Convert-PrimitiveValue -Text $MaximumValue -PrimitiveType $Type
    if ([double]$minimum -gt [double]$maximum) {
        throw "MinimumValue '$minimum' exceeds MaximumValue '$maximum'."
    }
    if ([double]$expected -lt [double]$minimum -or [double]$expected -gt [double]$maximum) {
        throw "ExpectedValue '$expected' is outside the approved range [$minimum, $maximum]."
    }
    if ([double]$desired -lt [double]$minimum -or [double]$desired -gt [double]$maximum) {
        throw "Value '$desired' is outside the approved range [$minimum, $maximum]."
    }
}
$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $runtimeState = $ads.ReadState()
    if ([string]$runtimeState.AdsState -ne $ExpectedAdsState) {
        throw "Expected PLC ADS state '$ExpectedAdsState', actual state: '$($runtimeState.AdsState)'."
    }

    $loader = $ads.CreateSymbolInfoLoader()
    $symbolInfo = $loader.FindSymbol($Symbol)
    if ($null -eq $symbolInfo) {
        throw "Symbol '$Symbol' was not found in the runtime symbol table."
    }
    if ($symbolInfo.IsReadOnly) {
        throw "Symbol '$Symbol' is marked read-only by the runtime."
    }
    if ([string]$symbolInfo.Type -ne $runtimeTypeMap[$Type]) {
        throw "Symbol '$Symbol' has runtime type '$($symbolInfo.Type)', expected '$($runtimeTypeMap[$Type])'."
    }

    $before = $ads.ReadSymbol($Symbol, $typeMap[$Type], $true)
    if (-not (Test-PrimitiveEqual -Actual $before -Expected $expected -PrimitiveType $Type -Tolerance $NumericTolerance)) {
        throw "Compare-before-write failed for '$Symbol': expected '$expected', actual '$before'."
    }

    [PSCustomObject]@{
        Phase    = 'Before'
        Symbol   = $Symbol
        Type     = $Type
        AdsState = $runtimeState.AdsState
        Value    = $before
    }

    $ads.WriteSymbol($Symbol, $desired, $true)

    $deadline = [DateTime]::UtcNow.AddSeconds($ReadbackTimeoutSeconds)
    do {
        $after = $ads.ReadSymbol($Symbol, $typeMap[$Type], $true)
        if (Test-PrimitiveEqual -Actual $after -Expected $desired -PrimitiveType $Type -Tolerance $NumericTolerance) {
            [PSCustomObject]@{
                Phase    = 'After'
                Symbol   = $Symbol
                Type     = $Type
                AdsState = $runtimeState.AdsState
                Value    = $after
                Verified = $true
            }
            return
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    } while ($true)

    throw "Write readback failed for '$Symbol': expected '$desired', last value '$after'."
}
finally {
    $ads.Dispose()
}
