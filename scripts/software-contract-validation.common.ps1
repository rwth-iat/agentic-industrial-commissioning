Set-StrictMode -Version Latest

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

function Get-Items {
    param(
        [AllowNull()]
        [object]$Value
    )

    $items = @(@($Value) | Where-Object { $null -ne $_ })
    Write-Output -NoEnumerate $items
}

function Add-ContractError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Path,
        [string]$Message
    )

    $Errors.Add("${Path}: ${Message}")
}

function Add-UniqueId {
    param(
        [System.Collections.Generic.HashSet[string]]$Ids,
        [string]$Id,
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Path
    )

    if (-not $Ids.Add($Id)) {
        Add-ContractError -Errors $Errors -Path $Path -Message "duplicate ID '${Id}'"
    }
}

function Get-SourceTypeMap {
    param(
        [object]$Document,
        [System.Collections.Generic.List[string]]$Errors
    )

    $sourceTypes = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $sources = Get-Items (Get-PropertyValue $Document 'sources')
    for ($sourceIndex = 0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
        $sourceId = [string](Get-PropertyValue $sources[$sourceIndex] 'id')
        if ($sourceTypes.ContainsKey($sourceId)) {
            Add-ContractError -Errors $Errors -Path "$.sources[${sourceIndex}].id" -Message "duplicate source ID '${sourceId}'"
            continue
        }
        $sourceTypes.Add($sourceId, [string](Get-PropertyValue $sources[$sourceIndex] 'type'))
    }
    return ,$sourceTypes
}

function Test-EvidenceList {
    param(
        [object]$Claim,
        [string]$Path,
        [System.Collections.Generic.Dictionary[string, string]]$SourceTypes,
        [System.Collections.Generic.List[string]]$Errors,
        [switch]$CheckStatus
    )

    $evidence = Get-Items (Get-PropertyValue $Claim 'evidence')
    $evidenceSourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    for ($evidenceIndex = 0; $evidenceIndex -lt $evidence.Count; $evidenceIndex++) {
        $sourceRef = [string](Get-PropertyValue $evidence[$evidenceIndex] 'source_ref')
        if (-not $SourceTypes.ContainsKey($sourceRef)) {
            Add-ContractError -Errors $Errors -Path "${Path}.evidence[${evidenceIndex}].source_ref" -Message "unknown source '${sourceRef}'"
            continue
        }
        $null = $evidenceSourceIds.Add($sourceRef)
    }

    if (-not $CheckStatus) { return }

    $status = [string](Get-PropertyValue $Claim 'status')
    if ($status -eq 'validated') {
        $hasRuntimeObservation = $false
        foreach ($sourceId in $evidenceSourceIds) {
            if ($SourceTypes[$sourceId] -eq 'runtime_observation') {
                $hasRuntimeObservation = $true
                break
            }
        }
        if (-not $hasRuntimeObservation) {
            Add-ContractError -Errors $Errors -Path "${Path}.status" -Message "validated claims require runtime_observation evidence"
        }
    }

    if ($status -eq 'corroborated' -and $evidenceSourceIds.Count -lt 2) {
        Add-ContractError -Errors $Errors -Path "${Path}.status" -Message 'corroborated claims require evidence from at least two distinct sources'
    }

    if ($status -in @('rejected', 'stale', 'unresolved')) {
        $rationale = Get-PropertyValue $Claim 'rationale'
        if ($null -eq $rationale -or [string]::IsNullOrWhiteSpace([string]$rationale)) {
            Add-ContractError -Errors $Errors -Path "${Path}.rationale" -Message "status '${status}' requires a rationale"
        }
    }
}

function Test-PrivatePlacement {
    param(
        [string]$ResolvedPath,
        [string]$DataClassification,
        [object]$Sources,
        [System.Collections.Generic.List[string]]$Errors
    )

    $normalizedPath = $ResolvedPath.Replace('\', '/')
    $isCasePath = $normalizedPath -match '/cases/[^/]+/'
    $isPrivateCasePath = $normalizedPath -match '/cases/[^/]+/(derived|results|validation)/private/'

    if ($isCasePath -and -not $isPrivateCasePath) {
        Add-ContractError -Errors $Errors -Path '$.data_classification' -Message 'contract documents inside cases must be stored below derived/private, results/private, or validation/private'
    }
    if ($DataClassification -eq 'private' -and -not $isPrivateCasePath) {
        Add-ContractError -Errors $Errors -Path '$.data_classification' -Message 'private documents must be stored in an ignored private case artifact directory'
    }
    if ($DataClassification -eq 'public_example' -and $isCasePath) {
        Add-ContractError -Errors $Errors -Path '$.data_classification' -Message 'public examples must not be stored inside a concrete case'
    }

    if ($DataClassification -eq 'public_example') {
        $sourceItems = Get-Items $Sources
        for ($sourceIndex = 0; $sourceIndex -lt $sourceItems.Count; $sourceIndex++) {
            $locator = Get-PropertyValue $sourceItems[$sourceIndex] 'locator'
            if ($null -ne $locator -and ([string]$locator).Replace('\', '/') -match '(^|/)cases/|(^|/)raw/') {
                Add-ContractError -Errors $Errors -Path "$.sources[${sourceIndex}].locator" -Message 'public examples must not reference case raw evidence'
            }
        }
    }
}

function Test-NumericRange {
    param(
        [AllowNull()]
        [object]$Range,
        [string]$Path,
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($null -eq $Range) { return }
    $minimum = Get-PropertyValue $Range 'minimum'
    $maximum = Get-PropertyValue $Range 'maximum'
    if ($null -ne $minimum -and $null -ne $maximum -and [double]$minimum -gt [double]$maximum) {
        Add-ContractError -Errors $Errors -Path $Path -Message 'minimum must not exceed maximum'
    }
}

function Test-ConditionReferences {
    param(
        [AllowNull()]
        [object]$Condition,
        [string]$Path,
        [System.Collections.Generic.HashSet[string]]$ObjectIds,
        [System.Collections.Generic.HashSet[string]]$SignalIds,
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($null -eq $Condition) { return }
    $kind = [string](Get-PropertyValue $Condition 'kind')
    if ($kind -eq 'predicate') {
        $subjectKind = [string](Get-PropertyValue $Condition 'subject_kind')
        $subjectRef = [string](Get-PropertyValue $Condition 'subject_ref')
        if ($subjectKind -eq 'software_object' -and -not $ObjectIds.Contains($subjectRef)) {
            Add-ContractError -Errors $Errors -Path "${Path}.subject_ref" -Message "unknown software object '${subjectRef}'"
        }
        if ($subjectKind -eq 'signal' -and -not $SignalIds.Contains($subjectRef)) {
            Add-ContractError -Errors $Errors -Path "${Path}.subject_ref" -Message "unknown signal '${subjectRef}'"
        }
        return
    }
    if ($kind -in @('all_of', 'any_of')) {
        $children = Get-Items (Get-PropertyValue $Condition 'conditions')
        for ($childIndex = 0; $childIndex -lt $children.Count; $childIndex++) {
            Test-ConditionReferences -Condition $children[$childIndex] -Path "${Path}.conditions[${childIndex}]" -ObjectIds $ObjectIds -SignalIds $SignalIds -Errors $Errors
        }
        return
    }
    if ($kind -eq 'not') {
        Test-ConditionReferences -Condition (Get-PropertyValue $Condition 'condition') -Path "${Path}.condition" -ObjectIds $ObjectIds -SignalIds $SignalIds -Errors $Errors
    }
}
