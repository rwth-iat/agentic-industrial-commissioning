[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$OperationPath,

    [string]$SchemaPath,

    [string]$RuntimeBindingPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $repositoryRoot 'spec/controlled-operation.schema.json'
}
$resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path

function Get-PropertyValue {
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Add-ValidationError {
    param([System.Collections.Generic.List[string]]$Errors, [string]$Path, [string]$Message)
    $Errors.Add("${Path}: ${Message}")
}

$runtimeBindingsById = $null
$runtimeEnvironmentId = $null
if (-not [string]::IsNullOrWhiteSpace($RuntimeBindingPath)) {
    $runtimeDocument = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $RuntimeBindingPath).Path | ConvertFrom-Json
    $runtimeEnvironmentId = [string](Get-PropertyValue -Object $runtimeDocument.environment -Name 'id')
    $runtimeBindingsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($binding in @($runtimeDocument.bindings)) {
        $runtimeBindingsById.Add([string]$binding.id, $binding)
    }
}

function Test-OperationSemantics {
    param([object]$Document, [System.Collections.Generic.List[string]]$Errors)

    $sourceTypes = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $sourceIndex = 0
    foreach ($source in @($Document.sources)) {
        $sourceId = [string]$source.id
        if ($sourceTypes.ContainsKey($sourceId)) {
            Add-ValidationError -Errors $Errors -Path "$.sources[${sourceIndex}].id" -Message "duplicate source ID '${sourceId}'"
        }
        else {
            $sourceTypes.Add($sourceId, [string]$source.type)
        }
        $sourceIndex++
    }

    $hasRuntimeObservation = $false
    $sourceRefIndex = 0
    foreach ($sourceRefValue in @($Document.source_refs)) {
        $sourceRef = [string]$sourceRefValue
        if (-not $sourceTypes.ContainsKey($sourceRef)) {
            Add-ValidationError -Errors $Errors -Path "$.source_refs[${sourceRefIndex}]" -Message "unknown source '${sourceRef}'"
        }
        elseif ($sourceTypes[$sourceRef] -eq 'runtime_observation') {
            $hasRuntimeObservation = $true
        }
        $sourceRefIndex++
    }
    if ([string]$Document.status -eq 'validated' -and -not $hasRuntimeObservation) {
        Add-ValidationError -Errors $Errors -Path '$.status' -Message 'validated operation requires runtime_observation evidence'
    }

    if ($null -ne $runtimeBindingsById -and [string]$Document.environment_id -ne $runtimeEnvironmentId) {
        Add-ValidationError -Errors $Errors -Path '$.environment_id' -Message "does not match runtime-binding environment '${runtimeEnvironmentId}'"
    }

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $allConditions = @(@($Document.preconditions) + @($Document.observations))
    for ($conditionIndex = 0; $conditionIndex -lt $allConditions.Count; $conditionIndex++) {
        $condition = $allConditions[$conditionIndex]
        if (-not $ids.Add([string]$condition.id)) {
            Add-ValidationError -Errors $Errors -Path '$.conditions' -Message "duplicate operation item ID '$($condition.id)'"
        }
        if ($null -ne $runtimeBindingsById -and -not $runtimeBindingsById.ContainsKey([string]$condition.binding_id)) {
            Add-ValidationError -Errors $Errors -Path '$.conditions' -Message "unknown binding '$($condition.binding_id)'"
        }
    }

    $allSteps = @(@($Document.steps) + @($Document.restore.steps))
    $hasStateChangingStep = $false
    foreach ($step in $allSteps) {
        if (-not $ids.Add([string]$step.id)) {
            Add-ValidationError -Errors $Errors -Path '$.steps' -Message "duplicate operation item ID '$($step.id)'"
        }
        $kind = [string]$step.kind
        if ($kind -in @('write_binding_guarded', 'pulse_request')) {
            $hasStateChangingStep = $true
        }
        foreach ($bindingProperty in @('binding_id', 'acknowledgement_binding_id')) {
            $bindingIdValue = Get-PropertyValue -Object $step -Name $bindingProperty
            if ($null -eq $bindingIdValue -or $null -eq $runtimeBindingsById) { continue }
            $bindingId = [string]$bindingIdValue
            if (-not $runtimeBindingsById.ContainsKey($bindingId)) {
                Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.${bindingProperty}" -Message "unknown binding '${bindingId}'"
                continue
            }
            if ($bindingProperty -eq 'binding_id' -and $kind -in @('write_binding_guarded', 'pulse_request')) {
                $access = [string]$runtimeBindingsById[$bindingId].access
                if ($access -notin @('write', 'read_write')) {
                    Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.binding_id" -Message "binding '${bindingId}' is not writable"
                }
                if ($kind -eq 'write_binding_guarded') {
                    $datatype = [string]$runtimeBindingsById[$bindingId].datatype
                    if ($datatype -in @('SINT', 'USINT', 'INT', 'UINT', 'DINT', 'UDINT', 'REAL', 'LREAL', 'Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Byte')) {
                        $minimum = Get-PropertyValue -Object $step -Name 'minimum'
                        $maximum = Get-PropertyValue -Object $step -Name 'maximum'
                        if ($null -eq $minimum -or $null -eq $maximum) {
                            Add-ValidationError -Errors $Errors -Path "step '$($step.id)'" -Message 'numeric guarded write requires minimum and maximum'
                        }
                        elseif ([double]$minimum -gt [double]$maximum) {
                            Add-ValidationError -Errors $Errors -Path "step '$($step.id)'" -Message 'minimum exceeds maximum'
                        }
                        else {
                            if ([double]$step.expected_current -lt [double]$minimum -or [double]$step.expected_current -gt [double]$maximum) {
                                Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.expected_current" -Message 'expected current value is outside the declared operation range'
                            }
                            if ([double]$step.value -lt [double]$minimum -or [double]$step.value -gt [double]$maximum) {
                                Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.value" -Message 'value is outside the declared operation range'
                            }
                            $bindingConstraints = Get-PropertyValue -Object $runtimeBindingsById[$bindingId] -Name 'write_constraints'
                            if ($null -ne $bindingConstraints) {
                                $bindingMinimum = Get-PropertyValue -Object $bindingConstraints -Name 'minimum'
                                $bindingMaximum = Get-PropertyValue -Object $bindingConstraints -Name 'maximum'
                                if ($null -ne $bindingMinimum -and [double]$minimum -lt [double]$bindingMinimum) {
                                    Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.minimum" -Message 'operation range is wider than the binding minimum'
                                }
                                if ($null -ne $bindingMaximum -and [double]$maximum -gt [double]$bindingMaximum) {
                                    Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.maximum" -Message 'operation range is wider than the binding maximum'
                                }
                            }
                        }
                    }
                }
            }
        }
        if ($null -ne $runtimeBindingsById -and $kind -eq 'pulse_request') {
            $requestBindingId = [string]$step.binding_id
            if ($runtimeBindingsById.ContainsKey($requestBindingId)) {
                $requestBinding = $runtimeBindingsById[$requestBindingId]
                if ([string]$requestBinding.datatype -notin @('BOOL', 'Boolean')) {
                    Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.binding_id" -Message "pulse request binding '${requestBindingId}' is not Boolean"
                }
                $declaredAcknowledgement = [string](
                    Get-PropertyValue -Object $requestBinding.interaction -Name 'acknowledgement_binding_id'
                )
                if (-not [string]::IsNullOrWhiteSpace($declaredAcknowledgement) -and
                    $declaredAcknowledgement -ne [string]$step.acknowledgement_binding_id) {
                    Add-ValidationError -Errors $Errors -Path "step '$($step.id)'.acknowledgement_binding_id" -Message "does not match binding-declared acknowledgement '${declaredAcknowledgement}'"
                }
            }
        }
    }

    if ($hasStateChangingStep) {
        if ([string]$Document.restore.policy -eq 'not_applicable') {
            Add-ValidationError -Errors $Errors -Path '$.restore.policy' -Message 'state-changing operation cannot declare restore not applicable'
        }
        if ([string]$Document.restore.policy -eq 'required' -and @($Document.restore.steps).Count -eq 0) {
            Add-ValidationError -Errors $Errors -Path '$.restore.steps' -Message 'required restore policy needs at least one step'
        }
        if ([string]$Document.restore.policy -eq 'manual_only' -and
            [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Document.restore -Name 'rationale'))) {
            Add-ValidationError -Errors $Errors -Path '$.restore.rationale' -Message 'manual-only restore requires a rationale'
        }
    }
}

$hasFailures = $false
foreach ($path in $OperationPath) {
    $resolvedOperationPath = (Resolve-Path -LiteralPath $path).Path
    $errors = [System.Collections.Generic.List[string]]::new()
    $rawDocument = Get-Content -Raw -LiteralPath $resolvedOperationPath
    $schemaValid = $false
    try {
        $schemaValid = Test-Json -Json $rawDocument -SchemaFile $resolvedSchemaPath -ErrorAction SilentlyContinue
    }
    catch {
        Add-ValidationError -Errors $errors -Path '$' -Message "schema validation failed: $($_.Exception.Message)"
    }
    if (-not $schemaValid -and $errors.Count -eq 0) {
        Add-ValidationError -Errors $errors -Path '$' -Message 'document does not conform to the controlled-operation JSON Schema'
    }
    if ($schemaValid) {
        try {
            $document = $rawDocument | ConvertFrom-Json
            Test-OperationSemantics -Document $document -Errors $errors
        }
        catch {
            Add-ValidationError -Errors $errors -Path '$' -Message "semantic validation could not complete: $($_.Exception.Message)"
        }
    }
    if ($errors.Count -eq 0) {
        Write-Output "PASS $resolvedOperationPath"
        continue
    }
    $hasFailures = $true
    Write-Output "FAIL $resolvedOperationPath"
    $errors | ForEach-Object { Write-Output "  - $_" }
}

if ($hasFailures) { exit 1 }
exit 0
