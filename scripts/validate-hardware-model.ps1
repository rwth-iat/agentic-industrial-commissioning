[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]] $ModelPath,

    [string] $SchemaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $repositoryRoot 'spec/hardware-model.schema.v0.2-proposal.json'
}

$resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path

function Get-PropertyValue {
    param(
        [AllowNull()]
        [object] $Object,
        [string] $Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Add-ValidationError {
    param(
        [System.Collections.Generic.List[string]] $Errors,
        [string] $Path,
        [string] $Message
    )

    $Errors.Add("${Path}: ${Message}")
}

function Test-ReferencedSourcesAndRanges {
    param(
        [AllowNull()]
        [object] $Node,
        [string] $Path,
        [System.Collections.Generic.HashSet[string]] $SourceIds,
        [System.Collections.Generic.List[string]] $Errors
    )

    if ($null -eq $Node -or $Node -is [string] -or $Node.GetType().IsValueType) {
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [System.Collections.IDictionary]) {
        $index = 0
        foreach ($item in $Node) {
            Test-ReferencedSourcesAndRanges -Node $item -Path "${Path}[${index}]" -SourceIds $SourceIds -Errors $Errors
            $index++
        }
        return
    }

    $minimum = Get-PropertyValue -Object $Node -Name 'min'
    $maximum = Get-PropertyValue -Object $Node -Name 'max'
    if ($null -ne $minimum -and $null -ne $maximum -and [double]$minimum -gt [double]$maximum) {
        Add-ValidationError -Errors $Errors -Path $Path -Message "range minimum ${minimum} exceeds maximum ${maximum}"
    }

    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -eq 'extensions') {
            continue
        }

        if ($property.Name -eq 'source_ref') {
            $sourceReference = [string]$property.Value
            if (-not $SourceIds.Contains($sourceReference)) {
                Add-ValidationError -Errors $Errors -Path "${Path}.source_ref" -Message "unknown source '${sourceReference}'"
            }
            continue
        }

        if ($property.Name -eq 'source_refs') {
            $index = 0
            foreach ($sourceReferenceValue in @($property.Value)) {
                $sourceReference = [string]$sourceReferenceValue
                if (-not $SourceIds.Contains($sourceReference)) {
                    Add-ValidationError -Errors $Errors -Path "${Path}.source_refs[${index}]" -Message "unknown source '${sourceReference}'"
                }
                $index++
            }
            continue
        }

        Test-ReferencedSourcesAndRanges -Node $property.Value -Path "${Path}.$($property.Name)" -SourceIds $SourceIds -Errors $Errors
    }
}

function Test-SemanticModel {
    param(
        [object] $Model,
        [System.Collections.Generic.List[string]] $Errors
    )

    $sourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $sources = @(@(Get-PropertyValue -Object $Model -Name 'sources') | Where-Object { $null -ne $_ })
    for ($sourceIndex = 0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
        $sourceId = [string](Get-PropertyValue -Object $sources[$sourceIndex] -Name 'id')
        if (-not $sourceIds.Add($sourceId)) {
            Add-ValidationError -Errors $Errors -Path "$.sources[${sourceIndex}].id" -Message "duplicate source ID '${sourceId}'"
        }
    }

    $assetsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $portsByAssetId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $assets = @(@(Get-PropertyValue -Object $Model -Name 'assets') | Where-Object { $null -ne $_ })

    for ($assetIndex = 0; $assetIndex -lt $assets.Count; $assetIndex++) {
        $asset = $assets[$assetIndex]
        $assetId = [string](Get-PropertyValue -Object $asset -Name 'id')
        if ($assetsById.ContainsKey($assetId)) {
            Add-ValidationError -Errors $Errors -Path "$.assets[${assetIndex}].id" -Message "duplicate asset ID '${assetId}'"
            continue
        }

        $assetsById.Add($assetId, $asset)
        $portsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $ports = @(@(Get-PropertyValue -Object $asset -Name 'ports') | Where-Object { $null -ne $_ })
        for ($portIndex = 0; $portIndex -lt $ports.Count; $portIndex++) {
            $port = $ports[$portIndex]
            $portId = [string](Get-PropertyValue -Object $port -Name 'id')
            if ($portsById.ContainsKey($portId)) {
                Add-ValidationError -Errors $Errors -Path "$.assets[${assetIndex}].ports[${portIndex}].id" -Message "duplicate port ID '${portId}' within asset '${assetId}'"
                continue
            }
            $portsById.Add($portId, $port)
        }
        $portsByAssetId.Add($assetId, $portsById)
    }

    foreach ($assetEntry in $assetsById.GetEnumerator()) {
        $assetId = $assetEntry.Key
        $parentAssetIdValue = Get-PropertyValue -Object $assetEntry.Value -Name 'parent_asset_id'
        if ($null -eq $parentAssetIdValue) {
            continue
        }

        $parentAssetId = [string]$parentAssetIdValue
        if (-not $assetsById.ContainsKey($parentAssetId)) {
            Add-ValidationError -Errors $Errors -Path "asset '${assetId}'.parent_asset_id" -Message "unknown parent asset '${parentAssetId}'"
            continue
        }

        $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $currentAssetId = $assetId
        while ($assetsById.ContainsKey($currentAssetId)) {
            if (-not $visited.Add($currentAssetId)) {
                Add-ValidationError -Errors $Errors -Path "asset '${assetId}'.parent_asset_id" -Message 'asset hierarchy contains a cycle'
                break
            }
            $nextParentValue = Get-PropertyValue -Object $assetsById[$currentAssetId] -Name 'parent_asset_id'
            if ($null -eq $nextParentValue) {
                break
            }
            $currentAssetId = [string]$nextParentValue
        }
    }

    $connectionIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $connections = @(@(Get-PropertyValue -Object $Model -Name 'physical_connections') | Where-Object { $null -ne $_ })
    for ($connectionIndex = 0; $connectionIndex -lt $connections.Count; $connectionIndex++) {
        $connection = $connections[$connectionIndex]
        $connectionPath = "$.physical_connections[${connectionIndex}]"
        $connectionId = [string](Get-PropertyValue -Object $connection -Name 'id')
        if (-not $connectionIds.Add($connectionId)) {
            Add-ValidationError -Errors $Errors -Path "${connectionPath}.id" -Message "duplicate connection ID '${connectionId}'"
        }

        $endpointKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $resolvedPorts = [System.Collections.Generic.List[object]]::new()
        $endpoints = @(@(Get-PropertyValue -Object $connection -Name 'endpoints') | Where-Object { $null -ne $_ })
        for ($endpointIndex = 0; $endpointIndex -lt $endpoints.Count; $endpointIndex++) {
            $endpoint = $endpoints[$endpointIndex]
            $endpointPath = "${connectionPath}.endpoints[${endpointIndex}]"
            $assetId = [string](Get-PropertyValue -Object $endpoint -Name 'asset_id')
            $portId = [string](Get-PropertyValue -Object $endpoint -Name 'port_id')
            $endpointKey = "${assetId}`0${portId}"
            if (-not $endpointKeys.Add($endpointKey)) {
                Add-ValidationError -Errors $Errors -Path $endpointPath -Message 'connection endpoints must be distinct'
            }

            if (-not $assetsById.ContainsKey($assetId)) {
                Add-ValidationError -Errors $Errors -Path "${endpointPath}.asset_id" -Message "unknown asset '${assetId}'"
                continue
            }

            $assetKind = Get-PropertyValue -Object $assetsById[$assetId] -Name 'asset_kind'
            if ($assetKind -eq 'type') {
                Add-ValidationError -Errors $Errors -Path "${endpointPath}.asset_id" -Message "type asset '${assetId}' cannot be an endpoint of a physical connection"
            }

            $portsById = $portsByAssetId[$assetId]
            if (-not $portsById.ContainsKey($portId)) {
                Add-ValidationError -Errors $Errors -Path "${endpointPath}.port_id" -Message "unknown port '${portId}' on asset '${assetId}'"
                continue
            }
            $resolvedPorts.Add($portsById[$portId])
        }

        $connectionKind = Get-PropertyValue -Object $connection -Name 'kind'
        if ($connectionKind -eq 'signal' -and $resolvedPorts.Count -eq 2) {
            $firstDirection = [string](Get-PropertyValue -Object $resolvedPorts[0] -Name 'direction')
            $secondDirection = [string](Get-PropertyValue -Object $resolvedPorts[1] -Name 'direction')
            $knownDirections = @('input', 'output')
            if ($knownDirections -contains $firstDirection -and $knownDirections -contains $secondDirection -and $firstDirection -eq $secondDirection) {
                Add-ValidationError -Errors $Errors -Path "${connectionPath}.endpoints" -Message "signal connection joins two '${firstDirection}' ports"
            }
        }
    }

    Test-ReferencedSourcesAndRanges -Node $Model -Path '$' -SourceIds $sourceIds -Errors $Errors
}

$hasFailures = $false
foreach ($path in $ModelPath) {
    $resolvedModelPath = (Resolve-Path -LiteralPath $path).Path
    $errors = [System.Collections.Generic.List[string]]::new()
    $rawModel = Get-Content -Raw -LiteralPath $resolvedModelPath

    $schemaValid = $false
    try {
        $schemaValid = Test-Json -Json $rawModel -SchemaFile $resolvedSchemaPath -ErrorAction SilentlyContinue
    }
    catch {
        Add-ValidationError -Errors $errors -Path '$' -Message "schema validation failed: $($_.Exception.Message)"
    }

    if (-not $schemaValid -and $errors.Count -eq 0) {
        Add-ValidationError -Errors $errors -Path '$' -Message 'document does not conform to the JSON Schema'
    }

    if ($schemaValid) {
        try {
            $model = $rawModel | ConvertFrom-Json
            Test-SemanticModel -Model $model -Errors $errors
        }
        catch {
            Add-ValidationError -Errors $errors -Path '$' -Message "semantic validation could not complete: $($_.Exception.Message)"
        }
    }

    if ($errors.Count -eq 0) {
        Write-Output "PASS $resolvedModelPath"
        continue
    }

    $hasFailures = $true
    Write-Output "FAIL $resolvedModelPath"
    foreach ($validationError in $errors) {
        Write-Output "  - $validationError"
    }
}

if ($hasFailures) {
    exit 1
}

exit 0
