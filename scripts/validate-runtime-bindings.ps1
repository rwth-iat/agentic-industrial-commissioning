[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$BindingPath,

    [string]$SchemaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $repositoryRoot 'spec/runtime-binding.schema.json'
}

$resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path

function Get-PropertyValue {
    param(
        [AllowNull()]
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Add-ValidationError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Path,
        [string]$Message
    )

    $Errors.Add("${Path}: ${Message}")
}

function Test-RuntimeBindingSemantics {
    param(
        [object]$Document,
        [System.Collections.Generic.List[string]]$Errors
    )

    $sourceTypes = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $sources = @(@(Get-PropertyValue -Object $Document -Name 'sources') | Where-Object { $null -ne $_ })
    for ($sourceIndex = 0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
        $sourceId = [string](Get-PropertyValue -Object $sources[$sourceIndex] -Name 'id')
        if ($sourceTypes.ContainsKey($sourceId)) {
            Add-ValidationError -Errors $Errors -Path "$.sources[${sourceIndex}].id" -Message "duplicate source ID '${sourceId}'"
            continue
        }
        $sourceTypes.Add($sourceId, [string](Get-PropertyValue -Object $sources[$sourceIndex] -Name 'type'))
    }

    $bindingsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $bindings = @(@(Get-PropertyValue -Object $Document -Name 'bindings') | Where-Object { $null -ne $_ })
    for ($bindingIndex = 0; $bindingIndex -lt $bindings.Count; $bindingIndex++) {
        $binding = $bindings[$bindingIndex]
        $bindingId = [string](Get-PropertyValue -Object $binding -Name 'id')
        if ($bindingsById.ContainsKey($bindingId)) {
            Add-ValidationError -Errors $Errors -Path "$.bindings[${bindingIndex}].id" -Message "duplicate binding ID '${bindingId}'"
            continue
        }
        $bindingsById.Add($bindingId, $binding)
    }

    for ($bindingIndex = 0; $bindingIndex -lt $bindings.Count; $bindingIndex++) {
        $binding = $bindings[$bindingIndex]
        $bindingPath = "$.bindings[${bindingIndex}]"
        $bindingId = [string](Get-PropertyValue -Object $binding -Name 'id')
        $hasRuntimeObservation = $false

        $sourceRefs = @(@(Get-PropertyValue -Object $binding -Name 'source_refs') | Where-Object { $null -ne $_ })
        for ($sourceRefIndex = 0; $sourceRefIndex -lt $sourceRefs.Count; $sourceRefIndex++) {
            $sourceRef = [string]$sourceRefs[$sourceRefIndex]
            if (-not $sourceTypes.ContainsKey($sourceRef)) {
                Add-ValidationError -Errors $Errors -Path "${bindingPath}.source_refs[${sourceRefIndex}]" -Message "unknown source '${sourceRef}'"
                continue
            }
            if ($sourceTypes[$sourceRef] -eq 'runtime_observation') {
                $hasRuntimeObservation = $true
            }
        }

        $status = [string](Get-PropertyValue -Object $binding -Name 'status')
        if ($status -eq 'validated' -and -not $hasRuntimeObservation) {
            Add-ValidationError -Errors $Errors -Path "${bindingPath}.status" -Message "validated binding '${bindingId}' requires runtime_observation evidence"
        }

        $access = [string](Get-PropertyValue -Object $binding -Name 'access')
        $datatype = [string](Get-PropertyValue -Object $binding -Name 'datatype')
        $interaction = Get-PropertyValue -Object $binding -Name 'interaction'
        $semantics = [string](Get-PropertyValue -Object $interaction -Name 'semantics')
        $writeConstraints = Get-PropertyValue -Object $binding -Name 'write_constraints'
        if ($access -in @('write', 'read_write') -and
            $semantics -eq 'setpoint' -and
            $datatype -in @('SINT', 'USINT', 'INT', 'UINT', 'DINT', 'UDINT', 'REAL', 'LREAL', 'Int16', 'UInt16', 'Int32', 'UInt32', 'Single', 'Double', 'Byte') -and
            $null -eq $writeConstraints) {
            Add-ValidationError -Errors $Errors -Path "${bindingPath}.write_constraints" -Message "numeric writable setpoint '${bindingId}' requires explicit write constraints"
        }
        if ($null -ne $writeConstraints) {
            $minimum = Get-PropertyValue -Object $writeConstraints -Name 'minimum'
            $maximum = Get-PropertyValue -Object $writeConstraints -Name 'maximum'
            if ($null -ne $minimum -and $null -ne $maximum -and [double]$minimum -gt [double]$maximum) {
                Add-ValidationError -Errors $Errors -Path "${bindingPath}.write_constraints" -Message 'minimum exceeds maximum'
            }
        }

        $acknowledgementBindingIdValue = Get-PropertyValue -Object $interaction -Name 'acknowledgement_binding_id'
        if ($null -eq $acknowledgementBindingIdValue) { continue }

        $acknowledgementBindingId = [string]$acknowledgementBindingIdValue
        if ($acknowledgementBindingId -eq $bindingId) {
            Add-ValidationError -Errors $Errors -Path "${bindingPath}.interaction.acknowledgement_binding_id" -Message 'binding cannot acknowledge itself'
        }
        elseif (-not $bindingsById.ContainsKey($acknowledgementBindingId)) {
            Add-ValidationError -Errors $Errors -Path "${bindingPath}.interaction.acknowledgement_binding_id" -Message "unknown binding '${acknowledgementBindingId}'"
        }
        else {
            $assetId = [string](Get-PropertyValue -Object $binding -Name 'asset_id')
            $acknowledgementAssetId = [string](Get-PropertyValue -Object $bindingsById[$acknowledgementBindingId] -Name 'asset_id')
            if ($assetId -ne $acknowledgementAssetId) {
                Add-ValidationError -Errors $Errors -Path "${bindingPath}.interaction.acknowledgement_binding_id" -Message "acknowledgement binding '${acknowledgementBindingId}' belongs to different asset '${acknowledgementAssetId}'"
            }
        }
    }
}

$hasFailures = $false
foreach ($path in $BindingPath) {
    $resolvedBindingPath = (Resolve-Path -LiteralPath $path).Path
    $errors = [System.Collections.Generic.List[string]]::new()
    $rawDocument = Get-Content -Raw -LiteralPath $resolvedBindingPath

    $schemaValid = $false
    try {
        $schemaValid = Test-Json -Json $rawDocument -SchemaFile $resolvedSchemaPath -ErrorAction SilentlyContinue
    }
    catch {
        Add-ValidationError -Errors $errors -Path '$' -Message "schema validation failed: $($_.Exception.Message)"
    }

    if (-not $schemaValid -and $errors.Count -eq 0) {
        Add-ValidationError -Errors $errors -Path '$' -Message 'document does not conform to the runtime-binding JSON Schema'
    }

    if ($schemaValid) {
        try {
            $document = $rawDocument | ConvertFrom-Json
            Test-RuntimeBindingSemantics -Document $document -Errors $errors
        }
        catch {
            Add-ValidationError -Errors $errors -Path '$' -Message "semantic validation could not complete: $($_.Exception.Message)"
        }
    }

    if ($errors.Count -eq 0) {
        Write-Output "PASS $resolvedBindingPath"
        continue
    }

    $hasFailures = $true
    Write-Output "FAIL $resolvedBindingPath"
    foreach ($validationError in $errors) {
        Write-Output "  - $validationError"
    }
}

if ($hasFailures) { exit 1 }
exit 0
