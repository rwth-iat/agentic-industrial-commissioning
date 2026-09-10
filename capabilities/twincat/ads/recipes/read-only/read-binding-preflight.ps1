[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [object[]]$Bindings,

    [Parameter(Mandatory)]
    [ValidateSet('Run')]
    [string]$ExpectedAdsState,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NetId,

    [ValidateRange(1, 65535)]
    [int]$Port = 851,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AdsDll
)

# CAPABILITY: Read and verify a bounded set of runtime bindings before commissioning
# SAFETY: READ_ONLY
# VERIFICATION: EXPERIMENTAL UNTIL A COMPLETE COMMISSIONING PREFLIGHT IS PRESERVED

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$startedAt = [DateTimeOffset]::UtcNow
$observations = [System.Collections.Generic.List[object]]::new()
$errors = [System.Collections.Generic.List[string]]::new()
$ads = $null

function Convert-ExpectedValue {
    param([string]$Value, [string]$Type)

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    switch ($Type) {
        'Boolean' {
            $parsed = $false
            if (-not [bool]::TryParse($Value, [ref]$parsed)) { throw "Expected value '$Value' is not Boolean." }
            return $parsed
        }
        'Byte' { return [byte]::Parse($Value, $culture) }
        'Int16' { return [int16]::Parse($Value, $culture) }
        'UInt16' { return [uint16]::Parse($Value, $culture) }
        'Int32' { return [int32]::Parse($Value, $culture) }
        'UInt32' { return [uint32]::Parse($Value, $culture) }
        'Single' { return [single]::Parse($Value, $culture) }
        'Double' { return [double]::Parse($Value, $culture) }
        default { throw "Unsupported preflight type '$Type'." }
    }
}

try {
    Add-Type -LiteralPath $AdsDll
    $ads = New-Object TwinCAT.Ads.TcAdsClient
    $ads.Connect($NetId, $Port)
    $runtimeState = $ads.ReadState()
    $runtimePassed = ([string]$runtimeState.AdsState -eq $ExpectedAdsState)
    $observations.Add([PSCustomObject]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        check = 'plc-runtime-state'
        expected = $ExpectedAdsState
        actual = [string]$runtimeState.AdsState
        passed = $runtimePassed
    })
    if (-not $runtimePassed) {
        $errors.Add("Expected PLC ADS state '$ExpectedAdsState', actual '$($runtimeState.AdsState)'.")
    }

    foreach ($binding in $Bindings) {
        $bindingId = [string]$binding.BindingId
        $symbol = [string]$binding.Symbol
        $type = [string]$binding.Type
        $expectedText = [string]$binding.ExpectedValue
        try {
            $symbolInfo = $ads.CreateSymbolInfoLoader().FindSymbol($symbol)
            if ($null -eq $symbolInfo) { throw "Symbol '$symbol' was not found." }
            $actualType = [string]$symbolInfo.Type
            $runtimeType = ([string]$binding.RuntimeType).ToUpperInvariant()
            $expectedRuntimeType = switch ($runtimeType) {
                'BOOLEAN' { 'BOOL' }
                'INT16' { 'INT' }
                'UINT16' { 'UINT' }
                'INT32' { 'DINT' }
                'UINT32' { 'UDINT' }
                'SINGLE' { 'REAL' }
                'DOUBLE' { 'LREAL' }
                default { $runtimeType }
            }
            if ($actualType.ToUpperInvariant() -ne $expectedRuntimeType.ToUpperInvariant()) {
                throw "Symbol '$symbol' datatype '$actualType' does not match expected '$expectedRuntimeType'."
            }

            $systemType = switch ($type) {
                'Boolean' { [System.Boolean] }
                'Byte' { [System.Byte] }
                'Int16' { [System.Int16] }
                'UInt16' { [System.UInt16] }
                'Int32' { [System.Int32] }
                'UInt32' { [System.UInt32] }
                'Single' { [System.Single] }
                'Double' { [System.Double] }
                default { throw "Unsupported preflight type '$type'." }
            }
            $actual = $ads.ReadSymbol($symbol, $systemType, $true)
            $expected = Convert-ExpectedValue -Value $expectedText -Type $type
            $passed = ($actual -eq $expected)
            $observations.Add([PSCustomObject]@{
                timestamp = [DateTimeOffset]::UtcNow.ToString('o')
                check = 'binding-value'
                binding_id = $bindingId
                symbol = $symbol
                runtime_type = $actualType
                expected = $expected
                actual = $actual
                passed = $passed
            })
            if (-not $passed) { $errors.Add("Binding '$bindingId' did not match its required preflight value.") }
        }
        catch {
            $errors.Add("Binding '$bindingId': $($_.Exception.Message)")
            $observations.Add([PSCustomObject]@{
                timestamp = [DateTimeOffset]::UtcNow.ToString('o')
                check = 'binding-value'
                binding_id = $bindingId
                symbol = $symbol
                passed = $false
                error = $_.Exception.Message
            })
        }
    }
}
catch {
    $errors.Add($_.Exception.Message)
}
finally {
    if ($null -ne $ads) { $ads.Dispose() }
}

[PSCustomObject]@{
    schema_version = '0.1.0'
    kind = 'ads_binding_preflight'
    started_at = $startedAt.ToString('o')
    finished_at = [DateTimeOffset]::UtcNow.ToString('o')
    writes_observed = $false
    success = ($errors.Count -eq 0)
    observations = @($observations)
    errors = @($errors)
} | ConvertTo-Json -Depth 20 -Compress
