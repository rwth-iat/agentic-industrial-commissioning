[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Symbol,
    [Parameter(Mandatory)][ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')][string]$Type,
    [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedValue,
    [Parameter(Mandatory)][ValidateRange(1, 300)][int]$DurationSeconds,
    [ValidateRange(10, 60000)][int]$PollIntervalMilliseconds = 100,
    [ValidateRange(0, 1000000000)][double]$NumericTolerance = 0,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$NetId,
    [ValidateRange(1, 65535)][int]$Port = 851,
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$AdsDll
)

# CAPABILITY: Observe a primitive PLC symbol continuously for a bounded duration
# SAFETY: READ_ONLY
# VERIFICATION: EXPERIMENTAL

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -LiteralPath $AdsDll

$typeMap = @{ Int16 = [int16]; UInt16 = [uint16]; Int32 = [int32]; UInt32 = [uint32]; Single = [single]; Double = [double]; Boolean = [bool]; Byte = [byte] }
function Convert-PrimitiveValue { param([string]$Text, [string]$PrimitiveType)
    $culture = [Globalization.CultureInfo]::InvariantCulture
    switch ($PrimitiveType) { 'Boolean' { [bool]::Parse($Text) } 'Int16' { [int16]::Parse($Text, $culture) } 'UInt16' { [uint16]::Parse($Text, $culture) } 'Int32' { [int32]::Parse($Text, $culture) } 'UInt32' { [uint32]::Parse($Text, $culture) } 'Single' { [single]::Parse($Text, $culture) } 'Double' { [double]::Parse($Text, $culture) } 'Byte' { [byte]::Parse($Text, $culture) } }
}
function Test-PrimitiveEqual { param($Actual, $Expected, [string]$PrimitiveType, [double]$Tolerance)
    if ($PrimitiveType -in @('Single', 'Double')) { return [Math]::Abs(([double]$Actual) - ([double]$Expected)) -le $Tolerance }
    return $Actual -eq $Expected
}

$expected = Convert-PrimitiveValue -Text $ExpectedValue -PrimitiveType $Type
$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $startedAt = [DateTimeOffset]::UtcNow
    $deadline = $startedAt.AddSeconds($DurationSeconds)
    $samples = 0
    do {
        $actual = $ads.ReadSymbol($Symbol, $typeMap[$Type], $true); $samples++
        if (-not (Test-PrimitiveEqual -Actual $actual -Expected $expected -PrimitiveType $Type -Tolerance $NumericTolerance)) {
            throw "Observed '$Symbol'='$actual'; expected '$expected' throughout the $DurationSeconds-second observation."
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    } while ($true)
    [PSCustomObject]@{ Symbol = $Symbol; Type = $Type; Expected = $expected; DurationSeconds = $DurationSeconds; Samples = $samples; Held = $true }
}
finally { $ads.Dispose() }
