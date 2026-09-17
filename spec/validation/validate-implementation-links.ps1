[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$LinkPath,

    [Parameter(Mandatory = $true)]
    [string]$SoftwareModelPath,

    [Parameter(Mandatory = $true)]
    [string]$HardwareModelPath,

    [string]$SchemaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repositoryRoot 'scripts/json-schema-validation.common.ps1')
. (Join-Path $repositoryRoot 'scripts/software-contract-validation.common.ps1')
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $repositoryRoot 'spec/implementation-link.schema.json'
}
$resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path
$resolvedSoftwarePath = (Resolve-Path -LiteralPath $SoftwareModelPath).Path
$resolvedHardwarePath = (Resolve-Path -LiteralPath $HardwareModelPath).Path
$softwareModel = Get-Content -Raw -LiteralPath $resolvedSoftwarePath | ConvertFrom-Json
$hardwareModel = Get-Content -Raw -LiteralPath $resolvedHardwarePath | ConvertFrom-Json

function Test-ImplementationLinkSemantics {
    param(
        [object]$Document,
        [string]$ResolvedDocumentPath,
        [System.Collections.Generic.List[string]]$Errors
    )

    $sourceTypes = Get-SourceTypeMap -Document $Document -Errors $Errors
    Test-PrivatePlacement -ResolvedPath $ResolvedDocumentPath `
        -DataClassification ([string](Get-PropertyValue $Document 'data_classification')) `
        -Sources (Get-PropertyValue $Document 'sources') -Errors $Errors

    $documentSystemId = [string](Get-PropertyValue $Document 'system_id')
    $hardwareRef = Get-PropertyValue $Document 'hardware_model'
    $softwareRef = Get-PropertyValue $Document 'software_model'
    $hardwareSystem = Get-PropertyValue $hardwareModel 'system'
    $hardwareSystemId = [string](Get-PropertyValue $hardwareSystem 'id')
    $softwareSystemId = [string](Get-PropertyValue $softwareModel 'system_id')

    if ($documentSystemId -ne $hardwareSystemId) {
        Add-ContractError -Errors $Errors -Path '$.system_id' -Message "does not match hardware system '${hardwareSystemId}'"
    }
    if ($documentSystemId -ne $softwareSystemId) {
        Add-ContractError -Errors $Errors -Path '$.system_id' -Message "does not match software system '${softwareSystemId}'"
    }
    if ([string](Get-PropertyValue $hardwareRef 'system_id') -ne $hardwareSystemId) {
        Add-ContractError -Errors $Errors -Path '$.hardware_model.system_id' -Message "does not match supplied hardware model '${hardwareSystemId}'"
    }
    if ([string](Get-PropertyValue $hardwareRef 'schema_version') -ne [string](Get-PropertyValue $hardwareModel 'schema_version')) {
        Add-ContractError -Errors $Errors -Path '$.hardware_model.schema_version' -Message 'does not match supplied hardware model schema version'
    }
    if ([string](Get-PropertyValue $softwareRef 'id') -ne [string](Get-PropertyValue $softwareModel 'id')) {
        Add-ContractError -Errors $Errors -Path '$.software_model.id' -Message 'does not match supplied software model ID'
    }
    if ([string](Get-PropertyValue $softwareRef 'system_id') -ne $softwareSystemId) {
        Add-ContractError -Errors $Errors -Path '$.software_model.system_id' -Message 'does not match supplied software model system'
    }
    if ([string](Get-PropertyValue $softwareRef 'schema_version') -ne [string](Get-PropertyValue $softwareModel 'schema_version')) {
        Add-ContractError -Errors $Errors -Path '$.software_model.schema_version' -Message 'does not match supplied software model schema version'
    }

    $classification = [string](Get-PropertyValue $Document 'data_classification')
    if ($classification -eq 'public_example') {
        if ([string](Get-PropertyValue $softwareModel 'data_classification') -ne 'public_example') {
            Add-ContractError -Errors $Errors -Path '$.software_model' -Message 'public links may only reference a public-example software model'
        }
        foreach ($reference in @($hardwareRef, $softwareRef)) {
            $modelRef = [string](Get-PropertyValue $reference 'model_ref')
            if ($modelRef.Replace('\', '/') -match '(^|/)cases/|(^|/)raw/') {
                Add-ContractError -Errors $Errors -Path '$.data_classification' -Message 'public links must not reference case raw evidence or private case models'
            }
        }
    }

    $hasHardwareModelSource = $false
    $hasSoftwareModelSource = $false
    foreach ($source in (Get-Items (Get-PropertyValue $Document 'sources'))) {
        $sourceType = [string](Get-PropertyValue $source 'type')
        $sourceLocator = [string](Get-PropertyValue $source 'locator')
        if ($sourceType -eq 'hardware_model' -and $sourceLocator -eq [string](Get-PropertyValue $hardwareRef 'model_ref')) {
            $hasHardwareModelSource = $true
        }
        if ($sourceType -eq 'software_model' -and $sourceLocator -eq [string](Get-PropertyValue $softwareRef 'model_ref')) {
            $hasSoftwareModelSource = $true
        }
    }
    if (-not $hasHardwareModelSource) {
        Add-ContractError -Errors $Errors -Path '$.hardware_model.model_ref' -Message 'must have a matching revisioned hardware_model source'
    }
    if (-not $hasSoftwareModelSource) {
        Add-ContractError -Errors $Errors -Path '$.software_model.model_ref' -Message 'must have a matching revisioned software_model source'
    }

    $assetsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $portsByAsset = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $assets = Get-Items (Get-PropertyValue $hardwareModel 'assets')
    foreach ($asset in $assets) {
        $assetId = [string](Get-PropertyValue $asset 'id')
        if (-not $assetsById.ContainsKey($assetId)) { $assetsById.Add($assetId, $asset) }
        $ports = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($port in (Get-Items (Get-PropertyValue $asset 'ports'))) {
            $portId = [string](Get-PropertyValue $port 'id')
            if (-not $ports.ContainsKey($portId)) { $ports.Add($portId, $port) }
        }
        $portsByAsset.Add($assetId, $ports)
    }

    $interfacesById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $signalsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $signalOwnerById = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($interface in (Get-Items (Get-PropertyValue $softwareModel 'component_interfaces'))) {
        $interfaceId = [string](Get-PropertyValue $interface 'id')
        if (-not $interfacesById.ContainsKey($interfaceId)) { $interfacesById.Add($interfaceId, $interface) }
        foreach ($signal in (Get-Items (Get-PropertyValue $interface 'signals'))) {
            $signalId = [string](Get-PropertyValue $signal 'id')
            if (-not $signalsById.ContainsKey($signalId)) {
                $signalsById.Add($signalId, $signal)
                $signalOwnerById.Add($signalId, $interfaceId)
            }
        }
    }

    $linkIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $links = Get-Items (Get-PropertyValue $Document 'links')
    for ($linkIndex = 0; $linkIndex -lt $links.Count; $linkIndex++) {
        $link = $links[$linkIndex]
        $linkPath = "$.links[${linkIndex}]"
        Add-UniqueId -Ids $linkIds -Id ([string](Get-PropertyValue $link 'id')) -Errors $Errors -Path "${linkPath}.id"
        Test-EvidenceList -Claim $link -Path $linkPath -SourceTypes $sourceTypes -Errors $Errors -CheckStatus

        $hardware = Get-PropertyValue $link 'hardware'
        $componentAssetId = [string](Get-PropertyValue $hardware 'component_asset_id')
        if (-not $assetsById.ContainsKey($componentAssetId)) {
            Add-ContractError -Errors $Errors -Path "${linkPath}.hardware.component_asset_id" -Message "unknown canonical asset '${componentAssetId}'"
        }

        $software = Get-PropertyValue $link 'software'
        $interfaceId = [string](Get-PropertyValue $software 'component_interface_id')
        $signalId = [string](Get-PropertyValue $software 'signal_id')
        if (-not $interfacesById.ContainsKey($interfaceId)) {
            Add-ContractError -Errors $Errors -Path "${linkPath}.software.component_interface_id" -Message "unknown component interface '${interfaceId}'"
        }
        else {
            $interfaceAssetId = [string](Get-PropertyValue $interfacesById[$interfaceId] 'asset_id')
            if ($interfaceAssetId -ne $componentAssetId) {
                Add-ContractError -Errors $Errors -Path "${linkPath}.hardware.component_asset_id" -Message "asset '${componentAssetId}' does not own component interface '${interfaceId}'"
            }
        }
        if (-not $signalsById.ContainsKey($signalId)) {
            Add-ContractError -Errors $Errors -Path "${linkPath}.software.signal_id" -Message "unknown signal '${signalId}'"
        }
        elseif ($signalOwnerById[$signalId] -ne $interfaceId) {
            Add-ContractError -Errors $Errors -Path "${linkPath}.software.signal_id" -Message "signal '${signalId}' does not belong to component interface '${interfaceId}'"
        }

        $endpoint = Get-PropertyValue $hardware 'endpoint'
        if ($null -ne $endpoint) {
            $endpointAssetId = [string](Get-PropertyValue $endpoint 'asset_id')
            $portId = [string](Get-PropertyValue $endpoint 'port_id')
            if (-not $assetsById.ContainsKey($endpointAssetId)) {
                Add-ContractError -Errors $Errors -Path "${linkPath}.hardware.endpoint.asset_id" -Message "unknown endpoint asset '${endpointAssetId}'"
            }
            elseif (-not $portsByAsset[$endpointAssetId].ContainsKey($portId)) {
                Add-ContractError -Errors $Errors -Path "${linkPath}.hardware.endpoint.port_id" -Message "port '${portId}' does not belong to asset '${endpointAssetId}'"
            }
            elseif ($signalsById.ContainsKey($signalId) -and [string](Get-PropertyValue $link 'kind') -eq 'io_signal') {
                $portDirection = [string](Get-PropertyValue $portsByAsset[$endpointAssetId][$portId] 'direction')
                $signalDirection = [string](Get-PropertyValue $signalsById[$signalId] 'flow_direction')
                $endpointIsComponent = $endpointAssetId -eq $componentAssetId
                $expectedFromDirection = if ($endpointIsComponent) { 'output' } else { 'input' }
                $expectedToDirection = if ($endpointIsComponent) { 'input' } else { 'output' }
                if ($signalDirection -eq 'from_component' -and $portDirection -notin @($expectedFromDirection, 'bidirectional')) {
                    Add-ContractError -Errors $Errors -Path "${linkPath}.hardware.endpoint.port_id" -Message "from_component signal is incompatible with '${portDirection}' endpoint direction"
                }
                if ($signalDirection -eq 'to_component' -and $portDirection -notin @($expectedToDirection, 'bidirectional')) {
                    Add-ContractError -Errors $Errors -Path "${linkPath}.hardware.endpoint.port_id" -Message "to_component signal is incompatible with '${portDirection}' endpoint direction"
                }
                if ($signalDirection -eq 'bidirectional' -and $portDirection -ne 'bidirectional') {
                    Add-ContractError -Errors $Errors -Path "${linkPath}.hardware.endpoint.port_id" -Message 'bidirectional signal requires a bidirectional hardware port'
                }
            }
        }
    }

    $gapIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $gaps = Get-Items (Get-PropertyValue $Document 'gaps')
    for ($gapIndex = 0; $gapIndex -lt $gaps.Count; $gapIndex++) {
        $gap = $gaps[$gapIndex]
        $gapPath = "$.gaps[${gapIndex}]"
        Add-UniqueId -Ids $gapIds -Id ([string](Get-PropertyValue $gap 'id')) -Errors $Errors -Path "${gapPath}.id"
        Test-EvidenceList -Claim $gap -Path $gapPath -SourceTypes $sourceTypes -Errors $Errors
        $assetId = Get-PropertyValue $gap 'asset_id'
        if ($null -ne $assetId -and -not $assetsById.ContainsKey([string]$assetId)) {
            Add-ContractError -Errors $Errors -Path "${gapPath}.asset_id" -Message "unknown canonical asset '${assetId}'"
        }
        $signalId = Get-PropertyValue $gap 'signal_id'
        if ($null -ne $signalId -and -not $signalsById.ContainsKey([string]$signalId)) {
            Add-ContractError -Errors $Errors -Path "${gapPath}.signal_id" -Message "unknown software signal '${signalId}'"
        }
    }
}

$hasFailures = $false
foreach ($path in $LinkPath) {
    $resolvedLinkPath = (Resolve-Path -LiteralPath $path).Path
    $errors = [System.Collections.Generic.List[string]]::new()
    $rawDocument = Get-Content -Raw -LiteralPath $resolvedLinkPath
    $schemaResult = Test-JsonSchemaFile -DocumentPath $resolvedLinkPath -SchemaPath $resolvedSchemaPath
    $schemaValid = $schemaResult.Valid
    if (-not $schemaValid) {
        Add-ContractError -Errors $errors -Path '$' -Message "schema validation failed using $($schemaResult.Engine): $($schemaResult.Error)"
    }
    if (-not $schemaValid -and $errors.Count -eq 0) {
        Add-ContractError -Errors $errors -Path '$' -Message 'document does not conform to the JSON Schema'
    }
    if ($schemaValid) {
        try {
            Test-ImplementationLinkSemantics -Document ($rawDocument | ConvertFrom-Json) -ResolvedDocumentPath $resolvedLinkPath -Errors $errors
        }
        catch {
            Add-ContractError -Errors $errors -Path '$' -Message "semantic validation could not complete: $($_.Exception.Message)"
        }
    }
    if ($errors.Count -eq 0) {
        Write-Output "PASS $resolvedLinkPath"
    }
    else {
        $hasFailures = $true
        Write-Output "FAIL $resolvedLinkPath"
        foreach ($validationError in $errors) { Write-Output "  - $validationError" }
    }
}

if ($hasFailures) { exit 1 }
exit 0
