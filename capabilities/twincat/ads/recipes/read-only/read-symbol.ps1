[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Symbol,

    [Parameter(Mandatory)]
    [ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')]
    [string]$Type,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 851,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Read a primitive PLC symbol
# SAFETY: READ_ONLY
# VERIFICATION: VERIFIED IN ONE SUPERVISED TWINCAT ADS ENVIRONMENT
# The caller must verify the PLC datatype before reading.

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

$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $value = $ads.ReadSymbol($Symbol, $typeMap[$Type], $true)
    [PSCustomObject]@{
        Symbol = $Symbol
        Type   = $Type
        Value  = $value
    }
}
finally {
    $ads.Dispose()
}
