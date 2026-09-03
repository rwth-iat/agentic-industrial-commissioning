[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Pattern,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 851,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Search PLC symbols by regular expression
# SAFETY: READ_ONLY

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -LiteralPath $AdsDll

$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $loader = $ads.CreateSymbolInfoLoader()
    $symbols = $loader.GetSymbols($false)

    $symbols |
        Where-Object { $_.Name -match $Pattern } |
        Select-Object Name, TypeName, DataTypeId, Category, Size, Comment,
            IsReadOnly, IndexGroup, IndexOffset
}
finally {
    $ads.Dispose()
}
