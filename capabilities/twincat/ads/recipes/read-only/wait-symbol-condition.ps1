[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Symbol,

    [Parameter(Mandatory)]
    [ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')]
    [string]$Type,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$ExpectedValue,

    [ValidateRange(0, 300)]
    [int]$TimeoutSeconds = 10,

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

# CAPABILITY: Wait until a primitive PLC symbol reaches an expected value
# SAFETY: READ_ONLY
# VERIFICATION: PREPARED; LIVE WAIT BEHAVIOR NOT YET PRESERVED

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $actual = $ads.ReadSymbol($Symbol, $typeMap[$Type], $true)
        if (Test-PrimitiveEqual -Actual $actual -Expected $expected -PrimitiveType $Type -Tolerance $NumericTolerance) {
            [PSCustomObject]@{
                Symbol    = $Symbol
                Type      = $Type
                Expected  = $expected
                Actual    = $actual
                Satisfied = $true
            }
            return
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    } while ($true)

    throw "Timed out waiting for '$Symbol' to reach '$expected'; last value: '$actual'."
}
finally {
    $ads.Dispose()
}
