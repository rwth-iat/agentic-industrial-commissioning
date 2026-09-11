[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$RuntimeBindingsPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$BindingExpectation,
    [switch]$Execute,
    [string]$ConfigPath,
    [string]$StateFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repositoryRoot 'scripts/commissioning/supervised-probe.common.ps1')

$expectations = [ordered]@{}
foreach ($item in $BindingExpectation) {
    $id = [string](Get-AicPropertyValue -Object $item -Name 'binding_id')
    $expected = [string](Get-AicPropertyValue -Object $item -Name 'expected_value')
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'Every BindingExpectation requires binding_id.' }
    if ([string]::IsNullOrWhiteSpace($expected)) { throw "BindingExpectation '$id' requires expected_value." }
    if ($expectations.Contains($id)) { throw "Duplicate BindingExpectation for '$id'." }
    $expectations[$id] = $expected
}
$context = Get-AicProbeContext `
    -ManifestPath $ManifestPath `
    -RuntimeBindingsPath $RuntimeBindingsPath `
    -BindingId @($expectations.Keys)

$bindingPlan = @($expectations.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        binding_id = [string]$_.Key
        expected_value = [string]$_.Value
    }
})
$plan = [PSCustomObject]@{
    Stage = 'read_only_preflight'
    Safety = 'READ_ONLY'
    RunId = [string]$context.Manifest.run_id
    CaseId = [string]$context.Manifest.case_id
    AssetId = [string]$context.Manifest.asset_id
    RequestedInterface = [string]$context.Manifest.requested_interface
    BindingExpectations = $bindingPlan
    WritesAuthorized = $false
}
if (-not $Execute) {
    $plan
    return
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repositoryRoot 'creds/twincat-ads.local.psd1'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "ADS configuration not found: $ConfigPath"
}

$recipeBindings = @($expectations.GetEnumerator() | ForEach-Object {
    $binding = $context.Bindings[[string]$_.Key]
    [PSCustomObject]@{
        BindingId = [string]$binding.id
        Symbol = [string]$binding.locator.value
        Type = ConvertTo-AicPowerShellType -RuntimeType ([string]$binding.datatype)
        RuntimeType = [string]$binding.datatype
        ExpectedValue = [string]$_.Value
    }
})

$selector = Join-Path $repositoryRoot 'scripts/capabilities/twincat/Invoke-AdsCapability.ps1'
$selectorParameters = @{
    Capability = 'ReadBindingPreflight'
    Bindings = $recipeBindings
    ExpectedAdsState = 'Run'
    ConfigPath = $ConfigPath
}
if (-not [string]::IsNullOrWhiteSpace($StateFile)) { $selectorParameters.StateFile = $StateFile }

$rawDirectory = Join-Path $repositoryRoot "cases/$($context.Manifest.case_id)/raw/runtime/$($context.Manifest.run_id)"
$rawPath = Join-Path $rawDirectory 'preflight-ads.json'
if (Test-Path -LiteralPath $rawPath) {
    throw "Refusing to overwrite existing raw preflight evidence: $rawPath"
}
$null = New-Item -ItemType Directory -Path $rawDirectory -Force

try {
    $remoteOutput = @(& $selector @selectorParameters 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($remoteOutput -join '; ') }
    $envelope = ($remoteOutput -join [Environment]::NewLine) | ConvertFrom-Json
}
catch {
    $now = [DateTimeOffset]::UtcNow.ToString('o')
    $envelope = [PSCustomObject]@{
        schema_version = '0.1.0'
        kind = 'ads_binding_preflight'
        started_at = $now
        finished_at = $now
        writes_observed = $false
        success = $false
        observations = @()
        errors = @($_.Exception.Message)
    }
}

$envelope | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $rawPath -Encoding utf8
$rawReference = Get-AicRepositoryRelativePath -Path $rawPath
$checks = [System.Collections.Generic.List[object]]::new()
$index = 0
foreach ($observation in @($envelope.observations)) {
    $index++
    $detail = if ([string]$observation.check -eq 'plc-runtime-state') {
        "PLC state expected '$($observation.expected)', observed '$($observation.actual)'."
    }
    elseif ($observation.PSObject.Properties.Name -contains 'error') {
        "Binding '$($observation.binding_id)' failed: $($observation.error)"
    }
    else {
        "Binding '$($observation.binding_id)' expected '$($observation.expected)', observed '$($observation.actual)'."
    }
    $checks.Add([PSCustomObject]@{
        id = "runtime-check-$index"
        status = if ([bool]$observation.passed) { 'passed' } else { 'failed' }
        detail = $detail
        evidence_refs = @($rawReference)
    })
}
if ($checks.Count -eq 0) {
    $checks.Add([PSCustomObject]@{
        id = 'runtime-access'
        status = 'failed'
        detail = "Read-only runtime acquisition failed: $(@($envelope.errors) -join '; ')"
        evidence_refs = @($rawReference)
    })
}

$failedChecks = @($checks | Where-Object { $_.status -eq 'failed' })
$blockers = @()
for ($index = 0; $index -lt $failedChecks.Count; $index++) {
    $blockers += [PSCustomObject]@{
        code = "preflight-$($index + 1)"
        description = [string]$failedChecks[$index].detail
        required_evidence_or_mitigation = 'Resolve the failed read-only check without changing plant state.'
        reevaluation_condition = 'Start a new run and repeat read-only preflight after the condition is resolved.'
    }
}
$assessment = if ($failedChecks.Count -eq 0 -and [bool]$envelope.success) {
    'ready_for_supervised_probe'
}
else {
    'hard_blocked'
}

$record = [ordered]@{
    schema_version = '0.1.0'
    record_type = 'preflight'
    run_id = [string]$context.Manifest.run_id
    case_id = [string]$context.Manifest.case_id
    asset_id = [string]$context.Manifest.asset_id
    requested_interface = [string]$context.Manifest.requested_interface
    created_at = [DateTimeOffset]::UtcNow.ToString('o')
    data_classification = 'private'
    observed_at = [string]$envelope.finished_at
    raw_evidence_refs = @($rawReference)
    checks = @($checks)
    hypotheses = @([ordered]@{
        id = 'requested-interface-effect'
        statement = "The resolved functional request path produces the requested '$($context.Manifest.requested_interface)' effect."
        status = 'untested'
        evidence_refs = @()
    })
    assessment = $assessment
    blockers = $blockers
    writes_observed = $false
}

$candidate = [IO.Path]::GetTempFileName()
try {
    $record | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $candidate -Encoding utf8
    $writer = Join-Path $repositoryRoot 'scripts/write-commissioning-record.ps1'
    $powerShell = (Get-Process -Id $PID).Path
    $writerOutput = @(& $powerShell -NoProfile -File $writer -InputPath $candidate 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Could not persist preflight: $($writerOutput -join '; ')" }
    [PSCustomObject]@{
        PreflightPath = [string]$writerOutput[-1]
        RawEvidencePath = $rawPath
        Assessment = $assessment
    }
}
finally {
    if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force }
}
