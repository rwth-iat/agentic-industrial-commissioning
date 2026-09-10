[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ModelPath,

    [string]$SchemaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'json-schema-validation.common.ps1')
. (Join-Path $PSScriptRoot 'software-contract-validation.common.ps1')

if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $repositoryRoot 'spec/software-model.schema.json'
}
$resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path

function Test-SoftwareModelSemantics {
    param(
        [object]$Model,
        [string]$ResolvedModelPath,
        [System.Collections.Generic.List[string]]$Errors
    )

    $sourceTypes = Get-SourceTypeMap -Document $Model -Errors $Errors
    Test-PrivatePlacement -ResolvedPath $ResolvedModelPath `
        -DataClassification ([string](Get-PropertyValue $Model 'data_classification')) `
        -Sources (Get-PropertyValue $Model 'sources') -Errors $Errors

    $allIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $objectIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $signalIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $interfaceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $interfaceAssetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $objectsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)

    $objects = Get-Items (Get-PropertyValue $Model 'software_objects')
    for ($objectIndex = 0; $objectIndex -lt $objects.Count; $objectIndex++) {
        $object = $objects[$objectIndex]
        $objectId = [string](Get-PropertyValue $object 'id')
        Add-UniqueId -Ids $allIds -Id $objectId -Errors $Errors -Path "$.software_objects[${objectIndex}].id"
        $null = $objectIds.Add($objectId)
        if (-not $objectsById.ContainsKey($objectId)) { $objectsById.Add($objectId, $object) }
        Test-EvidenceList -Claim $object -Path "$.software_objects[${objectIndex}]" -SourceTypes $sourceTypes -Errors $Errors -CheckStatus
    }

    $interfaces = Get-Items (Get-PropertyValue $Model 'component_interfaces')
    for ($interfaceIndex = 0; $interfaceIndex -lt $interfaces.Count; $interfaceIndex++) {
        $interface = $interfaces[$interfaceIndex]
        $interfacePath = "$.component_interfaces[${interfaceIndex}]"
        $interfaceId = [string](Get-PropertyValue $interface 'id')
        $assetId = [string](Get-PropertyValue $interface 'asset_id')
        Add-UniqueId -Ids $allIds -Id $interfaceId -Errors $Errors -Path "${interfacePath}.id"
        $null = $interfaceIds.Add($interfaceId)
        if (-not $interfaceAssetIds.Add($assetId)) {
            Add-ContractError -Errors $Errors -Path "${interfacePath}.asset_id" -Message "duplicate component interface for asset '${assetId}'"
        }
        Test-EvidenceList -Claim ([pscustomobject]@{ evidence = Get-PropertyValue $interface 'inventory_evidence' }) -Path "${interfacePath}.inventory_evidence" -SourceTypes $sourceTypes -Errors $Errors

        $signals = Get-Items (Get-PropertyValue $interface 'signals')
        $coverageStatus = [string](Get-PropertyValue $interface 'coverage_status')
        if ($coverageStatus -eq 'reconstructed' -and $signals.Count -eq 0) {
            Add-ContractError -Errors $Errors -Path "${interfacePath}.coverage_status" -Message 'reconstructed interfaces require at least one signal'
        }
        if ($coverageStatus -eq 'unresolved' -and $signals.Count -ne 0) {
            Add-ContractError -Errors $Errors -Path "${interfacePath}.coverage_status" -Message 'interfaces with discovered signals must be partial or ambiguous rather than unresolved'
        }

        for ($signalIndex = 0; $signalIndex -lt $signals.Count; $signalIndex++) {
            $signal = $signals[$signalIndex]
            $signalPath = "${interfacePath}.signals[${signalIndex}]"
            $signalId = [string](Get-PropertyValue $signal 'id')
            Add-UniqueId -Ids $allIds -Id $signalId -Errors $Errors -Path "${signalPath}.id"
            $null = $signalIds.Add($signalId)
            Test-EvidenceList -Claim $signal -Path $signalPath -SourceTypes $sourceTypes -Errors $Errors -CheckStatus
            Test-NumericRange -Range (Get-PropertyValue $signal 'engineering_range') -Path "${signalPath}.engineering_range" -Errors $Errors
        }

        $dependencies = Get-Items (Get-PropertyValue $interface 'dependencies')
        for ($dependencyIndex = 0; $dependencyIndex -lt $dependencies.Count; $dependencyIndex++) {
            $dependency = $dependencies[$dependencyIndex]
            $dependencyPath = "${interfacePath}.dependencies[${dependencyIndex}]"
            Add-UniqueId -Ids $allIds -Id ([string](Get-PropertyValue $dependency 'id')) -Errors $Errors -Path "${dependencyPath}.id"
            Test-EvidenceList -Claim $dependency -Path $dependencyPath -SourceTypes $sourceTypes -Errors $Errors -CheckStatus
        }
    }

    for ($objectIndex = 0; $objectIndex -lt $objects.Count; $objectIndex++) {
        $parentRef = Get-PropertyValue $objects[$objectIndex] 'parent_ref'
        if ($null -ne $parentRef -and -not $objectIds.Contains([string]$parentRef)) {
            Add-ContractError -Errors $Errors -Path "$.software_objects[${objectIndex}].parent_ref" -Message "unknown software object '${parentRef}'"
        }
    }

    foreach ($objectId in $objectIds) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $currentId = $objectId
        while ($objectsById.ContainsKey($currentId)) {
            if (-not $seen.Add($currentId)) {
                Add-ContractError -Errors $Errors -Path "software object '${objectId}'.parent_ref" -Message 'software object hierarchy contains a cycle'
                break
            }
            $parentRef = Get-PropertyValue $objectsById[$currentId] 'parent_ref'
            if ($null -eq $parentRef) { break }
            $currentId = [string]$parentRef
        }
    }

    $relations = Get-Items (Get-PropertyValue $Model 'relations')
    for ($relationIndex = 0; $relationIndex -lt $relations.Count; $relationIndex++) {
        $relation = $relations[$relationIndex]
        $relationPath = "$.relations[${relationIndex}]"
        Add-UniqueId -Ids $allIds -Id ([string](Get-PropertyValue $relation 'id')) -Errors $Errors -Path "${relationPath}.id"
        foreach ($field in @('from_ref', 'to_ref')) {
            $reference = [string](Get-PropertyValue $relation $field)
            if (-not $objectIds.Contains($reference)) {
                Add-ContractError -Errors $Errors -Path "${relationPath}.${field}" -Message "unknown software object '${reference}'"
            }
        }
        Test-EvidenceList -Claim $relation -Path $relationPath -SourceTypes $sourceTypes -Errors $Errors -CheckStatus
    }

    for ($interfaceIndex = 0; $interfaceIndex -lt $interfaces.Count; $interfaceIndex++) {
        $interface = $interfaces[$interfaceIndex]
        $interfacePath = "$.component_interfaces[${interfaceIndex}]"
        $signals = Get-Items (Get-PropertyValue $interface 'signals')
        for ($signalIndex = 0; $signalIndex -lt $signals.Count; $signalIndex++) {
            $signal = $signals[$signalIndex]
            $signalPath = "${interfacePath}.signals[${signalIndex}]"
            $objectRef = [string](Get-PropertyValue $signal 'software_object_ref')
            if (-not $objectIds.Contains($objectRef)) {
                Add-ContractError -Errors $Errors -Path "${signalPath}.software_object_ref" -Message "unknown software object '${objectRef}'"
            }
            Test-ConditionReferences -Condition (Get-PropertyValue $signal 'availability') -Path "${signalPath}.availability" -ObjectIds $objectIds -SignalIds $signalIds -Errors $Errors
            $effect = Get-PropertyValue $signal 'expected_effect'
            if ($null -ne $effect) {
                $targetRef = [string](Get-PropertyValue $effect 'target_signal_ref')
                if (-not $signalIds.Contains($targetRef)) {
                    Add-ContractError -Errors $Errors -Path "${signalPath}.expected_effect.target_signal_ref" -Message "unknown signal '${targetRef}'"
                }
                $expected = Get-PropertyValue $effect 'expected'
                $relativeRef = Get-PropertyValue $expected 'reference_signal_ref'
                $effectKind = [string](Get-PropertyValue $effect 'kind')
                $effectOperator = [string](Get-PropertyValue $effect 'operator')
                if ($effectKind -eq 'setpoint_relative' -and $null -eq $relativeRef) {
                    Add-ContractError -Errors $Errors -Path "${signalPath}.expected_effect.expected" -Message 'setpoint_relative effects require a reference_signal_ref, scale, and offset'
                }
                if ($effectKind -eq 'range' -and $effectOperator -ne 'within') {
                    Add-ContractError -Errors $Errors -Path "${signalPath}.expected_effect.operator" -Message "range effects require operator 'within'"
                }
                if ($null -ne $relativeRef -and -not $signalIds.Contains([string]$relativeRef)) {
                    Add-ContractError -Errors $Errors -Path "${signalPath}.expected_effect.expected.reference_signal_ref" -Message "unknown signal '${relativeRef}'"
                }
                Test-NumericRange -Range $expected -Path "${signalPath}.expected_effect.expected" -Errors $Errors
            }
        }
        $dependencies = Get-Items (Get-PropertyValue $interface 'dependencies')
        for ($dependencyIndex = 0; $dependencyIndex -lt $dependencies.Count; $dependencyIndex++) {
            Test-ConditionReferences -Condition (Get-PropertyValue $dependencies[$dependencyIndex] 'condition') -Path "${interfacePath}.dependencies[${dependencyIndex}].condition" -ObjectIds $objectIds -SignalIds $signalIds -Errors $Errors
        }
    }

    for ($relationIndex = 0; $relationIndex -lt $relations.Count; $relationIndex++) {
        Test-ConditionReferences -Condition (Get-PropertyValue $relations[$relationIndex] 'condition') -Path "$.relations[${relationIndex}].condition" -ObjectIds $objectIds -SignalIds $signalIds -Errors $Errors
    }

    $scope = Get-PropertyValue $Model 'scope'
    if ([bool](Get-PropertyValue $scope 'inventory_complete') -and (Get-Items (Get-PropertyValue $scope 'unexamined_sources')).Count -ne 0) {
        Add-ContractError -Errors $Errors -Path '$.scope.inventory_complete' -Message 'inventory cannot be complete while sources remain unexamined'
    }
    $focusIds = Get-Items (Get-PropertyValue $scope 'focus_asset_ids')
    for ($focusIndex = 0; $focusIndex -lt $focusIds.Count; $focusIndex++) {
        if (-not $interfaceAssetIds.Contains([string]$focusIds[$focusIndex])) {
            Add-ContractError -Errors $Errors -Path "$.scope.focus_asset_ids[${focusIndex}]" -Message "focused asset '$($focusIds[$focusIndex])' has no component interface coverage record"
        }
    }

    $gaps = Get-Items (Get-PropertyValue $Model 'gaps')
    for ($gapIndex = 0; $gapIndex -lt $gaps.Count; $gapIndex++) {
        $gap = $gaps[$gapIndex]
        $gapPath = "$.gaps[${gapIndex}]"
        Add-UniqueId -Ids $allIds -Id ([string](Get-PropertyValue $gap 'id')) -Errors $Errors -Path "${gapPath}.id"
        Test-EvidenceList -Claim $gap -Path $gapPath -SourceTypes $sourceTypes -Errors $Errors
        $scopeRef = Get-PropertyValue $gap 'scope_ref'
        if ($null -ne $scopeRef -and -not $allIds.Contains([string]$scopeRef)) {
            Add-ContractError -Errors $Errors -Path "${gapPath}.scope_ref" -Message "unknown scope reference '${scopeRef}'"
        }
    }
}

$hasFailures = $false
foreach ($path in $ModelPath) {
    $resolvedModelPath = (Resolve-Path -LiteralPath $path).Path
    $errors = [System.Collections.Generic.List[string]]::new()
    $rawModel = Get-Content -Raw -LiteralPath $resolvedModelPath
    $schemaResult = Test-JsonSchemaFile -DocumentPath $resolvedModelPath -SchemaPath $resolvedSchemaPath
    $schemaValid = $schemaResult.Valid
    if (-not $schemaValid) {
        Add-ContractError -Errors $errors -Path '$' -Message "schema validation failed using $($schemaResult.Engine): $($schemaResult.Error)"
    }
    if (-not $schemaValid -and $errors.Count -eq 0) {
        Add-ContractError -Errors $errors -Path '$' -Message 'document does not conform to the JSON Schema'
    }
    if ($schemaValid) {
        try {
            Test-SoftwareModelSemantics -Model ($rawModel | ConvertFrom-Json) -ResolvedModelPath $resolvedModelPath -Errors $errors
        }
        catch {
            Add-ContractError -Errors $errors -Path '$' -Message "semantic validation could not complete: $($_.Exception.Message)"
        }
    }
    if ($errors.Count -eq 0) {
        Write-Output "PASS $resolvedModelPath"
    }
    else {
        $hasFailures = $true
        Write-Output "FAIL $resolvedModelPath"
        foreach ($validationError in $errors) { Write-Output "  - $validationError" }
    }
}

if ($hasFailures) { exit 1 }
exit 0
