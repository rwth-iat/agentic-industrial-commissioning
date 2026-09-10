[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ExecutionFactsPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$HypothesisStatement,
    [ValidateSet('untested', 'confirmed', 'refuted')][string]$HypothesisStatus = 'untested',
    [string[]]$HumanObservation = @(),
    [string]$HumanObservationAt,
    [string]$HumanObservationSourceRef,
    [string]$AdapterRef
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate-commissioning-record.ps1'
$writer = Join-Path $PSScriptRoot 'write-commissioning-record.ps1'
$powerShell = (Get-Process -Id $PID).Path

$validationOutput = @(& $powerShell -NoProfile -File $validator -RecordPath $ManifestPath 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Run manifest is invalid: $($validationOutput -join '; ')" }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$facts = Get-Content -LiteralPath $ExecutionFactsPath -Raw | ConvertFrom-Json

if ([string]$facts.kind -ne 'normalized_supervised_probe_facts') {
    throw 'ExecutionFactsPath does not contain normalized supervised-probe facts.'
}
foreach ($property in @('run_id', 'case_id', 'asset_id', 'requested_interface')) {
    if ([string]$facts.$property -ne [string]$manifest.$property) {
        throw "Execution facts $property does not match the run manifest."
    }
}
$revisionSignature = { param($items) (@($items) | Sort-Object kind | ForEach-Object { "$($_.kind)|$($_.path)|$($_.revision)" }) -join "`n" }
if ((& $revisionSignature $facts.input_revisions) -ne (& $revisionSignature $manifest.input_contracts)) {
    throw 'Execution-fact input revisions do not match the run manifest.'
}

$reads = @($facts.events | Where-Object { $_.kind -eq 'read' })
$writes = @($facts.events | Where-Object { $_.kind -eq 'write' })
if ($reads.Count -eq 0 -or $writes.Count -eq 0) {
    throw 'The executor did not preserve both an actual read and an actual write; keep the raw facts but do not fabricate an execution record.'
}

$humanObservations = @()
if ($HumanObservation.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($HumanObservationAt) -or [string]::IsNullOrWhiteSpace($HumanObservationSourceRef)) {
        throw 'HumanObservationAt and HumanObservationSourceRef are required when human observations are supplied.'
    }
    try { $observationTime = [DateTimeOffset]::Parse($HumanObservationAt, [Globalization.CultureInfo]::InvariantCulture).ToString('o') }
    catch { throw "HumanObservationAt is not a valid timestamp: $HumanObservationAt" }
    foreach ($observation in $HumanObservation) {
        if ([string]::IsNullOrWhiteSpace($observation)) { continue }
        $humanObservations += [ordered]@{
            timestamp = $observationTime
            observation = $observation
            source_ref = $HumanObservationSourceRef
        }
    }
}

$resultingAssessment = if ([string]$facts.restore.status -eq 'failed' -or [string]$facts.restore.status -eq 'unknown') {
    'hard_blocked'
}
elseif ([string]$facts.execution_status -eq 'succeeded' -and
    -not [string]::IsNullOrWhiteSpace($AdapterRef) -and
    $humanObservations.Count -gt 0 -and
    $HypothesisStatus -eq 'confirmed') {
    'validated_interface'
}
else {
    'ready_for_supervised_probe'
}

$record = [ordered]@{
    schema_version = '0.1.0'
    record_type = 'execution_record'
    run_id = [string]$facts.run_id
    case_id = [string]$facts.case_id
    asset_id = [string]$facts.asset_id
    requested_interface = [string]$facts.requested_interface
    created_at = [DateTimeOffset]::UtcNow.ToString('o')
    data_classification = 'private'
    input_revisions = @($facts.input_revisions)
    started_at = [string]$facts.started_at
    finished_at = [string]$facts.finished_at
    initial_state = $facts.initial_state
    approval = $facts.approval
    events = @($facts.events)
    timeouts = $facts.timeouts
    human_observations = $humanObservations
    restore = $facts.restore
    hypotheses = @([ordered]@{
        id = 'requested-interface-effect'
        statement = $HypothesisStatement
        status = $HypothesisStatus
        evidence_refs = @($facts.raw_evidence_refs)
    })
    final_state = $facts.final_state
    execution_status = [string]$facts.execution_status
    resulting_assessment = $resultingAssessment
}
if (-not [string]::IsNullOrWhiteSpace($AdapterRef)) { $record.adapter_ref = $AdapterRef.Replace('\', '/') }

$candidatePath = [IO.Path]::GetTempFileName()
try {
    $record | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $candidatePath -Encoding utf8
    $writerOutput = @(& $powerShell -NoProfile -File $writer -InputPath $candidatePath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Could not persist execution record: $($writerOutput -join '; ')" }
    Write-Output ([string]$writerOutput[-1])
}
finally {
    if (Test-Path -LiteralPath $candidatePath) { Remove-Item -LiteralPath $candidatePath -Force }
}
