[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$PreflightPath,
    [Parameter(Mandatory)][string]$RuntimeBindingsPath,
    [Parameter(Mandatory)][string]$EnterModeRequestBindingId,
    [Parameter(Mandatory)][string]$ActivateRequestBindingId,
    [Parameter(Mandatory)][string]$DeactivateRequestBindingId,
    [Parameter(Mandatory)][string]$ExitModeRequestBindingId,
    [hashtable]$ExpectedBindingValue = @{},
    [ValidateRange(1, 5)][int]$HoldSeconds = 5,
    [ValidateRange(0, 30)][int]$TimeoutSeconds = 5,
    [ValidateRange(10, 1000)][int]$PollIntervalMilliseconds = 100,
    [ValidateRange(10, 1000)][int]$PulseMilliseconds = 100,
    [switch]$Execute,
    [string]$Approval,
    [string]$ApprovedAt,
    [string]$ApprovalSourceRef,
    [string]$ConfigPath,
    [string]$StateFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repositoryRoot 'scripts/commissioning/supervised-probe.common.ps1')

$additionalIds = @($ExpectedBindingValue.Keys | ForEach-Object { [string]$_ })
$context = Get-AicProbeContext `
    -ManifestPath $ManifestPath `
    -RuntimeBindingsPath $RuntimeBindingsPath `
    -EnterModeRequestBindingId $EnterModeRequestBindingId `
    -ActivateRequestBindingId $ActivateRequestBindingId `
    -DeactivateRequestBindingId $DeactivateRequestBindingId `
    -ExitModeRequestBindingId $ExitModeRequestBindingId `
    -AdditionalBindingId $additionalIds
$preflight = Assert-AicProbePreflight -ManifestPath $ManifestPath -PreflightPath $PreflightPath

$bindingMap = [ordered]@{}
foreach ($entry in $context.Slots.GetEnumerator()) { $bindingMap[[string]$entry.Value.id] = $entry.Value }
foreach ($binding in $context.AdditionalBindings) { $bindingMap[[string]$binding.id] = $binding }

$preconditions = [ordered]@{}
foreach ($entry in $context.Slots.GetEnumerator()) { $preconditions[[string]$entry.Value.id] = 'False' }
foreach ($id in $additionalIds) {
    $expected = [string]$ExpectedBindingValue[$id]
    if ([string]::IsNullOrWhiteSpace($expected)) { throw "Expected value for binding '$id' is empty." }
    if ($preconditions.Contains($id) -and $expected -ne 'False') {
        throw "Core probe binding '$id' must be inactive before execution."
    }
    $preconditions[$id] = $expected
}

$operation = [ordered]@{
    run_id = [string]$context.Manifest.run_id
    case_id = [string]$context.Manifest.case_id
    asset_id = [string]$context.Manifest.asset_id
    requested_interface = [string]$context.Manifest.requested_interface
    bindings = [ordered]@{
        enter_mode_request = [string]$context.Slots.EnterModeRequest.id
        mode_acknowledgement = [string]$context.Slots.ModeAcknowledgement.id
        activate_request = [string]$context.Slots.ActivateRequest.id
        active_acknowledgement = [string]$context.Slots.ActiveAcknowledgement.id
        deactivate_request = [string]$context.Slots.DeactivateRequest.id
        exit_mode_request = [string]$context.Slots.ExitModeRequest.id
    }
    preconditions = @($preconditions.GetEnumerator() | Sort-Object Key | ForEach-Object {
        [ordered]@{ binding_id = [string]$_.Key; expected_value = [string]$_.Value }
    })
    expected_ads_state = 'Run'
    hold_seconds = $HoldSeconds
    timeout_seconds = $TimeoutSeconds
    pulse_milliseconds = $PulseMilliseconds
    restore_target = 'inactive actuation and inactive mode'
}
$operationJson = $operation | ConvertTo-Json -Depth 30 -Compress
$sha256 = [Security.Cryptography.SHA256]::Create()
try { $hashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($operationJson)) }
finally { $sha256.Dispose() }
$operationId = ([BitConverter]::ToString($hashBytes).Replace('-', '')).Substring(0, 12)
$requiredApproval = "APPROVE SUPERVISED_PROBE $operationId"
$approvalScope = "Request '$($context.Manifest.requested_interface)' for asset '$($context.Manifest.asset_id)' for at most $HoldSeconds second(s), then restore inactive actuation and inactive mode."

$plan = [PSCustomObject]@{
    Stage = 'supervised_probe'
    Safety = 'STATE_CHANGING'
    OperationId = $operationId
    Operation = $operation
    ApprovalScope = $approvalScope
    RequiredApproval = $requiredApproval
    Warning = 'Execution requires current plant-safety confirmation and exact human approval. This phrase is only a technical guard.'
}
if (-not $Execute) { $plan; return }

if (-not [string]::Equals($Approval, $requiredApproval, [StringComparison]::Ordinal)) {
    throw 'Execution blocked. Prepare the current probe and provide its exact RequiredApproval phrase.'
}
if ([string]::IsNullOrWhiteSpace($ApprovedAt) -or [string]::IsNullOrWhiteSpace($ApprovalSourceRef)) {
    throw 'Execution requires ApprovedAt and ApprovalSourceRef from the current human authorization.'
}
try { $approvedTimestamp = [DateTimeOffset]::Parse($ApprovedAt, [Globalization.CultureInfo]::InvariantCulture) }
catch { throw "ApprovedAt is not a valid timestamp: $ApprovedAt" }
try { $preflightTimestamp = [DateTimeOffset]::Parse([string]$preflight.observed_at, [Globalization.CultureInfo]::InvariantCulture) }
catch { throw 'Preflight observed_at is not a valid timestamp.' }
if ($approvedTimestamp -lt $preflightTimestamp) {
    throw 'Approval predates the current preflight and cannot authorize this probe.'
}
if ($approvedTimestamp -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
    throw 'Approval timestamp is unreasonably far in the future.'
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repositoryRoot 'creds/twincat-ads.local.psd1'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "ADS configuration not found: $ConfigPath" }
$adsConfig = Import-PowerShellDataFile -LiteralPath $ConfigPath
$catalog = Import-PowerShellDataFile -LiteralPath (Join-Path $repositoryRoot 'capabilities/twincat/ads/catalog.psd1')
$definition = $catalog.Capabilities.BoundedBooleanRequestActuation
foreach ($requiredKey in @('NetId', 'AdsDll', $definition.PortConfigKey)) {
    if (-not $adsConfig.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace([string]$adsConfig[$requiredKey])) {
        throw "ADS configuration is missing required key: $requiredKey"
    }
}

$recipePreconditions = @($preconditions.GetEnumerator() | ForEach-Object {
    $binding = $bindingMap[[string]$_.Key]
    [PSCustomObject]@{
        Symbol = [string]$binding.locator.value
        Type = ConvertTo-AicPowerShellType -RuntimeType ([string]$binding.datatype)
        RuntimeType = [string]$binding.datatype
        ExpectedValue = [string]$_.Value
    }
})
$arguments = @{
    HumanApproved = $true
    EnterModeRequestSymbol = [string]$context.Slots.EnterModeRequest.locator.value
    ModeAcknowledgementSymbol = [string]$context.Slots.ModeAcknowledgement.locator.value
    ActivateRequestSymbol = [string]$context.Slots.ActivateRequest.locator.value
    ActiveAcknowledgementSymbol = [string]$context.Slots.ActiveAcknowledgement.locator.value
    DeactivateRequestSymbol = [string]$context.Slots.DeactivateRequest.locator.value
    ExitModeRequestSymbol = [string]$context.Slots.ExitModeRequest.locator.value
    ExpectedAdsState = 'Run'
    HoldSeconds = $HoldSeconds
    PulseMilliseconds = $PulseMilliseconds
    AcknowledgementTimeoutSeconds = $TimeoutSeconds
    PollIntervalMilliseconds = $PollIntervalMilliseconds
    Preconditions = $recipePreconditions
    NetId = $adsConfig.NetId
    Port = $adsConfig[$definition.PortConfigKey]
    AdsDll = $adsConfig.AdsDll
}
$recipePath = Join-Path $repositoryRoot "capabilities/twincat/ads/$($definition.Recipe)"
$remoteInvoker = Join-Path $repositoryRoot 'scripts/remote/Invoke-AgentRemote.ps1'

if (-not $PSCmdlet.ShouldProcess([string]$context.Manifest.asset_id, "Execute supervised probe $operationId")) { return }

$rawDirectory = Join-Path $repositoryRoot "cases/$($context.Manifest.case_id)/raw/runtime/$($context.Manifest.run_id)"
$rawAdsPath = Join-Path $rawDirectory 'probe-ads.json'
$factsPath = Join-Path $rawDirectory 'execution-facts.json'
foreach ($path in @($rawAdsPath, $factsPath)) {
    if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite existing runtime evidence: $path" }
}
$null = New-Item -ItemType Directory -Path $rawDirectory -Force

$invokeParameters = @{ ScriptPath = $recipePath; Arguments = $arguments }
if (-not [string]::IsNullOrWhiteSpace($StateFile)) { $invokeParameters.StateFile = $StateFile }
try {
    $remoteOutput = @(& $remoteInvoker @invokeParameters 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($remoteOutput -join '; ') }
    $remoteEnvelope = ($remoteOutput -join [Environment]::NewLine) | ConvertFrom-Json
}
catch {
    $now = [DateTimeOffset]::UtcNow.ToString('o')
    $remoteEnvelope = [PSCustomObject]@{
        schema_version = '0.1.0'
        kind = 'bounded_boolean_probe_facts'
        started_at = $now
        finished_at = $now
        initial_state = [PSCustomObject]@{ known = $false }
        events = @([PSCustomObject]@{ timestamp = $now; kind = 'error'; outcome = 'failed'; detail = $_.Exception.Message })
        timeouts = [PSCustomObject]@{ overall_seconds = [Math]::Max(1, $HoldSeconds + (4 * $TimeoutSeconds)); triggered = $false }
        restore = [PSCustomObject]@{ attempted = $true; status = 'unknown' }
        final_state = [PSCustomObject]@{ known = $false }
        execution_status = 'failed'
    }
}
$remoteEnvelope | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $rawAdsPath -Encoding utf8
$rawReference = Get-AicRepositoryRelativePath -Path $rawAdsPath

$locatorToBinding = @{}
foreach ($entry in $bindingMap.GetEnumerator()) { $locatorToBinding[[string]$entry.Value.locator.value] = [string]$entry.Key }
$normalizedEvents = @()
foreach ($event in @($remoteEnvelope.events)) {
    $normalized = [ordered]@{
        timestamp = [string]$event.timestamp
        kind = [string]$event.kind
        outcome = [string]$event.outcome
    }
    if ($event.PSObject.Properties.Name -contains 'symbol' -and $locatorToBinding.ContainsKey([string]$event.symbol)) {
        $normalized.binding_id = $locatorToBinding[[string]$event.symbol]
    }
    elseif ([string]$event.kind -in @('read', 'write')) {
        throw "Executor emitted an unmapped $($event.kind) event; raw evidence was preserved but normalized facts were not created."
    }
    if ($event.PSObject.Properties.Name -contains 'value') { $normalized.value = $event.value }
    if ($event.PSObject.Properties.Name -contains 'detail') { $normalized.detail = [string]$event.detail }
    $normalized.raw_evidence_ref = $rawReference
    $normalizedEvents += [PSCustomObject]$normalized
}

$facts = [ordered]@{
    schema_version = '0.1.0'
    kind = 'normalized_supervised_probe_facts'
    run_id = [string]$context.Manifest.run_id
    case_id = [string]$context.Manifest.case_id
    asset_id = [string]$context.Manifest.asset_id
    requested_interface = [string]$context.Manifest.requested_interface
    operation_id = $operationId
    input_revisions = @($context.Manifest.input_contracts)
    approval = [ordered]@{
        approved_at = $approvedTimestamp.ToString('o')
        scope = $approvalScope
        maximum_duration_seconds = $HoldSeconds
        restore_target = [string]$operation.restore_target
        source_ref = $ApprovalSourceRef
    }
    started_at = [string]$remoteEnvelope.started_at
    finished_at = [string]$remoteEnvelope.finished_at
    initial_state = $remoteEnvelope.initial_state
    events = $normalizedEvents
    timeouts = $remoteEnvelope.timeouts
    restore = [ordered]@{
        attempted = $true
        status = [string]$remoteEnvelope.restore.status
        evidence_refs = @($rawReference)
    }
    final_state = $remoteEnvelope.final_state
    execution_status = [string]$remoteEnvelope.execution_status
    raw_evidence_refs = @($rawReference)
}
$facts | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $factsPath -Encoding utf8

[PSCustomObject]@{
    ExecutionFactsPath = $factsPath
    RawEvidencePath = $rawAdsPath
    ExecutionStatus = [string]$facts.execution_status
    RestoreStatus = [string]$facts.restore.status
}
