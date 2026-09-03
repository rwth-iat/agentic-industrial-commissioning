[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 851,

    [ValidateRange(1, 1000000)]
    [int]$First = 100,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Load and list PLC symbols
# SAFETY: READ_ONLY

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -LiteralPath $AdsDll

$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $loader = $ads.CreateSymbolInfoLoader()
    $symbols = $loader.GetSymbols($false)

    [PSCustomObject]@{
        SymbolCount = $symbols.Count
        Symbols = @(
            $symbols | Select-Object -First $First `
                Name, TypeName, IndexGroup, IndexOffset, Size, Comment, IsReadOnly
        )
    }
}
finally {
    $ads.Dispose()
}
