Set-StrictMode -Version Latest

$script:AicRepositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

function Get-AicPropertyValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        return $Object[$Name]
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-AicRepositoryRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    # Probe evidence is referenced before its first write. Resolve existing
    # paths for canonicalization, but permit a normalized future file path.
    if (Test-Path -LiteralPath $Path) {
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
    }
    else {
        $resolved = [IO.Path]::GetFullPath($Path)
    }
    $prefix = $script:AicRepositoryRoot
    if (-not $prefix.EndsWith([string][IO.Path]::DirectorySeparatorChar)) {
        $prefix += [IO.Path]::DirectorySeparatorChar
    }
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be inside the repository: $resolved"
    }
    return $resolved.Substring($prefix.Length).Replace('\', '/')
}

function Get-AicFileRevision {
    param([Parameter(Mandatory)][string]$Path)

    return "sha256:$((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant())"
}

function ConvertTo-AicPowerShellType {
    param([Parameter(Mandatory)][string]$RuntimeType)

    switch ($RuntimeType.ToUpperInvariant()) {
        'BOOL' { return 'Boolean' }
        'BOOLEAN' { return 'Boolean' }
        'USINT' { return 'Byte' }
        'BYTE' { return 'Byte' }
        'INT' { return 'Int16' }
        'INT16' { return 'Int16' }
        'UINT' { return 'UInt16' }
        'UINT16' { return 'UInt16' }
        'DINT' { return 'Int32' }
        'INT32' { return 'Int32' }
        'UDINT' { return 'UInt32' }
        'UINT32' { return 'UInt32' }
        'REAL' { return 'Single' }
        'SINGLE' { return 'Single' }
        'LREAL' { return 'Double' }
        'DOUBLE' { return 'Double' }
        default { throw "Runtime datatype '$RuntimeType' is not supported by the current ADS commissioning path." }
    }
}

function Assert-AicValidDocument {
    param(
        [Parameter(Mandatory)][string]$ValidatorPath,
        [Parameter(Mandatory)][string]$ParameterName,
        [Parameter(Mandatory)][string[]]$Paths
    )

    $powerShell = (Get-Process -Id $PID).Path
    $arguments = @('-NoProfile', '-File', $ValidatorPath, "-$ParameterName") + $Paths
    $output = @(& $powerShell @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Contract validation failed: $($output -join '; ')"
    }
}

function Get-AicProbeContext {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$RuntimeBindingsPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$BindingId,
        [string[]]$WritableBindingId = @()
    )

    $manifestValidator = Join-Path $script:AicRepositoryRoot 'scripts/validate-commissioning-record.ps1'
    $bindingValidator = Join-Path $script:AicRepositoryRoot 'scripts/validate-runtime-bindings.ps1'
    Assert-AicValidDocument -ValidatorPath $manifestValidator -ParameterName 'RecordPath' -Paths @($ManifestPath)
    Assert-AicValidDocument -ValidatorPath $bindingValidator -ParameterName 'BindingPath' -Paths @($RuntimeBindingsPath)

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.record_type -ne 'run_manifest') {
        throw 'ManifestPath must identify a run_manifest record.'
    }
    $runtimeDocument = Get-Content -LiteralPath $RuntimeBindingsPath -Raw | ConvertFrom-Json

    if ([string]$runtimeDocument.environment.connection_profile -ne [string]$manifest.connection_profile) {
        throw 'Runtime-binding connection_profile does not match the run manifest.'
    }

    $runtimeContract = @($manifest.input_contracts | Where-Object { $_.kind -eq 'runtime_bindings' })
    if ($runtimeContract.Count -ne 1) {
        throw 'Run manifest must contain exactly one runtime_bindings revision.'
    }
    $actualRelativePath = Get-AicRepositoryRelativePath -Path $RuntimeBindingsPath
    $actualRevision = Get-AicFileRevision -Path $RuntimeBindingsPath
    if ([string]$runtimeContract[0].path -ne $actualRelativePath -or
        [string]$runtimeContract[0].revision -ne $actualRevision) {
        throw 'Runtime bindings do not match the path and revision frozen in the run manifest.'
    }

    $bindingsById = @{}
    foreach ($binding in @($runtimeDocument.bindings)) {
        $id = [string]$binding.id
        if ($bindingsById.ContainsKey($id)) { throw "Duplicate runtime binding ID '$id'." }
        $bindingsById[$id] = $binding
    }

    function Resolve-Binding {
        param([Parameter(Mandatory)][string]$Id, [switch]$Writable)

        if (-not $bindingsById.ContainsKey($Id)) { throw "Runtime binding '$Id' was not found." }
        $binding = $bindingsById[$Id]
        if ([string]$binding.asset_id -ne [string]$manifest.asset_id) {
            throw "Runtime binding '$Id' belongs to asset '$($binding.asset_id)', not '$($manifest.asset_id)'."
        }
        if ([string]$binding.status -in @('rejected', 'stale')) {
            throw "Runtime binding '$Id' has unusable status '$($binding.status)'."
        }
        if ([string]$binding.locator.kind -ne 'ads_symbol') {
            throw "Runtime binding '$Id' is not an ADS symbol binding."
        }
        if ([string]::IsNullOrWhiteSpace([string]$binding.locator.value)) {
            throw "Runtime binding '$Id' has no runtime locator."
        }
        [void](ConvertTo-AicPowerShellType -RuntimeType ([string]$binding.datatype))
        if ($Writable) {
            if ([string]$binding.access -ne 'read_write') {
                throw "Write binding '$Id' must be readable and writable for guarded execution."
            }
        }
        elseif ([string]$binding.access -notin @('read', 'read_write')) {
            throw "Observation binding '$Id' is not readable."
        }
        return $binding
    }

    $requestedIds = @($BindingId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requestedIds.Count -ne @($requestedIds | Select-Object -Unique).Count) {
        throw 'BindingId must not contain duplicates.'
    }
    $writableIds = @($WritableBindingId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    foreach ($id in $writableIds) {
        if ($id -notin $requestedIds) { throw "Writable request binding '$id' is not present in BindingId." }
    }

    $resolvedBindings = [ordered]@{}
    foreach ($id in $requestedIds) {
        $binding = Resolve-Binding -Id $id -Writable:($id -in $writableIds)
        $resolvedBindings[$id] = $binding
    }

    $locators = @($resolvedBindings.Values | ForEach-Object { [string]$_.locator.value })
    if (@($locators | Select-Object -Unique).Count -ne $locators.Count) {
        throw 'Requested runtime bindings must resolve to distinct ADS locators.'
    }

    return [PSCustomObject]@{
        RepositoryRoot = $script:AicRepositoryRoot
        Manifest = $manifest
        RuntimeBindings = $runtimeDocument
        Bindings = $resolvedBindings
    }
}

function Assert-AicProbePreflight {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$PreflightPath
    )

    $validator = Join-Path $script:AicRepositoryRoot 'scripts/validate-commissioning-record.ps1'
    Assert-AicValidDocument -ValidatorPath $validator -ParameterName 'RecordPath' -Paths @($ManifestPath, $PreflightPath)
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $preflight = Get-Content -LiteralPath $PreflightPath -Raw | ConvertFrom-Json
    if ([string]$preflight.record_type -ne 'preflight') { throw 'PreflightPath must identify a preflight record.' }
    foreach ($property in @('run_id', 'case_id', 'asset_id', 'requested_interface')) {
        if ([string]$preflight.$property -ne [string]$manifest.$property) {
            throw "Preflight $property does not match the run manifest."
        }
    }
    if ([string]$preflight.assessment -ne 'ready_for_supervised_probe') {
        throw "Probe execution requires ready_for_supervised_probe; current assessment is '$($preflight.assessment)'."
    }
    return $preflight
}
