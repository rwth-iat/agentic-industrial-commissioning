[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$PreflightPath,
    [Parameter(Mandatory)][string]$RuntimeBindingsPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$InitialExpectation,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$Step,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$RestoreStep,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$FinalExpectation,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$HumanObservationRequirement,
    [ValidateRange(1, 300)][int]$MaximumDurationSeconds = 30,
    [ValidateRange(1, 120)][int]$RestoreMaximumDurationSeconds = 30,
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

function Get-InputValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-Map {
    param([AllowNull()][object]$Value, [string]$Owner)
    $map = [ordered]@{}
    if ($null -eq $Value) { return $map }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { $map[[string]$key] = $Value[$key] }
        return $map
    }
    foreach ($property in $Value.PSObject.Properties) { $map[[string]$property.Name] = $property.Value }
    if ($map.Count -eq 0) { throw "$Owner must be a property map." }
    return $map
}

function ConvertTo-ExpectationList {
    param([object[]]$Items, [string]$Owner)
    $normalized = @()
    $seen = @{}
    foreach ($item in @($Items)) {
        $id = [string](Get-InputValue -Object $item -Name 'binding_id')
        $value = [string](Get-InputValue -Object $item -Name 'expected_value')
        if ([string]::IsNullOrWhiteSpace($id)) { throw "$Owner requires binding_id." }
        if ([string]::IsNullOrWhiteSpace($value)) { throw "$Owner '$id' requires expected_value." }
        if ($seen.ContainsKey($id)) { throw "$Owner contains duplicate binding '$id'." }
        $seen[$id] = $true
        $entry = [ordered]@{ binding_id = $id; expected_value = $value }
        $tolerance = Get-InputValue -Object $item -Name 'numeric_tolerance'
        if ($null -ne $tolerance) {
            if ([double]$tolerance -lt 0) { throw "$Owner '$id' has negative numeric_tolerance." }
            $entry.numeric_tolerance = [double]$tolerance
        }
        $normalized += [PSCustomObject]$entry
    }
    if ($normalized.Count -eq 0) { throw "$Owner requires at least one entry." }
    return $normalized
}

function ConvertTo-Step {
    param([object]$Item, [string]$Owner)
    $name = [string](Get-InputValue -Object $Item -Name 'name')
    $capability = [string](Get-InputValue -Object $Item -Name 'capability')
    if ([string]::IsNullOrWhiteSpace($name)) { throw "$Owner requires name." }
    if ([string]::IsNullOrWhiteSpace($capability)) { throw "$Owner '$name' requires capability." }
    $readBindings = ConvertTo-Map -Value (Get-InputValue -Object $Item -Name 'read_bindings') -Owner "$Owner '$name' read_bindings"
    $writeBindings = ConvertTo-Map -Value (Get-InputValue -Object $Item -Name 'write_bindings') -Owner "$Owner '$name' write_bindings"
    $arguments = ConvertTo-Map -Value (Get-InputValue -Object $Item -Name 'arguments') -Owner "$Owner '$name' arguments"
    $parameterNames = @($readBindings.Keys) + @($writeBindings.Keys) + @($arguments.Keys)
    if (@($parameterNames | Select-Object -Unique).Count -ne $parameterNames.Count) {
        throw "$Owner '$name' assigns a capability parameter more than once."
    }
    return [PSCustomObject][ordered]@{
        name = $name
        capability = $capability
        read_bindings = $readBindings
        write_bindings = $writeBindings
        arguments = $arguments
    }
}

function Assert-NoFreeSymbolArgument {
    param([AllowNull()][object]$Value, [string]$Path)
    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive) { return }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ([string]$key -match 'Symbol$') { throw "$Path contains free symbol field '$key'. Use a runtime-binding ID." }
            Assert-NoFreeSymbolArgument -Value $Value[$key] -Path "$Path.$key"
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $Value) { Assert-NoFreeSymbolArgument -Value $item -Path "$Path[$index]"; $index++ }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -match 'Symbol$') { throw "$Path contains free symbol field '$($property.Name)'. Use a runtime-binding ID." }
        Assert-NoFreeSymbolArgument -Value $property.Value -Path "$Path.$($property.Name)"
    }
}

if ($Step.Count -gt 32) { throw 'Step is limited to 32 finite capability calls.' }
if ($RestoreStep.Count -gt 16) { throw 'RestoreStep is limited to 16 finite capability calls.' }
$initial = @(ConvertTo-ExpectationList -Items $InitialExpectation -Owner 'InitialExpectation')
$final = @(ConvertTo-ExpectationList -Items $FinalExpectation -Owner 'FinalExpectation')
$steps = @($Step | ForEach-Object { ConvertTo-Step -Item $_ -Owner 'Step' })
$restoreSteps = @($RestoreStep | ForEach-Object { ConvertTo-Step -Item $_ -Owner 'RestoreStep' })
$stepNames = @($steps + $restoreSteps | ForEach-Object { [string]$_.name })
if (@($stepNames | Select-Object -Unique).Count -ne $stepNames.Count) { throw 'Step names must be unique.' }

$catalogPath = Join-Path $repositoryRoot 'capabilities/twincat/ads/catalog.psd1'
$catalog = Import-PowerShellDataFile -LiteralPath $catalogPath
$reservedArguments = @('NetId', 'Port', 'AdsDll', 'HumanApproved')
$bindingIds = @($initial + $final | ForEach-Object { [string]$_.binding_id })
$writableIds = @()
foreach ($currentStep in @($steps + $restoreSteps)) {
    if (-not $catalog.Capabilities.ContainsKey([string]$currentStep.capability)) {
        throw "Step '$($currentStep.name)' references unknown capability '$($currentStep.capability)'."
    }
    $definition = $catalog.Capabilities[[string]$currentStep.capability]
    $recipePath = Join-Path $repositoryRoot "capabilities/twincat/ads/$($definition.Recipe)"
    if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) { throw "Capability '$($currentStep.capability)' recipe is missing." }
    $allowed = @($definition.UserParameters)
    foreach ($parameter in @($currentStep.read_bindings.Keys) + @($currentStep.write_bindings.Keys) + @($currentStep.arguments.Keys)) {
        if ($parameter -in $reservedArguments) { throw "Step '$($currentStep.name)' may not provide reserved parameter '$parameter'." }
        if ($parameter -notin $allowed) { throw "Capability '$($currentStep.capability)' does not declare parameter '$parameter'." }
    }
    foreach ($parameter in @($currentStep.arguments.Keys | Where-Object { $_ -match 'Symbol$' })) {
        throw "Step '$($currentStep.name)' must provide '$parameter' through a runtime-binding ID, not a free symbol."
    }
    Assert-NoFreeSymbolArgument -Value $currentStep.arguments -Path "Step '$($currentStep.name)'.arguments"
    if ([string]$definition.Safety -eq 'STATE_CHANGING' -and $currentStep.write_bindings.Count -eq 0) {
        throw "State-changing step '$($currentStep.name)' requires at least one explicit write binding."
    }
    if ([string]$definition.Safety -eq 'READ_ONLY' -and $currentStep.write_bindings.Count -gt 0) {
        throw "Read-only step '$($currentStep.name)' may not declare write bindings."
    }
    $currentStep | Add-Member -NotePropertyName safety -NotePropertyValue ([string]$definition.Safety)
    $currentStep | Add-Member -NotePropertyName recipe_revision -NotePropertyValue (Get-AicFileRevision -Path $recipePath)
    foreach ($id in @($currentStep.read_bindings.Values)) { $bindingIds += [string]$id }
    foreach ($id in @($currentStep.write_bindings.Values)) { $bindingIds += [string]$id; $writableIds += [string]$id }
}
$mainStateChangeCount = @($steps | Where-Object { $_.safety -eq 'STATE_CHANGING' }).Count
$restoreStateChangeCount = @($restoreSteps | Where-Object { $_.safety -eq 'STATE_CHANGING' }).Count
if ($mainStateChangeCount -eq 0) { throw 'A supervised probe requires at least one state-changing main step.' }
if ($restoreStateChangeCount -eq 0) { throw 'A supervised probe requires at least one state-changing restore step.' }
$bindingIds = @($bindingIds | Select-Object -Unique)
$writableIds = @($writableIds | Select-Object -Unique)
$context = Get-AicProbeContext -ManifestPath $ManifestPath -RuntimeBindingsPath $RuntimeBindingsPath `
    -BindingId $bindingIds -WritableBindingId $writableIds
$preflight = Assert-AicProbePreflight -ManifestPath $ManifestPath -PreflightPath $PreflightPath

$operation = [ordered]@{
    run_id = [string]$context.Manifest.run_id
    case_id = [string]$context.Manifest.case_id
    asset_id = [string]$context.Manifest.asset_id
    requested_interface = [string]$context.Manifest.requested_interface
    connection_profile = [string]$context.Manifest.connection_profile
    initial_expectations = $initial
    steps = $steps
    restore_steps = $restoreSteps
    final_expectations = $final
    human_observation_requirement = $HumanObservationRequirement
    maximum_duration_seconds = $MaximumDurationSeconds
    restore_maximum_duration_seconds = $RestoreMaximumDurationSeconds
}
$operationJson = $operation | ConvertTo-Json -Depth 50 -Compress
$sha256 = [Security.Cryptography.SHA256]::Create()
try { $hashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($operationJson)) }
finally { $sha256.Dispose() }
$operationId = ([BitConverter]::ToString($hashBytes).Replace('-', '')).Substring(0, 12)
$requiredApproval = "APPROVE SUPERVISED_PROBE $operationId"
$mainNames = @($steps | ForEach-Object { "$($_.name):$($_.capability)" }) -join ', '
$restoreNames = @($restoreSteps | ForEach-Object { "$($_.name):$($_.capability)" }) -join ', '
$approvalScope = "Request '$($context.Manifest.requested_interface)' for '$($context.Manifest.asset_id)' in '$($context.Manifest.connection_profile)' using [$mainNames] within $MaximumDurationSeconds second(s); observe '$HumanObservationRequirement'; abort on failure; restore using [$restoreNames] within $RestoreMaximumDurationSeconds second(s)."

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
if ($approvedTimestamp -lt $preflightTimestamp) { throw 'Approval predates the current preflight and cannot authorize this probe.' }
if ($approvedTimestamp -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) { throw 'Approval timestamp is unreasonably far in the future.' }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $repositoryRoot 'creds/twincat-ads.local.psd1' }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "ADS configuration not found: $ConfigPath" }
$adsConfig = Import-PowerShellDataFile -LiteralPath $ConfigPath

$rawDirectory = Join-Path $repositoryRoot "cases/$($context.Manifest.case_id)/raw/runtime/$($context.Manifest.run_id)"
$rawPath = Join-Path $rawDirectory 'probe-capabilities.json'
$factsPath = Join-Path $rawDirectory 'execution-facts.json'
foreach ($path in @($rawPath, $factsPath)) {
    if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite existing runtime evidence: $path" }
}
$null = New-Item -ItemType Directory -Path $rawDirectory -Force
$rawReference = Get-AicRepositoryRelativePath -Path $rawPath
$events = [System.Collections.Generic.List[object]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$startedAt = [DateTimeOffset]::UtcNow
$operationDeadline = $startedAt.AddSeconds($MaximumDurationSeconds)
$timeoutTriggered = $false
$stateChangeAttempted = $false
$mainSucceeded = $false
$restoreStatus = 'unknown'
$initialState = [ordered]@{ known = $false }
$finalState = [ordered]@{ known = $false }

function Save-RawEvidence {
    [ordered]@{
        schema_version = '0.1.0'; kind = 'supervised_capability_sequence_facts'
        started_at = $startedAt.ToString('o'); updated_at = [DateTimeOffset]::UtcNow.ToString('o')
        operation_id = $operationId; results = @($results); events = @($events)
    } | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $rawPath -Encoding utf8
}

function Add-ExecutionEvent {
    param([string]$Kind, [string]$Outcome, [string]$BindingId, [string]$Detail, [string]$Timestamp)
    if ([string]::IsNullOrWhiteSpace($Timestamp)) { $Timestamp = [DateTimeOffset]::UtcNow.ToString('o') }
    $event = [ordered]@{ timestamp = $Timestamp; kind = $Kind; outcome = $Outcome }
    if (-not [string]::IsNullOrWhiteSpace($BindingId)) { $event.binding_id = $BindingId }
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { $event.detail = $Detail }
    $event.raw_evidence_ref = $rawReference
    $events.Add([PSCustomObject]$event)
}

function Invoke-ExpectationCheck {
    param([object[]]$Expectations, [string]$Name)
    $recipeBindings = @($Expectations | ForEach-Object {
        $binding = $context.Bindings[[string]$_.binding_id]
        [PSCustomObject]@{
            BindingId = [string]$binding.id
            Symbol = [string]$binding.locator.value
            Type = ConvertTo-AicPowerShellType -RuntimeType ([string]$binding.datatype)
            RuntimeType = [string]$binding.datatype
            ExpectedValue = [string]$_.expected_value
        }
    })
    $selector = Join-Path $repositoryRoot 'scripts/capabilities/twincat/Invoke-AdsCapability.ps1'
    $parameters = @{ Capability = 'ReadBindingPreflight'; Bindings = $recipeBindings; ExpectedAdsState = 'Run'; ConfigPath = $ConfigPath }
    if (-not [string]::IsNullOrWhiteSpace($StateFile)) { $parameters.StateFile = $StateFile }
    $checkStarted = [DateTimeOffset]::UtcNow
    $output = @(& $selector @parameters 2>&1)
    $envelope = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    $results.Add([PSCustomObject]@{
        name = $Name; capability = 'ReadBindingPreflight'; safety = 'READ_ONLY'
        started_at = $checkStarted.ToString('o'); finished_at = [DateTimeOffset]::UtcNow.ToString('o'); output = $envelope
    })
    foreach ($observation in @($envelope.observations)) {
        if ([string]$observation.check -eq 'binding-value') {
            Add-ExecutionEvent -Kind 'read' -Outcome $(if ([bool]$observation.passed) { 'observed' } else { 'failed' }) `
                -BindingId ([string]$observation.binding_id) -Detail "$Name expected '$($observation.expected)', observed '$($observation.actual)'." `
                -Timestamp ([string]$observation.timestamp)
        }
        elseif ([string]$observation.check -eq 'plc-runtime-state') {
            Add-ExecutionEvent -Kind 'runtime_observation' -Outcome $(if ([bool]$observation.passed) { 'observed' } else { 'failed' }) `
                -Detail "$Name expected PLC '$($observation.expected)', observed '$($observation.actual)'." -Timestamp ([string]$observation.timestamp)
        }
    }
    Save-RawEvidence
    return [PSCustomObject]@{
        Success = [bool]$envelope.success
        Snapshot = [ordered]@{ known = $true; values = @($envelope.observations | Where-Object { $_.check -eq 'binding-value' } | ForEach-Object {
            [PSCustomObject]@{ binding_id = [string]$_.binding_id; value = $_.actual }
        }) }
        Errors = @($envelope.errors)
    }
}

function Invoke-CapabilityStep {
    param([object]$CurrentStep, [switch]$Restore)
    $definition = $catalog.Capabilities[[string]$CurrentStep.capability]
    $arguments = @{
        NetId = $adsConfig.NetId
        Port = $adsConfig[$definition.PortConfigKey]
        AdsDll = $adsConfig.AdsDll
    }
    foreach ($entry in $CurrentStep.read_bindings.GetEnumerator()) {
        $arguments[[string]$entry.Key] = [string]$context.Bindings[[string]$entry.Value].locator.value
    }
    foreach ($entry in $CurrentStep.write_bindings.GetEnumerator()) {
        $arguments[[string]$entry.Key] = [string]$context.Bindings[[string]$entry.Value].locator.value
    }
    foreach ($entry in $CurrentStep.arguments.GetEnumerator()) { $arguments[[string]$entry.Key] = $entry.Value }
    if ([string]$definition.Safety -eq 'STATE_CHANGING') { $arguments.HumanApproved = $true; $script:stateChangeAttempted = $true }

    $recipePath = Join-Path $repositoryRoot "capabilities/twincat/ads/$($definition.Recipe)"
    $remoteInvoker = Join-Path $repositoryRoot 'scripts/remote/Invoke-AgentRemote.ps1'
    $invokeParameters = @{ ScriptPath = $recipePath; Arguments = $arguments }
    if (-not [string]::IsNullOrWhiteSpace($StateFile)) { $invokeParameters.StateFile = $StateFile }
    $stepStarted = [DateTimeOffset]::UtcNow
    $succeeded = $false
    $output = @()
    try {
        $output = @(& $remoteInvoker @invokeParameters 2>&1)
        $succeeded = $true
    }
    catch { $output += $_.Exception.Message }
    $finishedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $results.Add([PSCustomObject]@{
        name = [string]$CurrentStep.name; capability = [string]$CurrentStep.capability; safety = [string]$definition.Safety
        restore = [bool]$Restore; started_at = $stepStarted.ToString('o'); finished_at = $finishedAt
        succeeded = $succeeded; output = ($output -join [Environment]::NewLine)
    })
    $eventKind = if ($Restore) { 'restore' } elseif ([string]$definition.Safety -eq 'STATE_CHANGING') { 'write' } else { 'read' }
    $eventBindings = if ($Restore) { @($CurrentStep.write_bindings.Values) } elseif ($eventKind -eq 'write') { @($CurrentStep.write_bindings.Values) } else { @($CurrentStep.read_bindings.Values) }
    if (@($eventBindings).Count -eq 0) {
        Add-ExecutionEvent -Kind $eventKind -Outcome $(if ($succeeded) { 'succeeded' } else { 'failed' }) `
            -Detail "Capability '$($CurrentStep.capability)' step '$($CurrentStep.name)'." -Timestamp $finishedAt
    }
    else {
        foreach ($id in $eventBindings) {
            Add-ExecutionEvent -Kind $eventKind -Outcome $(if ($succeeded) { 'succeeded' } else { 'failed' }) -BindingId ([string]$id) `
                -Detail "Capability '$($CurrentStep.capability)' step '$($CurrentStep.name)'." -Timestamp $finishedAt
        }
    }
    Save-RawEvidence
    if (-not $succeeded) { throw "Capability step '$($CurrentStep.name)' failed. Raw output was preserved." }
}

if (-not $PSCmdlet.ShouldProcess([string]$context.Manifest.asset_id, "Execute supervised probe $operationId")) { return }
try {
    $check = Invoke-ExpectationCheck -Expectations $initial -Name 'immediate-precondition'
    $initialState = $check.Snapshot
    if (-not $check.Success) { throw "Immediate precondition failed: $(@($check.Errors) -join '; ')" }
    foreach ($currentStep in $steps) {
        if ([DateTimeOffset]::UtcNow -ge $operationDeadline) { $timeoutTriggered = $true; throw 'Supervised sequence exceeded its operation deadline.' }
        Invoke-CapabilityStep -CurrentStep $currentStep
    }
    $mainSucceeded = $true
}
catch {
    Add-ExecutionEvent -Kind $(if ($timeoutTriggered) { 'timeout' } else { 'error' }) -Outcome 'failed' -Detail $_.Exception.Message
    Save-RawEvidence
}
finally {
    if ($stateChangeAttempted) {
        $restoreDeadline = [DateTimeOffset]::UtcNow.AddSeconds($RestoreMaximumDurationSeconds)
        $restoreFailed = $false
        foreach ($currentStep in $restoreSteps) {
            if ([DateTimeOffset]::UtcNow -ge $restoreDeadline) {
                $timeoutTriggered = $true; $restoreFailed = $true
                Add-ExecutionEvent -Kind 'timeout' -Outcome 'failed' -Detail 'Restore sequence exceeded its deadline.'
                break
            }
            try { Invoke-CapabilityStep -CurrentStep $currentStep -Restore }
            catch { $restoreFailed = $true; Add-ExecutionEvent -Kind 'restore' -Outcome 'failed' -Detail $_.Exception.Message }
        }
        try {
            $check = Invoke-ExpectationCheck -Expectations $final -Name 'final-restore-check'
            $finalState = $check.Snapshot
            if (-not $check.Success) { $restoreFailed = $true }
        }
        catch { $restoreFailed = $true; Add-ExecutionEvent -Kind 'restore' -Outcome 'failed' -Detail $_.Exception.Message }
        $restoreStatus = if ($restoreFailed) { 'failed' } else { 'verified' }
    }
    else {
        $finalState = $initialState
        $restoreStatus = 'unknown'
    }
    Save-RawEvidence
}

$executionStatus = if ($mainSucceeded -and $restoreStatus -eq 'verified') { 'succeeded' } elseif ($timeoutTriggered) { 'aborted' } else { 'failed' }
$finishedAt = [DateTimeOffset]::UtcNow
$latestEventAt = $null
foreach ($event in @($events)) {
    try { $eventAt = [DateTimeOffset]::Parse([string]$event.timestamp) }
    catch { continue }
    if ($null -eq $latestEventAt -or $eventAt -gt $latestEventAt) { $latestEventAt = $eventAt }
}
if ($null -ne $latestEventAt -and $latestEventAt -gt $finishedAt) { $finishedAt = $latestEventAt }
$facts = [ordered]@{
    schema_version = '0.1.0'; kind = 'normalized_supervised_probe_facts'
    run_id = [string]$context.Manifest.run_id; case_id = [string]$context.Manifest.case_id
    asset_id = [string]$context.Manifest.asset_id; requested_interface = [string]$context.Manifest.requested_interface
    operation_id = $operationId; input_revisions = @($context.Manifest.input_contracts)
    approval = [ordered]@{
        approved_at = $approvedTimestamp.ToString('o'); scope = $approvalScope
        maximum_duration_seconds = ($MaximumDurationSeconds + $RestoreMaximumDurationSeconds)
        restore_target = "Final expectations: $(@($final | ForEach-Object { "$($_.binding_id)=$($_.expected_value)" }) -join ', ')"
        source_ref = $ApprovalSourceRef
    }
    started_at = $startedAt.ToString('o'); finished_at = $finishedAt.ToString('o')
    initial_state = $initialState; events = @($events)
    timeouts = [ordered]@{ overall_seconds = ($MaximumDurationSeconds + $RestoreMaximumDurationSeconds); triggered = $timeoutTriggered }
    restore = [ordered]@{ attempted = $stateChangeAttempted; status = $restoreStatus; evidence_refs = @($rawReference) }
    final_state = $finalState; execution_status = $executionStatus; raw_evidence_refs = @($rawReference)
}
$facts | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $factsPath -Encoding utf8

[PSCustomObject]@{
    ExecutionFactsPath = $factsPath
    RawEvidencePath = $rawPath
    ExecutionStatus = $executionStatus
    RestoreStatus = $restoreStatus
}
