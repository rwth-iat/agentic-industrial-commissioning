Set-StrictMode -Version Latest

$script:AicRepositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

function Get-AicPropertyValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-AicRepositoryRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
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
        [Parameter(Mandatory)][string]$EnterModeRequestBindingId,
        [Parameter(Mandatory)][string]$ActivateRequestBindingId,
        [Parameter(Mandatory)][string]$DeactivateRequestBindingId,
        [Parameter(Mandatory)][string]$ExitModeRequestBindingId,
        [string[]]$AdditionalBindingId = @()
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
        param([Parameter(Mandatory)][string]$Id, [switch]$WritableRequest)

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
        if ($WritableRequest) {
            if ([string]$binding.access -ne 'read_write') {
                throw "Request binding '$Id' must be readable and writable for preflight and execution."
            }
            if ([string]$binding.interaction.semantics -ne 'request') {
                throw "Request binding '$Id' must declare request interaction semantics."
            }
        }
        elseif ([string]$binding.access -notin @('read', 'read_write')) {
            throw "Observation binding '$Id' is not readable."
        }
        return $binding
    }

    $enterMode = Resolve-Binding -Id $EnterModeRequestBindingId -WritableRequest
    $activate = Resolve-Binding -Id $ActivateRequestBindingId -WritableRequest
    $deactivate = Resolve-Binding -Id $DeactivateRequestBindingId -WritableRequest
    $exitMode = Resolve-Binding -Id $ExitModeRequestBindingId -WritableRequest

    $modeAcknowledgementId = [string](Get-AicPropertyValue -Object $enterMode.interaction -Name 'acknowledgement_binding_id')
    $activeAcknowledgementId = [string](Get-AicPropertyValue -Object $activate.interaction -Name 'acknowledgement_binding_id')
    if ([string]::IsNullOrWhiteSpace($modeAcknowledgementId) -or
        [string]::IsNullOrWhiteSpace($activeAcknowledgementId)) {
        throw 'Enter-mode and activate request bindings require acknowledgement_binding_id.'
    }
    if ([string](Get-AicPropertyValue -Object $exitMode.interaction -Name 'acknowledgement_binding_id') -ne $modeAcknowledgementId) {
        throw 'Exit-mode request must reference the same mode acknowledgement as enter-mode request.'
    }
    if ([string](Get-AicPropertyValue -Object $deactivate.interaction -Name 'acknowledgement_binding_id') -ne $activeAcknowledgementId) {
        throw 'Deactivate request must reference the same active acknowledgement as activate request.'
    }

    $modeAcknowledgement = Resolve-Binding -Id $modeAcknowledgementId
    $activeAcknowledgement = Resolve-Binding -Id $activeAcknowledgementId
    foreach ($booleanBinding in @($enterMode, $modeAcknowledgement, $activate, $activeAcknowledgement, $deactivate, $exitMode)) {
        if ((ConvertTo-AicPowerShellType -RuntimeType ([string]$booleanBinding.datatype)) -ne 'Boolean') {
            throw "Bounded Boolean probe binding '$($booleanBinding.id)' must have Boolean datatype."
        }
    }

    $slots = [ordered]@{
        EnterModeRequest    = $enterMode
        ModeAcknowledgement = $modeAcknowledgement
        ActivateRequest     = $activate
        ActiveAcknowledgement = $activeAcknowledgement
        DeactivateRequest   = $deactivate
        ExitModeRequest     = $exitMode
    }
    $locators = @($slots.Values | ForEach-Object { [string]$_.locator.value })
    if (@($locators | Select-Object -Unique).Count -ne 6) {
        throw 'The bounded probe requires six distinct request and acknowledgement locators.'
    }

    $additional = @()
    foreach ($id in @($AdditionalBindingId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $additional += Resolve-Binding -Id $id
    }

    return [PSCustomObject]@{
        RepositoryRoot = $script:AicRepositoryRoot
        Manifest = $manifest
        RuntimeBindings = $runtimeDocument
        Slots = $slots
        AdditionalBindings = $additional
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
