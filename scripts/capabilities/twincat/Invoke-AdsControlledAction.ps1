[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Capability,

    [switch]$List,

    [switch]$Execute,

    [string]$Approval,

    [string]$Symbol,

    [ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')]
    [string]$Type,

    [AllowEmptyString()]
    [string]$ExpectedValue,

    [AllowEmptyString()]
    [string]$Value,

    [AllowEmptyString()]
    [string]$MinimumValue,

    [AllowEmptyString()]
    [string]$MaximumValue,

    [string]$RequestSymbol,

    [string]$AcknowledgementSymbol,

    [ValidateSet('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Boolean', 'Byte')]
    [string]$AcknowledgementType,

    [AllowEmptyString()]
    [string]$ExpectedInitialAcknowledgement,

    [AllowEmptyString()]
    [string]$ExpectedFinalAcknowledgement,

    [ValidateSet('Run')]
    [string]$ExpectedAdsState,

    [ValidateRange(0, 300)]
    [int]$WaitSeconds = 5,

    [string]$EnterModeRequestSymbol,

    [string]$ModeAcknowledgementSymbol,

    [string]$ActivateRequestSymbol,

    [string]$ActiveAcknowledgementSymbol,

    [string]$DeactivateRequestSymbol,

    [string]$ExitModeRequestSymbol,

    [ValidateRange(1, 300)]
    [int]$HoldSeconds = 5,

    [ValidateRange(0, 300)]
    [int]$TimeoutSeconds = 5,

    [ValidateRange(10, 60000)]
    [int]$PollIntervalMilliseconds = 100,

    [ValidateRange(10, 60000)]
    [int]$PulseMilliseconds = 100,

    [ValidateRange(0, 1000000000)]
    [double]$NumericTolerance = 0,

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

$controlledCapabilities = @(
    $catalog.Capabilities.GetEnumerator() |
        Where-Object { $_.Value.Safety -eq 'STATE_CHANGING' } |
        Sort-Object { $_.Value.Order }
)

if ($List) {
    $controlledCapabilities | ForEach-Object {
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
    Write-Host 'Available controlled TwinCAT ADS actions:'
    Write-Host 'Every execution is state-changing and requires exact human approval.'
    Write-Host ''
    for ($index = 0; $index -lt $controlledCapabilities.Count; $index++) {
        $entry = $controlledCapabilities[$index]
        Write-Host "[$($index + 1)] $($entry.Value.Label) [$($entry.Value.Verification)]"
        Write-Host "    $($entry.Value.Description)"
    }
    Write-Host ''
    $selectionText = Read-Host 'Selection'
    $selection = 0
    if (-not [int]::TryParse($selectionText, [ref]$selection) -or
        $selection -lt 1 -or $selection -gt $controlledCapabilities.Count) {
        throw "Invalid capability selection: $selectionText"
    }
    $Capability = [string]$controlledCapabilities[$selection - 1].Key
}

if (-not $catalog.Capabilities.ContainsKey($Capability)) {
    throw "Unknown capability '$Capability'."
}
$definition = $catalog.Capabilities[$Capability]
if ($definition.Safety -ne 'STATE_CHANGING') {
    throw "Capability '$Capability' is $($definition.Safety) and must be invoked through the read-only selector."
}

$arguments = [ordered]@{}
$operation = [ordered]@{
    capability = $Capability
}

switch ($Capability) {
    'SystemConfigToRun' {
        $arguments.WaitSeconds = $WaitSeconds
        $operation.transition = 'ConfigToRun'
        $operation.wait_seconds = $WaitSeconds
    }
    'SystemRunToConfig' {
        $arguments.WaitSeconds = $WaitSeconds
        $operation.transition = 'RunToConfig'
        $operation.wait_seconds = $WaitSeconds
    }
    'WriteSymbolGuarded' {
        foreach ($required in @(
            @{ Name = 'Symbol'; Value = $Symbol },
            @{ Name = 'Type'; Value = $Type },
            @{ Name = 'ExpectedValue'; Value = $ExpectedValue },
            @{ Name = 'Value'; Value = $Value },
            @{ Name = 'ExpectedAdsState'; Value = $ExpectedAdsState }
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
                throw "WriteSymbolGuarded requires -$($required.Name)."
            }
        }
        $arguments.Symbol = $Symbol
        $arguments.Type = $Type
        $arguments.ExpectedValue = $ExpectedValue
        $arguments.Value = $Value
        $arguments.ExpectedAdsState = $ExpectedAdsState
        if ($Type -in @('Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Byte')) {
            if ([string]::IsNullOrWhiteSpace($MinimumValue) -or [string]::IsNullOrWhiteSpace($MaximumValue)) {
                throw "WriteSymbolGuarded with numeric type '$Type' requires -MinimumValue and -MaximumValue."
            }
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            try {
                $minimumNumber = [double]::Parse($MinimumValue, $culture)
                $maximumNumber = [double]::Parse($MaximumValue, $culture)
                $expectedNumber = [double]::Parse($ExpectedValue, $culture)
                $valueNumber = [double]::Parse($Value, $culture)
            }
            catch {
                throw 'Numeric write values and bounds must use invariant numeric formatting.'
            }
            if ($minimumNumber -gt $maximumNumber) {
                throw 'MinimumValue must not exceed MaximumValue.'
            }
            if ($expectedNumber -lt $minimumNumber -or $expectedNumber -gt $maximumNumber) {
                throw 'ExpectedValue is outside the declared write range.'
            }
            if ($valueNumber -lt $minimumNumber -or $valueNumber -gt $maximumNumber) {
                throw 'Value is outside the declared write range.'
            }
            $arguments.MinimumValue = $MinimumValue
            $arguments.MaximumValue = $MaximumValue
        }
        $arguments.ReadbackTimeoutSeconds = $TimeoutSeconds
        $arguments.PollIntervalMilliseconds = $PollIntervalMilliseconds
        $arguments.NumericTolerance = $NumericTolerance
        $operation.symbol = $Symbol
        $operation.type = $Type
        $operation.expected_value = $ExpectedValue
        $operation.value = $Value
        $operation.expected_ads_state = $ExpectedAdsState
        if (-not [string]::IsNullOrWhiteSpace($MinimumValue)) { $operation.minimum_value = $MinimumValue }
        if (-not [string]::IsNullOrWhiteSpace($MaximumValue)) { $operation.maximum_value = $MaximumValue }
        $operation.timeout_seconds = $TimeoutSeconds
        $operation.numeric_tolerance = $NumericTolerance
    }
    'PulseBooleanRequest' {
        foreach ($required in @(
            @{ Name = 'RequestSymbol'; Value = $RequestSymbol },
            @{ Name = 'AcknowledgementSymbol'; Value = $AcknowledgementSymbol },
            @{ Name = 'AcknowledgementType'; Value = $AcknowledgementType },
            @{ Name = 'ExpectedInitialAcknowledgement'; Value = $ExpectedInitialAcknowledgement },
            @{ Name = 'ExpectedFinalAcknowledgement'; Value = $ExpectedFinalAcknowledgement },
            @{ Name = 'ExpectedAdsState'; Value = $ExpectedAdsState }
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
                throw "PulseBooleanRequest requires -$($required.Name)."
            }
        }
        if ($ExpectedAdsState -ne 'Run') {
            throw 'PulseBooleanRequest requires -ExpectedAdsState Run.'
        }
        $arguments.RequestSymbol = $RequestSymbol
        $arguments.AcknowledgementSymbol = $AcknowledgementSymbol
        $arguments.AcknowledgementType = $AcknowledgementType
        $arguments.ExpectedInitialAcknowledgement = $ExpectedInitialAcknowledgement
        $arguments.ExpectedFinalAcknowledgement = $ExpectedFinalAcknowledgement
        $arguments.ExpectedAdsState = $ExpectedAdsState
        $arguments.PulseMilliseconds = $PulseMilliseconds
        $arguments.AcknowledgementTimeoutSeconds = $TimeoutSeconds
        $arguments.PollIntervalMilliseconds = $PollIntervalMilliseconds
        $arguments.NumericTolerance = $NumericTolerance
        $operation.request_symbol = $RequestSymbol
        $operation.acknowledgement_symbol = $AcknowledgementSymbol
        $operation.acknowledgement_type = $AcknowledgementType
        $operation.expected_initial_acknowledgement = $ExpectedInitialAcknowledgement
        $operation.expected_final_acknowledgement = $ExpectedFinalAcknowledgement
        $operation.expected_ads_state = $ExpectedAdsState
        $operation.pulse_milliseconds = $PulseMilliseconds
        $operation.timeout_seconds = $TimeoutSeconds
        $operation.numeric_tolerance = $NumericTolerance
    }
    'BoundedBooleanRequestActuation' {
        foreach ($required in @(
            @{ Name = 'EnterModeRequestSymbol'; Value = $EnterModeRequestSymbol },
            @{ Name = 'ModeAcknowledgementSymbol'; Value = $ModeAcknowledgementSymbol },
            @{ Name = 'ActivateRequestSymbol'; Value = $ActivateRequestSymbol },
            @{ Name = 'ActiveAcknowledgementSymbol'; Value = $ActiveAcknowledgementSymbol },
            @{ Name = 'DeactivateRequestSymbol'; Value = $DeactivateRequestSymbol },
            @{ Name = 'ExitModeRequestSymbol'; Value = $ExitModeRequestSymbol },
            @{ Name = 'ExpectedAdsState'; Value = $ExpectedAdsState }
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
                throw "BoundedBooleanRequestActuation requires -$($required.Name)."
            }
        }
        if ($ExpectedAdsState -ne 'Run') {
            throw 'BoundedBooleanRequestActuation requires -ExpectedAdsState Run.'
        }
        $operationSymbols = @(
            $EnterModeRequestSymbol,
            $ModeAcknowledgementSymbol,
            $ActivateRequestSymbol,
            $ActiveAcknowledgementSymbol,
            $DeactivateRequestSymbol,
            $ExitModeRequestSymbol
        ) | Select-Object -Unique
        if ($operationSymbols.Count -ne 6) {
            throw 'BoundedBooleanRequestActuation requires six distinct request and acknowledgement symbols.'
        }
        $arguments.EnterModeRequestSymbol = $EnterModeRequestSymbol
        $arguments.ModeAcknowledgementSymbol = $ModeAcknowledgementSymbol
        $arguments.ActivateRequestSymbol = $ActivateRequestSymbol
        $arguments.ActiveAcknowledgementSymbol = $ActiveAcknowledgementSymbol
        $arguments.DeactivateRequestSymbol = $DeactivateRequestSymbol
        $arguments.ExitModeRequestSymbol = $ExitModeRequestSymbol
        $arguments.ExpectedAdsState = $ExpectedAdsState
        $arguments.HoldSeconds = $HoldSeconds
        $arguments.PulseMilliseconds = $PulseMilliseconds
        $arguments.AcknowledgementTimeoutSeconds = $TimeoutSeconds
        $arguments.PollIntervalMilliseconds = $PollIntervalMilliseconds
        $operation.enter_mode_request_symbol = $EnterModeRequestSymbol
        $operation.mode_acknowledgement_symbol = $ModeAcknowledgementSymbol
        $operation.activate_request_symbol = $ActivateRequestSymbol
        $operation.active_acknowledgement_symbol = $ActiveAcknowledgementSymbol
        $operation.hold_seconds = $HoldSeconds
        $operation.deactivate_request_symbol = $DeactivateRequestSymbol
        $operation.exit_mode_request_symbol = $ExitModeRequestSymbol
        $operation.expected_ads_state = $ExpectedAdsState
        $operation.pulse_milliseconds = $PulseMilliseconds
        $operation.timeout_seconds = $TimeoutSeconds
        $operation.restore = 'deactivate_then_exit_mode'
    }
    default {
        throw "Controlled action '$Capability' has no dispatcher binding."
    }
}

$operationJson = $operation | ConvertTo-Json -Compress
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($operationJson))
}
finally {
    $sha256.Dispose()
}
$hashText = [BitConverter]::ToString($hashBytes).Replace('-', '')
$operationId = $hashText.Substring(0, 12)
$requiredApproval = "APPROVE $Capability $operationId"

$plan = [PSCustomObject]@{
    Capability       = $Capability
    Safety           = $definition.Safety
    Verification     = $definition.Verification
    OperationId      = $operationId
    Operation        = $operation
    RequiredApproval = $requiredApproval
    Warning          = 'The approval phrase is a defensive guard, not proof of plant safety or user authorization.'
}

if (-not $Execute) {
    $plan
    return
}

if (-not [string]::Equals($Approval, $requiredApproval, [StringComparison]::Ordinal)) {
    throw "Execution blocked. Prepare the exact operation first and provide its RequiredApproval phrase."
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

$arguments.HumanApproved = $true
$arguments.NetId = $adsConfig.NetId
$arguments.Port = $adsConfig[$definition.PortConfigKey]
$arguments.AdsDll = $adsConfig.AdsDll

$recipePath = Join-Path $adsRoot $definition.Recipe
if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) {
    throw "Catalog recipe does not exist: $($definition.Recipe)"
}

if (-not $PSCmdlet.ShouldProcess($Capability, "Execute controlled ADS action $operationId")) {
    return
}

$invokeParameters = @{
    ScriptPath = $recipePath
    Arguments  = $arguments
}
if (-not [string]::IsNullOrWhiteSpace($StateFile)) {
    $invokeParameters.StateFile = $StateFile
}

& $remoteInvoker @invokeParameters
