[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RecordPath,

    [string]$SchemaPath,

    [switch]$SkipPlacement
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'json-schema-validation.common.ps1')
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $repositoryRoot 'spec/commissioning-record.schema.json'
}
$resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path

function Get-PropertyValue {
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Add-RecordError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Path,
        [string]$Message
    )
    $Errors.Add("${Path}: ${Message}")
}

function ConvertTo-Timestamp {
    param(
        [AllowNull()][object]$Value,
        [string]$Path,
        [System.Collections.Generic.List[string]]$Errors
    )
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) {
        Add-RecordError -Errors $Errors -Path $Path -Message 'invalid timestamp'
        return $null
    }
    return $parsed.ToUniversalTime()
}

function Test-ContractRevisionSet {
    param(
        [AllowNull()][object]$Revisions,
        [string]$Path,
        [System.Collections.Generic.List[string]]$Errors
    )
    $requiredKinds = @(
        'hardware_model',
        'software_model',
        'implementation_links',
        'runtime_bindings'
    )
    $items = @(@($Revisions) | Where-Object { $null -ne $_ })
    $kinds = @($items | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'kind') })
    foreach ($kind in $requiredKinds) {
        if (@($kinds | Where-Object { $_ -eq $kind }).Count -ne 1) {
            Add-RecordError -Errors $Errors -Path $Path -Message "requires exactly one '${kind}' revision"
        }
    }
}

function Get-ExpectedRecordPath {
    param([object]$Document)
    $caseId = [string](Get-PropertyValue -Object $Document -Name 'case_id')
    $runId = [string](Get-PropertyValue -Object $Document -Name 'run_id')
    $recordType = [string](Get-PropertyValue -Object $Document -Name 'record_type')
    switch ($recordType) {
        'run_manifest' {
            return Join-Path $repositoryRoot "cases/$caseId/validation/private/$runId/run-manifest.json"
        }
        'preflight' {
            return Join-Path $repositoryRoot "cases/$caseId/validation/private/$runId/preflight.json"
        }
        'execution_record' {
            return Join-Path $repositoryRoot "cases/$caseId/results/private/probes/$runId/execution-record.json"
        }
        default { return $null }
    }
}

function Test-AllowedProperties {
    param(
        [object]$Document,
        [string[]]$Allowed,
        [System.Collections.Generic.List[string]]$Errors
    )
    foreach ($property in $Document.PSObject.Properties.Name) {
        if ($property -notin $Allowed) {
            Add-RecordError -Errors $Errors -Path "$.${property}" -Message "property is not valid for record type '$($Document.record_type)'"
        }
    }
}

function Get-AdapterBindingValues {
    param([AllowNull()][object]$Mapping)

    if ($null -eq $Mapping) { return @() }
    if ($Mapping -is [System.Collections.IDictionary]) {
        return @($Mapping.Values | ForEach-Object { [string]$_ })
    }
    return @($Mapping.PSObject.Properties | ForEach-Object { [string]$_.Value })
}

function Get-RuntimeBindingIds {
    param(
        [AllowNull()][object]$Revisions,
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($null -eq $Revisions) { return @() }
    $runtimeRevision = @(@($Revisions) | Where-Object {
        [string](Get-PropertyValue -Object $_ -Name 'kind') -eq 'runtime_bindings'
    })
    if ($runtimeRevision.Count -ne 1) { return @() }

    $relativePath = [string](Get-PropertyValue -Object $runtimeRevision[0] -Name 'path')
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath)) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.input_revisions' -Message 'runtime-binding path must be repository-relative'
        return @()
    }
    $runtimePath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $relativePath))
    $repositoryPrefix = $repositoryRoot
    if (-not $repositoryPrefix.EndsWith([string][IO.Path]::DirectorySeparatorChar)) {
        $repositoryPrefix += [IO.Path]::DirectorySeparatorChar
    }
    if (-not $runtimePath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.input_revisions' -Message 'runtime-binding file does not exist inside the repository'
        return @()
    }
    try { $runtimeBindings = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json }
    catch {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.input_revisions' -Message "runtime-binding file is not valid JSON: $($_.Exception.Message)"
        return @()
    }
    return @(@($runtimeBindings.bindings) | ForEach-Object { [string]$_.id })
}

function Test-AdapterActionContract {
    param(
        [object]$Verification,
        [string]$EntrypointPath,
        [AllowNull()][object]$Revisions,
        [System.Collections.Generic.List[string]]$Errors
    )

    if ([IO.Path]::GetExtension($EntrypointPath) -ne '.ps1') {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message 'current completion gate supports PowerShell component adapters only'
        return
    }

    try { $command = Get-Command -Name $EntrypointPath -ErrorAction Stop }
    catch {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "could not inspect adapter entrypoint: $($_.Exception.Message)"
        return
    }
    if (-not $command.Parameters.ContainsKey('Describe') -or -not $command.Parameters.ContainsKey('Action')) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message 'component adapter must support side-effect-free -Describe and -Action planning'
        return
    }

    try { $descriptionOutput = @(& $EntrypointPath -Describe) }
    catch {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter -Describe failed: $($_.Exception.Message)"
        return
    }
    if ($descriptionOutput.Count -ne 1) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message 'adapter -Describe must return exactly one descriptor'
        return
    }

    $description = $descriptionOutput[0]
    if ([string](Get-PropertyValue -Object $description -Name 'adapter_kind') -ne 'component_actions') {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter -Describe must declare adapter_kind 'component_actions'"
    }
    $actions = @(@((Get-PropertyValue -Object $description -Name 'actions')) | Where-Object { $null -ne $_ })
    if ($actions.Count -eq 0) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message 'adapter -Describe must expose at least one semantic action'
        return
    }

    $actionIds = @($actions | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'id') })
    $supportedInterfaces = @((Get-PropertyValue -Object $Verification -Name 'supported_interfaces') | ForEach-Object { [string]$_ })
    if (@($actionIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
        @($actionIds | Sort-Object -Unique).Count -ne $actionIds.Count) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message 'adapter action IDs must be non-empty and unique'
        return
    }
    $actionSignature = @($actionIds | Sort-Object) -join "`n"
    $interfaceSignature = @($supportedInterfaces | Sort-Object) -join "`n"
    if ($actionSignature -ne $interfaceSignature) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref.supported_interfaces' -Message 'must exactly match independently exposed adapter actions'
    }

    $runtimeBindingIds = @(Get-RuntimeBindingIds -Revisions $Revisions -Errors $Errors)
    foreach ($action in $actions) {
        $actionId = [string](Get-PropertyValue -Object $action -Name 'id')
        $safety = [string](Get-PropertyValue -Object $action -Name 'safety')
        if ($safety -notin @('READ_ONLY', 'STATE_CHANGING')) {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' has unsupported safety '$safety'"
            continue
        }

        try { $planOutput = @(& $EntrypointPath -Action $actionId) }
        catch {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' cannot be planned independently: $($_.Exception.Message)"
            continue
        }
        if ($planOutput.Count -ne 1) {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' planning must return exactly one plan"
            continue
        }

        $plan = $planOutput[0]
        if ([string](Get-PropertyValue -Object $plan -Name 'action') -ne $actionId -or
            [string](Get-PropertyValue -Object $plan -Name 'safety') -ne $safety) {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' plan identity or safety does not match -Describe"
        }
        $steps = @(@((Get-PropertyValue -Object $plan -Name 'steps')) | Where-Object { $null -ne $_ })
        if ($steps.Count -eq 0) {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' plan must contain at least one step"
            continue
        }

        $effectCount = 0
        foreach ($step in $steps) {
            $role = [string](Get-PropertyValue -Object $step -Name 'role')
            $semanticAction = [string](Get-PropertyValue -Object $step -Name 'semantic_action')
            if ($role -notin @('prerequisite', 'effect', 'observation')) {
                Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' step has unsupported role '$role'"
            }
            if ($role -eq 'effect') {
                $effectCount++
                if ($semanticAction -ne $actionId) {
                    Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' plan contains another semantic effect '$semanticAction'"
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($semanticAction) -and $semanticAction -ne $actionId) {
                Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' plan contains another semantic action '$semanticAction'"
            }

            $readBindings = @(Get-AdapterBindingValues -Mapping (Get-PropertyValue -Object $step -Name 'read_bindings'))
            $writeBindings = @(Get-AdapterBindingValues -Mapping (Get-PropertyValue -Object $step -Name 'write_bindings'))
            if ($safety -eq 'READ_ONLY' -and $writeBindings.Count -gt 0) {
                Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "read-only adapter action '$actionId' declares write bindings"
            }
            if ($runtimeBindingIds.Count -gt 0) {
                foreach ($bindingId in @($readBindings + $writeBindings)) {
                    if ($bindingId -notin $runtimeBindingIds) {
                        Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "adapter action '$actionId' uses unknown binding ID '$bindingId'"
                    }
                }
            }
        }
        if ($safety -eq 'STATE_CHANGING' -and $effectCount -eq 0) {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref.entrypoint' -Message "state-changing adapter action '$actionId' has no semantic effect step"
        }
    }
}

function Test-AdapterReference {
    param(
        [object]$Document,
        [AllowNull()][object]$Revisions,
        [System.Collections.Generic.List[string]]$Errors
    )

    $reference = [string](Get-PropertyValue -Object $Document -Name 'adapter_ref')
    if ([string]::IsNullOrWhiteSpace($reference)) { return }
    $normalized = $reference.Replace('\', '/')
    if ([IO.Path]::IsPathRooted($reference) -or
        $normalized -notmatch '^generated/connectors/[^/]+/components/[^/]+/verification\.json$') {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'must reference generated/connectors/<environment>/components/<component>/verification.json'
        return
    }

    $generatedRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'generated/connectors'))
    $verificationPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $normalized))
    $prefix = $generatedRoot
    if (-not $prefix.EndsWith([string][IO.Path]::DirectorySeparatorChar)) { $prefix += [IO.Path]::DirectorySeparatorChar }
    if (-not $verificationPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'referenced adapter verification file does not exist'
        return
    }

    try { $verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json }
    catch {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message "verification file is not valid JSON: $($_.Exception.Message)"
        return
    }
    if ([string](Get-PropertyValue -Object $verification -Name 'schema_version') -ne '0.1.0') {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'unsupported adapter verification schema_version'
    }
    if ([string](Get-PropertyValue -Object $verification -Name 'verification_status') -ne 'verified') {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'adapter verification_status must be verified'
    }
    if ([string](Get-PropertyValue -Object $verification -Name 'asset_id') -ne [string]$Document.asset_id) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'adapter asset_id does not match the commissioning record'
    }
    if ([string]$Document.requested_interface -notin @((Get-PropertyValue -Object $verification -Name 'supported_interfaces'))) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'adapter does not declare the requested interface'
    }
    $evidenceRefs = @((Get-PropertyValue -Object $verification -Name 'evidence_refs'))
    if ($evidenceRefs.Count -eq 0) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'adapter verification requires evidence_refs'
    }

    $entrypoint = [string](Get-PropertyValue -Object $verification -Name 'entrypoint')
    $adapterDirectory = Split-Path -Parent $verificationPath
    if ([string]::IsNullOrWhiteSpace($entrypoint) -or [IO.Path]::IsPathRooted($entrypoint)) {
        Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'adapter verification requires a relative entrypoint'
    }
    else {
        $entrypointPath = [IO.Path]::GetFullPath((Join-Path $adapterDirectory $entrypoint))
        $adapterPrefix = $adapterDirectory
        if (-not $adapterPrefix.EndsWith([string][IO.Path]::DirectorySeparatorChar)) { $adapterPrefix += [IO.Path]::DirectorySeparatorChar }
        if (-not $entrypointPath.StartsWith($adapterPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $entrypointPath -PathType Leaf)) {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'adapter entrypoint does not exist inside the adapter directory'
        }
        else {
            Test-AdapterActionContract -Verification $verification -EntrypointPath $entrypointPath -Revisions $Revisions -Errors $Errors
        }
    }

    if ($null -ne $Revisions) {
        $verificationRevisions = Get-PropertyValue -Object $verification -Name 'input_revisions'
        Test-ContractRevisionSet -Revisions $verificationRevisions -Path '$.adapter_ref.input_revisions' -Errors $Errors
        if ((Get-RevisionSignature -Revisions $verificationRevisions) -ne (Get-RevisionSignature -Revisions $Revisions)) {
            Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'adapter input revisions do not match the commissioning run'
        }
    }
}

function Test-RecordSemantics {
    param(
        [object]$Document,
        [string]$ResolvedPath,
        [System.Collections.Generic.List[string]]$Errors
    )
    $common = @(
        'schema_version', 'record_type', 'run_id', 'case_id', 'asset_id',
        'requested_interface', 'created_at', 'data_classification'
    )
    $recordType = [string](Get-PropertyValue -Object $Document -Name 'record_type')
    switch ($recordType) {
        'run_manifest' {
            Test-AllowedProperties -Document $Document -Allowed ($common + @(
                'repository_revision', 'connection_profile', 'input_contracts', 'safety_boundary'
            )) -Errors $Errors
            Test-ContractRevisionSet -Revisions $Document.input_contracts -Path '$.input_contracts' -Errors $Errors
        }
        'preflight' {
            Test-AllowedProperties -Document $Document -Allowed ($common + @(
                'observed_at', 'raw_evidence_refs', 'checks', 'hypotheses',
                'assessment', 'blockers', 'writes_observed', 'adapter_ref'
            )) -Errors $Errors
            $blockers = @($Document.blockers)
            if ($Document.assessment -eq 'hard_blocked' -and $blockers.Count -eq 0) {
                Add-RecordError -Errors $Errors -Path '$.blockers' -Message 'hard_blocked requires a concrete blocker and reevaluation path'
            }
            if ($Document.assessment -ne 'hard_blocked' -and $blockers.Count -gt 0) {
                Add-RecordError -Errors $Errors -Path '$.blockers' -Message 'a non-blocked assessment must not contain hard blockers'
            }
            $failedChecks = @($Document.checks | Where-Object { $_.status -eq 'failed' })
            if ($Document.assessment -ne 'hard_blocked' -and $failedChecks.Count -gt 0) {
                Add-RecordError -Errors $Errors -Path '$.assessment' -Message 'failed preflight checks require hard_blocked'
            }
            if ($Document.assessment -eq 'validated_interface') {
                if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Document -Name 'adapter_ref'))) {
                    Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'validated_interface requires a verified adapter reference'
                }
                else {
                    Test-AdapterReference -Document $Document -Revisions $null -Errors $Errors
                }
            }
        }
        'execution_record' {
            Test-AllowedProperties -Document $Document -Allowed ($common + @(
                'input_revisions', 'started_at', 'finished_at', 'initial_state',
                'approval', 'events', 'timeouts', 'human_observations', 'restore',
                'hypotheses', 'final_state', 'execution_status',
                'resulting_assessment', 'adapter_ref'
            )) -Errors $Errors
            Test-ContractRevisionSet -Revisions $Document.input_revisions -Path '$.input_revisions' -Errors $Errors

            $startedAt = ConvertTo-Timestamp -Value $Document.started_at -Path '$.started_at' -Errors $Errors
            $finishedAt = ConvertTo-Timestamp -Value $Document.finished_at -Path '$.finished_at' -Errors $Errors
            if ($null -ne $startedAt -and $null -ne $finishedAt -and $startedAt -gt $finishedAt) {
                Add-RecordError -Errors $Errors -Path '$.finished_at' -Message 'must not precede started_at'
            }

            $events = @($Document.events)
            if (@($events | Where-Object { $_.kind -eq 'read' }).Count -eq 0) {
                Add-RecordError -Errors $Errors -Path '$.events' -Message 'execution must contain at least one actual read'
            }
            if (@($events | Where-Object { $_.kind -eq 'write' }).Count -eq 0) {
                Add-RecordError -Errors $Errors -Path '$.events' -Message 'execution must contain at least one actual write'
            }

            $previous = $startedAt
            for ($index = 0; $index -lt $events.Count; $index++) {
                $eventTime = ConvertTo-Timestamp -Value $events[$index].timestamp -Path "$.events[${index}].timestamp" -Errors $Errors
                if ($null -eq $eventTime) { continue }
                if ($null -ne $previous -and $eventTime -lt $previous) {
                    Add-RecordError -Errors $Errors -Path "$.events[${index}].timestamp" -Message 'events must be chronological and not precede started_at'
                }
                if ($null -ne $finishedAt -and $eventTime -gt $finishedAt) {
                    Add-RecordError -Errors $Errors -Path "$.events[${index}].timestamp" -Message 'event must not follow finished_at'
                }
                $previous = $eventTime
            }

            $timeoutEvents = @($events | Where-Object { $_.kind -eq 'timeout' })
            if ([bool]$Document.timeouts.triggered -and $timeoutEvents.Count -eq 0) {
                Add-RecordError -Errors $Errors -Path '$.timeouts.triggered' -Message 'a triggered timeout requires a timeout event'
            }
            if (-not [bool]$Document.timeouts.triggered -and $timeoutEvents.Count -gt 0) {
                Add-RecordError -Errors $Errors -Path '$.timeouts.triggered' -Message 'a timeout event requires triggered=true'
            }

            if ($Document.execution_status -eq 'succeeded' -and $Document.restore.status -ne 'verified') {
                Add-RecordError -Errors $Errors -Path '$.restore.status' -Message 'successful execution requires verified restore'
            }
            if ($Document.restore.status -eq 'failed' -and $Document.resulting_assessment -ne 'hard_blocked') {
                Add-RecordError -Errors $Errors -Path '$.resulting_assessment' -Message 'failed restore requires hard_blocked'
            }
            if ($Document.resulting_assessment -eq 'validated_interface') {
                if ($Document.execution_status -ne 'succeeded' -or $Document.restore.status -ne 'verified') {
                    Add-RecordError -Errors $Errors -Path '$.resulting_assessment' -Message 'validated_interface requires successful execution and verified restore'
                }
                if (@($Document.human_observations).Count -eq 0) {
                    Add-RecordError -Errors $Errors -Path '$.human_observations' -Message 'validated_interface requires a retained human observation for the current supervised actuator path'
                }
                if (@($Document.hypotheses | Where-Object { $_.status -eq 'confirmed' }).Count -eq 0) {
                    Add-RecordError -Errors $Errors -Path '$.hypotheses' -Message 'validated_interface requires a confirmed interaction hypothesis'
                }
                if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Document -Name 'adapter_ref'))) {
                    Add-RecordError -Errors $Errors -Path '$.adapter_ref' -Message 'validated_interface requires a verified adapter reference'
                }
                else {
                    Test-AdapterReference -Document $Document -Revisions $Document.input_revisions -Errors $Errors
                }
            }
        }
    }

    if (-not $SkipPlacement) {
        $expectedPath = Get-ExpectedRecordPath -Document $Document
        if ($null -ne $expectedPath -and
            -not [string]::Equals([IO.Path]::GetFullPath($ResolvedPath), [IO.Path]::GetFullPath($expectedPath), [StringComparison]::OrdinalIgnoreCase)) {
            Add-RecordError -Errors $Errors -Path '$' -Message "record must be stored at '$expectedPath'"
        }
    }
}

function Get-RevisionSignature {
    param([object]$Revisions)
    return (@($Revisions) | Sort-Object kind | ForEach-Object {
        "$($_.kind)|$($_.path)|$($_.revision)"
    }) -join "`n"
}

$records = @()
$errorsByPath = @{}
foreach ($path in $RecordPath) {
    $resolvedPath = (Resolve-Path -LiteralPath $path).Path
    $errors = [System.Collections.Generic.List[string]]::new()
    $errorsByPath[$resolvedPath] = $errors
    $schemaResult = Test-JsonSchemaFile -DocumentPath $resolvedPath -SchemaPath $resolvedSchemaPath
    if (-not $schemaResult.Valid) {
        Add-RecordError -Errors $errors -Path '$' -Message "schema validation failed using $($schemaResult.Engine): $($schemaResult.Error)"
        continue
    }
    try {
        $document = Get-Content -Raw -LiteralPath $resolvedPath | ConvertFrom-Json
        Test-RecordSemantics -Document $document -ResolvedPath $resolvedPath -Errors $errors
        $records += [PSCustomObject]@{ Path = $resolvedPath; Document = $document }
    }
    catch {
        Add-RecordError -Errors $errors -Path '$' -Message "semantic validation could not complete: $($_.Exception.Message)"
    }
}

foreach ($group in @($records | Group-Object { $_.Document.run_id })) {
    if ($group.Count -lt 2) { continue }
    $baseline = $group.Group[0].Document
    $types = @{}
    foreach ($record in $group.Group) {
        $document = $record.Document
        $errors = $errorsByPath[$record.Path]
        foreach ($identity in @('case_id', 'asset_id', 'requested_interface')) {
            if ([string]$document.$identity -ne [string]$baseline.$identity) {
                Add-RecordError -Errors $errors -Path "$.${identity}" -Message "does not match other records for run '$($document.run_id)'"
            }
        }
        if ($types.ContainsKey([string]$document.record_type)) {
            Add-RecordError -Errors $errors -Path '$.record_type' -Message "duplicate record type for run '$($document.run_id)'"
        }
        else {
            $types[[string]$document.record_type] = $document
        }
    }
    if ($types.ContainsKey('run_manifest') -and $types.ContainsKey('execution_record')) {
        $manifestSignature = Get-RevisionSignature -Revisions $types.run_manifest.input_contracts
        $executionSignature = Get-RevisionSignature -Revisions $types.execution_record.input_revisions
        if ($manifestSignature -ne $executionSignature) {
            $executionRecord = @($group.Group | Where-Object { $_.Document.record_type -eq 'execution_record' })[0]
            Add-RecordError -Errors $errorsByPath[$executionRecord.Path] -Path '$.input_revisions' -Message 'does not match run-manifest input_contracts'
        }
    }
    if ($types.ContainsKey('run_manifest') -and $types.ContainsKey('preflight') -and
        [string]$types.preflight.assessment -eq 'validated_interface') {
        $preflightRecord = @($group.Group | Where-Object { $_.Document.record_type -eq 'preflight' })[0]
        Test-AdapterReference -Document $types.preflight -Revisions $types.run_manifest.input_contracts `
            -Errors $errorsByPath[$preflightRecord.Path]
    }
}

$hasFailures = $false
foreach ($path in $errorsByPath.Keys) {
    $errors = $errorsByPath[$path]
    if ($errors.Count -eq 0) {
        Write-Output "PASS $path"
        continue
    }
    $hasFailures = $true
    Write-Output "FAIL $path"
    foreach ($validationError in $errors) {
        Write-Output "  - $validationError"
    }
}

if ($hasFailures) { exit 1 }
exit 0
