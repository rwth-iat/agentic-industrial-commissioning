Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BridgeStateFile = Join-Path (Get-Location) '.agent-remote-bridge.json'
$script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ConnectionProfileRoot = Join-Path $script:RepositoryRoot 'creds'

function Get-AicBridgeState {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:BridgeStateFile -PathType Leaf)) {
        throw 'Runtime access unavailable: remote session is not active.'
    }

    try {
        $state = Get-Content -LiteralPath $script:BridgeStateFile -Raw |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Runtime access unavailable: bridge state is invalid. $($_.Exception.Message)"
    }

    if ($state.schemaVersion -ne 1) {
        throw "Runtime access unavailable: unsupported bridge state schema '$($state.schemaVersion)'."
    }
    if ([string]$state.host -ne '127.0.0.1') {
        throw 'Runtime access unavailable: bridge endpoint is not loopback.'
    }
    if ([int]$state.port -lt 1 -or [int]$state.port -gt 65535) {
        throw 'Runtime access unavailable: bridge port is invalid.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$state.token)) {
        throw 'Runtime access unavailable: bridge session token is missing.'
    }

    return $state
}

function Invoke-AicRemoteScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceCode,

        [hashtable]$Arguments = @{}
    )

    $state = Get-AicBridgeState
    $request = [PSCustomObject]@{
        token     = [string]$state.token
        code      = [Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes($SourceCode)
        )
        arguments = $Arguments
    }
    $requestJson = $request | ConvertTo-Json -Depth 20 -Compress

    $client = New-Object System.Net.Sockets.TcpClient
    $reader = $null
    $writer = $null
    try {
        $client.Connect([string]$state.host, [int]$state.port)
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader(
            $stream,
            [System.Text.Encoding]::UTF8
        )
        $writer = New-Object System.IO.StreamWriter(
            $stream,
            [System.Text.Encoding]::UTF8
        )
        $writer.AutoFlush = $true
        $writer.WriteLine($requestJson)

        $responseJson = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($responseJson)) {
            throw 'Runtime access failed: remote bridge returned an empty response.'
        }
        try {
            $response = $responseJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Runtime access failed: remote bridge returned invalid JSON. $($_.Exception.Message)"
        }

        if (-not [bool]$response.success) {
            $detail = if ([string]::IsNullOrWhiteSpace([string]$response.error)) {
                'Remote command failed without an error message.'
            }
            else {
                [string]$response.error
            }
            throw "Runtime access failed: $detail"
        }

        return [string]$response.output
    }
    catch [System.Net.Sockets.SocketException] {
        throw "Runtime access unavailable: remote bridge connection failed. $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $writer) { $writer.Dispose() }
        $client.Close()
    }
}

function Read-AicRuntimeBindingDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Runtime-binding document not found: $Path"
    }
    try {
        $document = Get-Content -LiteralPath $Path -Raw |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Runtime-binding document is invalid JSON: $($_.Exception.Message)"
    }
    if ($document.PSObject.Properties.Name -notcontains 'bindings' -or
        $null -eq $document.bindings) {
        throw 'Runtime-binding document does not contain bindings.'
    }
    if ($document.PSObject.Properties.Name -notcontains 'environment' -or
        $null -eq $document.environment) {
        throw 'Runtime-binding document does not contain an environment.'
    }

    return $document
}

function Get-AicSelectedBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Document,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BindingId
    )

    $matches = @($Document.bindings | Where-Object {
        $_.PSObject.Properties.Name -contains 'id' -and
        [string]$_.id -ceq $BindingId
    })
    if ($matches.Count -eq 0) {
        throw "Runtime binding not found: $BindingId"
    }
    if ($matches.Count -gt 1) {
        throw "Runtime-binding document contains duplicate exact ID: $BindingId"
    }

    return $matches[0]
}

function ConvertTo-AicAdsType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PlcDatatype
    )

    $typeMap = @{
        BOOL  = 'Boolean'
        BYTE  = 'Byte'
        INT   = 'Int16'
        UINT  = 'UInt16'
        WORD  = 'UInt16'
        DINT  = 'Int32'
        UDINT = 'UInt32'
        DWORD = 'UInt32'
        REAL  = 'Single'
        LREAL = 'Double'
    }
    $normalized = $PlcDatatype.Trim().ToUpperInvariant()
    if (-not $typeMap.ContainsKey($normalized)) {
        throw "Unsupported PLC datatype for ADS access: $PlcDatatype"
    }

    return $typeMap[$normalized]
}

function ConvertTo-AicPrimitiveValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AdsType,

        [string]$Label = 'Value'
    )

    if ($null -eq $Value) {
        throw "$Label cannot be null."
    }
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $text = if ($Value -is [System.IFormattable]) {
        $Value.ToString($null, $culture)
    }
    else {
        [string]$Value
    }

    try {
        switch ($AdsType) {
            'Boolean' { return [System.Boolean]::Parse($text) }
            'Int16'   { return [System.Int16]::Parse($text, [Globalization.NumberStyles]::Integer, $culture) }
            'UInt16'  { return [System.UInt16]::Parse($text, [Globalization.NumberStyles]::Integer, $culture) }
            'Int32'   { return [System.Int32]::Parse($text, [Globalization.NumberStyles]::Integer, $culture) }
            'UInt32'  { return [System.UInt32]::Parse($text, [Globalization.NumberStyles]::Integer, $culture) }
            'Single'  {
                $converted = [System.Single]::Parse($text, [Globalization.NumberStyles]::Float, $culture)
                if ([System.Single]::IsNaN($converted) -or [System.Single]::IsInfinity($converted)) {
                    throw 'Non-finite values are not supported.'
                }
                return $converted
            }
            'Double'  {
                $converted = [System.Double]::Parse($text, [Globalization.NumberStyles]::Float, $culture)
                if ([System.Double]::IsNaN($converted) -or [System.Double]::IsInfinity($converted)) {
                    throw 'Non-finite values are not supported.'
                }
                return $converted
            }
            'Byte'    { return [System.Byte]::Parse($text, [Globalization.NumberStyles]::Integer, $culture) }
            default   { throw "Unsupported ADS type: $AdsType" }
        }
    }
    catch {
        throw "$Label '$text' is not convertible to $AdsType. $($_.Exception.Message)"
    }
}

function ConvertTo-AicInvariantText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($Value -is [System.IFormattable]) {
        return $Value.ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Assert-AicWriteConstraints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Binding,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AdsType,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BindingId
    )

    if ($Binding.PSObject.Properties.Name -notcontains 'write_constraints' -or
        $null -eq $Binding.write_constraints) {
        return
    }

    $constraints = $Binding.write_constraints
    $hasMinimum = $constraints.PSObject.Properties.Name -contains 'minimum'
    $hasMaximum = $constraints.PSObject.Properties.Name -contains 'maximum'
    if ($hasMinimum -xor $hasMaximum) {
        throw "Runtime binding has an incomplete minimum/maximum constraint: $BindingId"
    }
    if ($hasMinimum) {
        if ($AdsType -eq 'Boolean') {
            throw "Boolean runtime binding cannot use minimum/maximum constraints: $BindingId"
        }
        $minimum = ConvertTo-AicPrimitiveValue `
            -Value $constraints.minimum -AdsType $AdsType -Label 'Minimum'
        $maximum = ConvertTo-AicPrimitiveValue `
            -Value $constraints.maximum -AdsType $AdsType -Label 'Maximum'
        if ([double]$minimum -gt [double]$maximum) {
            throw "Runtime binding minimum exceeds maximum: $BindingId"
        }
        if ([double]$Value -lt [double]$minimum -or
            [double]$Value -gt [double]$maximum) {
            throw "Value '$Value' is outside the allowed range [$minimum, $maximum] for runtime binding '$BindingId'."
        }
    }

    if ($constraints.PSObject.Properties.Name -contains 'allowed_values') {
        $allowedValues = @($constraints.allowed_values | ForEach-Object {
            ConvertTo-AicPrimitiveValue -Value $_ -AdsType $AdsType -Label 'Allowed value'
        })
        $isAllowed = $false
        foreach ($allowedValue in $allowedValues) {
            if ([object]::Equals($Value, $allowedValue)) {
                $isAllowed = $true
                break
            }
        }
        if (-not $isAllowed) {
            throw "Value '$Value' is not in the allowed value set for runtime binding '$BindingId'."
        }
    }
}

function Import-AicConnectionProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileKey
    )

    if ($ProfileKey -cnotmatch '^[A-Za-z][A-Za-z0-9._-]*$') {
        throw "Connection profile key is invalid: $ProfileKey"
    }
    $profilePath = Join-Path $script:ConnectionProfileRoot "$ProfileKey.local.psd1"
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        throw "Connection profile not found: $ProfileKey"
    }
    try {
        $profile = Import-PowerShellDataFile -LiteralPath $profilePath
    }
    catch {
        throw "Connection profile '$ProfileKey' is invalid: $($_.Exception.Message)"
    }
    if (-not $profile.ContainsKey('Ads') -or
        $profile.Ads -isnot [System.Collections.IDictionary]) {
        throw "Connection profile '$ProfileKey' does not contain an Ads section."
    }

    $ads = $profile.Ads
    foreach ($requiredKey in @('NetId', 'Port', 'AdsDll')) {
        if (-not $ads.ContainsKey($requiredKey) -or
            [string]::IsNullOrWhiteSpace([string]$ads[$requiredKey])) {
            throw "Connection profile '$ProfileKey' is missing Ads.$requiredKey."
        }
    }
    $port = 0
    if (-not [int]::TryParse([string]$ads.Port, [ref]$port) -or
        $port -lt 1 -or $port -gt 65535) {
        throw "Connection profile '$ProfileKey' contains an invalid Ads.Port."
    }

    return [PSCustomObject]@{
        NetId  = [string]$ads.NetId
        Port   = $port
        AdsDll = [string]$ads.AdsDll
    }
}

function Get-AicAdsReadSource {
    [CmdletBinding()]
    param()

    return @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Symbol,
    [Parameter(Mandatory)][string]$Type,
    [Parameter(Mandatory)][string]$NetId,
    [Parameter(Mandatory)][int]$Port,
    [Parameter(Mandatory)][string]$AdsDll
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AdsDll -PathType Leaf)) {
    throw "ADS assembly not found: $AdsDll"
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
if (-not $typeMap.ContainsKey($Type)) {
    throw "Unsupported ADS type: $Type"
}

$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $value = $ads.ReadSymbol($Symbol, $typeMap[$Type], $true)
    [PSCustomObject]@{
        symbol      = $Symbol
        type        = $Type
        value       = $value
        observed_at = (Get-Date).ToUniversalTime().ToString('o')
        success     = $true
    } | ConvertTo-Json -Compress
}
finally {
    $ads.Dispose()
}
'@
}

function Get-AicAdsWriteSource {
    [CmdletBinding()]
    param()

    return @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Symbol,
    [Parameter(Mandatory)][string]$Type,
    [Parameter(Mandatory)][string]$PlcDatatype,
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$NetId,
    [Parameter(Mandatory)][int]$Port,
    [Parameter(Mandatory)][string]$AdsDll
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AdsDll -PathType Leaf)) {
    throw "ADS assembly not found: $AdsDll"
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
if (-not $typeMap.ContainsKey($Type)) {
    throw "Unsupported ADS type: $Type"
}

$culture = [System.Globalization.CultureInfo]::InvariantCulture
switch ($Type) {
    'Boolean' { $desired = [System.Boolean]::Parse($Value) }
    'Int16'   { $desired = [System.Int16]::Parse($Value, [Globalization.NumberStyles]::Integer, $culture) }
    'UInt16'  { $desired = [System.UInt16]::Parse($Value, [Globalization.NumberStyles]::Integer, $culture) }
    'Int32'   { $desired = [System.Int32]::Parse($Value, [Globalization.NumberStyles]::Integer, $culture) }
    'UInt32'  { $desired = [System.UInt32]::Parse($Value, [Globalization.NumberStyles]::Integer, $culture) }
    'Single'  { $desired = [System.Single]::Parse($Value, [Globalization.NumberStyles]::Float, $culture) }
    'Double'  { $desired = [System.Double]::Parse($Value, [Globalization.NumberStyles]::Float, $culture) }
    'Byte'    { $desired = [System.Byte]::Parse($Value, [Globalization.NumberStyles]::Integer, $culture) }
}

$ads = New-Object TwinCAT.Ads.TcAdsClient
try {
    $ads.Connect($NetId, $Port)
    $loader = $ads.CreateSymbolInfoLoader()
    $symbolInfo = $loader.FindSymbol($Symbol)
    if ($null -eq $symbolInfo) {
        throw "Symbol '$Symbol' was not found in the runtime symbol table."
    }
    if ($symbolInfo.IsReadOnly) {
        throw "Symbol '$Symbol' is marked read-only by the runtime."
    }
    if ([string]$symbolInfo.Type -cne $PlcDatatype) {
        throw "Symbol '$Symbol' has runtime type '$($symbolInfo.Type)', expected '$PlcDatatype'."
    }

    $ads.WriteSymbol($Symbol, $desired, $true)
    $actual = $ads.ReadSymbol($Symbol, $typeMap[$Type], $true)
    if (-not [object]::Equals($actual, $desired)) {
        throw "Write readback failed for '$Symbol': expected '$desired', actual '$actual'."
    }
    [PSCustomObject]@{
        symbol       = $Symbol
        type         = $Type
        plc_datatype = $PlcDatatype
        value        = $actual
        observed_at  = (Get-Date).ToUniversalTime().ToString('o')
        success      = $true
    } | ConvertTo-Json -Compress
}
finally {
    $ads.Dispose()
}
'@
}

function Get-AicAdsPulseWriteSource {
    [CmdletBinding()]
    param()

    return @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Symbol,
    [Parameter(Mandatory)][int]$DurationMilliseconds,
    [Parameter(Mandatory)][string]$NetId,
    [Parameter(Mandatory)][int]$Port,
    [Parameter(Mandatory)][string]$AdsDll
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($DurationMilliseconds -lt 10 -or $DurationMilliseconds -gt 60000) {
    throw "Pulse duration must be between 10 and 60000 milliseconds."
}
if (-not (Test-Path -LiteralPath $AdsDll -PathType Leaf)) {
    throw "ADS assembly not found: $AdsDll"
}
Add-Type -LiteralPath $AdsDll

$ads = New-Object TwinCAT.Ads.TcAdsClient
$raised = $false
try {
    $ads.Connect($NetId, $Port)
    $loader = $ads.CreateSymbolInfoLoader()
    $symbolInfo = $loader.FindSymbol($Symbol)
    if ($null -eq $symbolInfo) {
        throw "Symbol '$Symbol' was not found in the runtime symbol table."
    }
    if ($symbolInfo.IsReadOnly) {
        throw "Symbol '$Symbol' is marked read-only by the runtime."
    }
    if ([string]$symbolInfo.Type -cne 'BOOL') {
        throw "Symbol '$Symbol' has runtime type '$($symbolInfo.Type)', expected 'BOOL'."
    }

    $before = [bool]$ads.ReadSymbol($Symbol, [System.Boolean], $true)
    if ($before) {
        throw "Pulse symbol '$Symbol' is already TRUE."
    }

    try {
        $raised = $true
        $ads.WriteSymbol($Symbol, $true, $true)
        Start-Sleep -Milliseconds $DurationMilliseconds
    }
    finally {
        if ($raised) {
            $ads.WriteSymbol($Symbol, $false, $true)
            $raised = $false
        }
    }

    $after = [bool]$ads.ReadSymbol($Symbol, [System.Boolean], $true)
    if ($after) {
        throw "Pulse reset readback failed for '$Symbol': expected 'False', actual 'True'."
    }
    [PSCustomObject]@{
        symbol       = $Symbol
        type         = 'Boolean'
        plc_datatype = 'BOOL'
        initial_value = $before
        value        = $after
        duration_ms  = $DurationMilliseconds
        reset        = $true
        observed_at  = (Get-Date).ToUniversalTime().ToString('o')
        success      = $true
    } | ConvertTo-Json -Compress
}
finally {
    $ads.Dispose()
}
'@
}

function Read-Binding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RuntimeBindingsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BindingId
    )

    $document = Read-AicRuntimeBindingDocument -Path $RuntimeBindingsPath
    if ($document.environment.PSObject.Properties.Name -notcontains 'platform' -or
        [string]::IsNullOrWhiteSpace([string]$document.environment.platform)) {
        throw 'Runtime-binding environment does not declare a platform.'
    }
    if ([string]$document.environment.platform -ine 'TwinCAT') {
        throw "Unsupported runtime platform: $($document.environment.platform)"
    }

    $binding = Get-AicSelectedBinding -Document $document -BindingId $BindingId
    if ($binding.PSObject.Properties.Name -notcontains 'access') {
        throw "Runtime binding does not declare access: $BindingId"
    }
    if ([string]$binding.access -notin @('read', 'read_write')) {
        throw "Runtime binding is not readable: $BindingId"
    }
    if ($binding.PSObject.Properties.Name -notcontains 'locator' -or
        $null -eq $binding.locator) {
        throw "Runtime binding does not contain a locator: $BindingId"
    }
    if ($binding.locator.PSObject.Properties.Name -notcontains 'kind') {
        throw "Runtime binding locator does not declare a kind: $BindingId"
    }
    if ([string]$binding.locator.kind -cne 'ads_symbol') {
        throw "Runtime binding does not use an ADS symbol locator: $BindingId"
    }
    if ($binding.locator.PSObject.Properties.Name -notcontains 'value') {
        throw "Runtime binding does not contain an ADS symbol: $BindingId"
    }
    $symbol = [string]$binding.locator.value
    if ([string]::IsNullOrWhiteSpace($symbol)) {
        throw "Runtime binding does not contain an ADS symbol: $BindingId"
    }

    if ($binding.PSObject.Properties.Name -notcontains 'datatype' -or
        [string]::IsNullOrWhiteSpace([string]$binding.datatype)) {
        throw "Runtime binding does not declare a datatype: $BindingId"
    }
    $plcDatatype = [string]$binding.datatype
    $adsType = ConvertTo-AicAdsType -PlcDatatype $plcDatatype
    if ($document.environment.PSObject.Properties.Name -notcontains 'connection_profile' -or
        [string]::IsNullOrWhiteSpace([string]$document.environment.connection_profile)) {
        throw 'Runtime-binding environment does not declare a connection profile.'
    }
    $profileKey = [string]$document.environment.connection_profile
    $profile = Import-AicConnectionProfile -ProfileKey $profileKey
    $remoteOutput = Invoke-AicRemoteScript `
        -SourceCode (Get-AicAdsReadSource) `
        -Arguments @{
            Symbol = $symbol
            Type   = $adsType
            NetId  = $profile.NetId
            Port   = $profile.Port
            AdsDll = $profile.AdsDll
        }

    try {
        $observation = $remoteOutput | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "ADS read returned invalid JSON: $($_.Exception.Message)"
    }
    if (-not [bool]$observation.success) {
        throw 'ADS read did not report success.'
    }
    if ([string]$observation.symbol -cne $symbol) {
        throw 'ADS read returned a different symbol than requested.'
    }
    if ([string]$observation.type -cne $adsType) {
        throw 'ADS read returned a different datatype than requested.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$observation.observed_at)) {
        throw 'ADS read did not return an observation timestamp.'
    }
    $observedAt = if ($observation.observed_at -is [datetime]) {
        $observation.observed_at.ToUniversalTime().ToString('o')
    }
    else {
        [string]$observation.observed_at
    }

    return [PSCustomObject][ordered]@{
        operation   = 'read'
        binding_id  = $BindingId
        symbol      = $symbol
        datatype    = $plcDatatype
        value       = $observation.value
        observed_at = $observedAt
        success     = $true
    }
}

function Write-Binding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RuntimeBindingsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BindingId,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('level', 'pulse')]
        [string]$Mode,

        [ValidateRange(10, 60000)]
        [int]$PulseDurationMilliseconds
    )

    $document = Read-AicRuntimeBindingDocument -Path $RuntimeBindingsPath
    if ($document.environment.PSObject.Properties.Name -notcontains 'platform' -or
        [string]::IsNullOrWhiteSpace([string]$document.environment.platform)) {
        throw 'Runtime-binding environment does not declare a platform.'
    }
    if ([string]$document.environment.platform -ine 'TwinCAT') {
        throw "Unsupported runtime platform: $($document.environment.platform)"
    }

    $binding = Get-AicSelectedBinding -Document $document -BindingId $BindingId
    if ($binding.PSObject.Properties.Name -notcontains 'access') {
        throw "Runtime binding does not declare access: $BindingId"
    }
    if ([string]$binding.access -notin @('write', 'read_write')) {
        throw "Runtime binding is not writable: $BindingId"
    }
    if ($binding.PSObject.Properties.Name -notcontains 'locator' -or
        $null -eq $binding.locator) {
        throw "Runtime binding does not contain a locator: $BindingId"
    }
    if ($binding.locator.PSObject.Properties.Name -notcontains 'kind' -or
        [string]$binding.locator.kind -cne 'ads_symbol') {
        throw "Runtime binding does not use an ADS symbol locator: $BindingId"
    }
    if ($binding.locator.PSObject.Properties.Name -notcontains 'value' -or
        [string]::IsNullOrWhiteSpace([string]$binding.locator.value)) {
        throw "Runtime binding does not contain an ADS symbol: $BindingId"
    }
    $symbol = [string]$binding.locator.value

    if ($binding.PSObject.Properties.Name -notcontains 'datatype' -or
        [string]::IsNullOrWhiteSpace([string]$binding.datatype)) {
        throw "Runtime binding does not declare a datatype: $BindingId"
    }
    $plcDatatype = ([string]$binding.datatype).Trim().ToUpperInvariant()
    $adsType = ConvertTo-AicAdsType -PlcDatatype $plcDatatype
    $convertedValue = ConvertTo-AicPrimitiveValue `
        -Value $Value -AdsType $adsType -Label 'Value'
    Assert-AicWriteConstraints `
        -Binding $binding -Value $convertedValue -AdsType $adsType -BindingId $BindingId

    $semantics = $Mode.ToLowerInvariant()

    $durationMilliseconds = $null
    if ($semantics -eq 'pulse') {
        if ($plcDatatype -cne 'BOOL') {
            throw "Pulse write requires PLC datatype BOOL: $BindingId"
        }
        if (-not [bool]$convertedValue) {
            throw "Pulse write requires trigger value TRUE: $BindingId"
        }
        if (-not $PSBoundParameters.ContainsKey('PulseDurationMilliseconds')) {
            throw "Pulse write requires PulseDurationMilliseconds: $BindingId"
        }
        $durationMilliseconds = $PulseDurationMilliseconds
    }
    elseif ($PSBoundParameters.ContainsKey('PulseDurationMilliseconds')) {
        throw "Level write must not specify PulseDurationMilliseconds: $BindingId"
    }

    if ($document.environment.PSObject.Properties.Name -notcontains 'connection_profile' -or
        [string]::IsNullOrWhiteSpace([string]$document.environment.connection_profile)) {
        throw 'Runtime-binding environment does not declare a connection profile.'
    }
    $profileKey = [string]$document.environment.connection_profile
    $profile = Import-AicConnectionProfile -ProfileKey $profileKey
    if ($semantics -eq 'pulse') {
        $sourceCode = Get-AicAdsPulseWriteSource
        $arguments = @{
            Symbol               = $symbol
            DurationMilliseconds = $durationMilliseconds
            NetId                = $profile.NetId
            Port                 = $profile.Port
            AdsDll               = $profile.AdsDll
        }
    }
    else {
        $sourceCode = Get-AicAdsWriteSource
        $arguments = @{
            Symbol      = $symbol
            Type        = $adsType
            PlcDatatype = $plcDatatype
            Value       = ConvertTo-AicInvariantText -Value $convertedValue
            NetId       = $profile.NetId
            Port        = $profile.Port
            AdsDll      = $profile.AdsDll
        }
    }
    $remoteOutput = Invoke-AicRemoteScript `
        -SourceCode $sourceCode `
        -Arguments $arguments

    try {
        $observation = $remoteOutput | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "ADS write returned invalid JSON: $($_.Exception.Message)"
    }
    if (-not [bool]$observation.success) {
        throw 'ADS write did not report success.'
    }
    if ([string]$observation.symbol -cne $symbol) {
        throw 'ADS write returned a different symbol than requested.'
    }
    if ([string]$observation.type -cne $adsType -or
        [string]$observation.plc_datatype -cne $plcDatatype) {
        throw 'ADS write returned a different datatype than requested.'
    }
    if ($semantics -eq 'pulse') {
        if ([bool]$observation.initial_value -or
            [bool]$observation.value -or
            -not [bool]$observation.reset -or
            [int]$observation.duration_ms -ne $durationMilliseconds) {
            throw 'ADS pulse write did not return the required reset state.'
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$observation.observed_at)) {
        throw 'ADS write did not return an observation timestamp.'
    }
    $observedAt = if ($observation.observed_at -is [datetime]) {
        $observation.observed_at.ToUniversalTime().ToString('o')
    }
    else {
        [string]$observation.observed_at
    }

    $result = [ordered]@{
        operation       = 'write'
        binding_id      = $BindingId
        symbol          = $symbol
        datatype        = $plcDatatype
        semantics       = $semantics
        requested_value = $convertedValue
        value           = $observation.value
        observed_at     = $observedAt
        success         = $true
    }
    if ($semantics -eq 'pulse') {
        $result.initial_value = [bool]$observation.initial_value
        $result.duration_ms = $durationMilliseconds
        $result.reset = [bool]$observation.reset
    }
    return [PSCustomObject]$result
}

Export-ModuleMember -Function Read-Binding, Write-Binding
