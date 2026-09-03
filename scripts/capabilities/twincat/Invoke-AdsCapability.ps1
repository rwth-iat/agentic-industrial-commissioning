[CmdletBinding()]
param(
    [string]$Capability,

    [switch]$List,

    [string]$Pattern,

    [string]$Symbol,

    [ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')]
    [string]$Type,

    [ValidateRange(1, 1000000)]
    [int]$First = 100,

    [string]$ConfigPath,

    [string]$StateFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (
    Split-Path -Parent (
        Split-Path -Parent $PSScriptRoot
    )
)
$adsRoot = Join-Path $repositoryRoot 'capabilities/twincat/ads'
$catalogPath = Join-Path $adsRoot 'catalog.psd1'
$remoteInvoker = Join-Path $repositoryRoot 'scripts/remote/Invoke-AgentRemote.ps1'

$catalog = Import-PowerShellDataFile -LiteralPath $catalogPath
if ($catalog.SchemaVersion -ne 1) {
    throw "Unsupported ADS capability catalog schema: $($catalog.SchemaVersion)"
}

$readOnlyCapabilities = @(
    $catalog.Capabilities.GetEnumerator() |
        Where-Object { $_.Value.Safety -eq 'READ_ONLY' } |
        Sort-Object { $_.Value.Order }
)

if ($List) {
    $readOnlyCapabilities | ForEach-Object {
        [PSCustomObject]@{
            Capability   = $_.Key
            Label        = $_.Value.Label
            Description  = $_.Value.Description
            Verification = $_.Value.Verification
            Parameters   = ($_.Value.UserParameters -join ', ')
        }
    }
    return
}

$interactiveSelection = [string]::IsNullOrWhiteSpace($Capability)
if ($interactiveSelection) {
    Write-Host 'Available read-only TwinCAT ADS capabilities:'
    Write-Host ''
    for ($index = 0; $index -lt $readOnlyCapabilities.Count; $index++) {
        $entry = $readOnlyCapabilities[$index]
        Write-Host "[$($index + 1)] $($entry.Value.Label) [$($entry.Value.Verification)]"
        Write-Host "    $($entry.Value.Description)"
    }
    Write-Host ''

    $selectionText = Read-Host 'Selection'
    $selection = 0
    if (-not [int]::TryParse($selectionText, [ref]$selection) -or
        $selection -lt 1 -or
        $selection -gt $readOnlyCapabilities.Count) {
        throw "Invalid capability selection: $selectionText"
    }
    $Capability = [string]$readOnlyCapabilities[$selection - 1].Key
}

if (-not $catalog.Capabilities.ContainsKey($Capability)) {
    $available = ($readOnlyCapabilities.Key -join ', ')
    throw "Unknown capability '$Capability'. Available read-only capabilities: $available"
}

$definition = $catalog.Capabilities[$Capability]
if ($definition.Safety -ne 'READ_ONLY') {
    throw "Capability '$Capability' is $($definition.Safety) and is intentionally blocked by the read-only selector."
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repositoryRoot 'creds/twincat-ads.local.psd1'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "ADS configuration not found: $ConfigPath"
}

$adsConfig = Import-PowerShellDataFile -LiteralPath $ConfigPath
foreach ($requiredKey in @('NetId', 'AdsDll', $definition.PortConfigKey)) {
    if (-not $adsConfig.ContainsKey($requiredKey) -or
        [string]::IsNullOrWhiteSpace([string]$adsConfig[$requiredKey])) {
        throw "ADS configuration is missing required key: $requiredKey"
    }
}

$arguments = @{
    NetId = $adsConfig.NetId
    Port   = $adsConfig[$definition.PortConfigKey]
    AdsDll = $adsConfig.AdsDll
}

switch ($Capability) {
    'ListSymbols' {
        $arguments.First = $First
    }
    'SearchSymbols' {
        if ([string]::IsNullOrWhiteSpace($Pattern) -and $interactiveSelection) {
            $Pattern = Read-Host 'Regular expression for symbol names'
        }
        if ([string]::IsNullOrWhiteSpace($Pattern)) {
            throw 'SearchSymbols requires -Pattern.'
        }
        $arguments.Pattern = $Pattern
    }
    'ReadSymbol' {
        if ([string]::IsNullOrWhiteSpace($Symbol) -and $interactiveSelection) {
            $Symbol = Read-Host 'Exact PLC symbol name'
        }
        if ([string]::IsNullOrWhiteSpace($Type) -and $interactiveSelection) {
            $Type = Read-Host 'Verified type (Int16, UInt16, Int32, UInt32, Single, Double, Boolean, Byte)'
        }
        if ([string]::IsNullOrWhiteSpace($Symbol)) {
            throw 'ReadSymbol requires -Symbol.'
        }
        if ([string]::IsNullOrWhiteSpace($Type)) {
            throw 'ReadSymbol requires -Type after datatype verification.'
        }
        $allowedTypes = @('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')
        if ($Type -notin $allowedTypes) {
            throw "Unsupported primitive type '$Type'. Allowed types: $($allowedTypes -join ', ')"
        }
        $arguments.Symbol = $Symbol
        $arguments.Type = $Type
    }
}

$recipePath = Join-Path $adsRoot $definition.Recipe
if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) {
    throw "Catalog recipe does not exist: $($definition.Recipe)"
}

$invokeParameters = @{
    ScriptPath = $recipePath
    Arguments  = $arguments
}
if (-not [string]::IsNullOrWhiteSpace($StateFile)) {
    $invokeParameters.StateFile = $StateFile
}

& $remoteInvoker @invokeParameters
