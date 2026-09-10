[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$runtimePath = Join-Path $repositoryRoot 'tests/fixtures/supervised-probe/runtime-bindings.synthetic.v0.1.json'
$preflightScript = Join-Path $repositoryRoot 'scripts/capabilities/twincat/Invoke-AdsBindingPreflight.ps1'
$probeScript = Join-Path $repositoryRoot 'scripts/capabilities/twincat/Invoke-AdsSupervisedProbe.ps1'
$completeScript = Join-Path $repositoryRoot 'scripts/complete-supervised-probe.ps1'
$validator = Join-Path $repositoryRoot 'scripts/validate-commissioning-record.ps1'
$powerShell = (Get-Process -Id $PID).Path
$failures = [System.Collections.Generic.List[string]]::new()
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$caseId = "probe-test-$suffix"
$runId = "run-probe-test-$suffix"
$caseRoot = Join-Path $repositoryRoot "cases/$caseId"
$validationRoot = Join-Path $caseRoot "validation/private/$runId"
$adapterRelative = "generated/connectors/probe-test-$suffix/components/asset-valve/verification.json"
$adapterRoot = Join-Path $repositoryRoot "generated/connectors/probe-test-$suffix"

function Add-Failure { param([string]$Message) $failures.Add($Message) }

try {
    $null = New-Item -ItemType Directory -Path $validationRoot -Force
    $runtimeRelative = $runtimePath.Substring($repositoryRoot.Length + 1).Replace('\', '/')
    $runtimeRevision = "sha256:$((Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant())"
    $revisions = @(
        [ordered]@{ kind = 'hardware_model'; path = 'tests/fixtures/hardware.json'; revision = 'sha256:hardware' },
        [ordered]@{ kind = 'software_model'; path = 'tests/fixtures/software.json'; revision = 'sha256:software' },
        [ordered]@{ kind = 'implementation_links'; path = 'tests/fixtures/links.json'; revision = 'sha256:links' },
        [ordered]@{ kind = 'runtime_bindings'; path = $runtimeRelative; revision = $runtimeRevision }
    )
    $manifestPath = Join-Path $validationRoot 'run-manifest.json'
    [ordered]@{
        schema_version = '0.1.0'; record_type = 'run_manifest'; run_id = $runId; case_id = $caseId
        asset_id = 'asset-valve'; requested_interface = 'open'; created_at = '2026-09-10T12:00:00Z'
        data_classification = 'private'; repository_revision = 'synthetic'; connection_profile = 'synthetic-ads'
        input_contracts = $revisions
        safety_boundary = [ordered]@{ mode = 'read_only_preflight'; state_changes_authorized = $false }
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $preflightPath = Join-Path $validationRoot 'preflight.json'
    [ordered]@{
        schema_version = '0.1.0'; record_type = 'preflight'; run_id = $runId; case_id = $caseId
        asset_id = 'asset-valve'; requested_interface = 'open'; created_at = '2026-09-10T12:00:05Z'
        data_classification = 'private'; observed_at = '2026-09-10T12:00:04Z'
        raw_evidence_refs = @("cases/$caseId/raw/runtime/$runId/preflight-ads.json")
        checks = @([ordered]@{ id = 'synthetic-preflight'; status = 'passed'; evidence_refs = @("cases/$caseId/raw/runtime/$runId/preflight-ads.json") })
        hypotheses = @([ordered]@{ id = 'requested-interface-effect'; statement = 'Synthetic probe hypothesis.'; status = 'untested'; evidence_refs = @() })
        assessment = 'ready_for_supervised_probe'; blockers = @(); writes_observed = $false
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $preflightPath -Encoding utf8

    $bindingArguments = @{
        ManifestPath = $manifestPath
        RuntimeBindingsPath = $runtimePath
        EnterModeRequestBindingId = 'mode-enter-request'
        ActivateRequestBindingId = 'activate-request'
        DeactivateRequestBindingId = 'deactivate-request'
        ExitModeRequestBindingId = 'mode-exit-request'
        ExpectedBindingValue = @{ permit = 'True' }
    }
    try {
        $preflightPlan = & $preflightScript @bindingArguments
        $serializedPlan = $preflightPlan | ConvertTo-Json -Depth 20
        if ($preflightPlan.Safety -ne 'READ_ONLY' -or $preflightPlan.WritesAuthorized -ne $false) {
            Add-Failure 'Preflight preparation did not preserve the read-only boundary.'
        }
        if ($serializedPlan -match 'Synthetic\.Valve') {
            Add-Failure 'Preflight plan exposed concrete PLC locators instead of binding IDs.'
        }
        if (@($preflightPlan.BindingExpectations).Count -ne 7) {
            Add-Failure 'Preflight plan did not include six core bindings and the additional permit.'
        }
    }
    catch { Add-Failure "Preflight preparation failed: $($_.Exception.Message)" }

    try {
        $probePlan = & $probeScript @bindingArguments -PreflightPath $preflightPath -HoldSeconds 5
        $serializedProbe = $probePlan | ConvertTo-Json -Depth 30
        if ($probePlan.RequiredApproval -notmatch '^APPROVE SUPERVISED_PROBE [A-F0-9]{12}$') {
            Add-Failure 'Probe preparation did not create an operation-specific approval phrase.'
        }
        if ($serializedProbe -match 'Synthetic\.Valve') {
            Add-Failure 'Probe plan exposed concrete PLC locators instead of binding IDs.'
        }
        $blocked = $false
        try {
            & $probeScript @bindingArguments -PreflightPath $preflightPath -HoldSeconds 5 `
                -Execute -Approval 'wrong' -ApprovedAt '2026-09-10T12:00:06Z' `
                -ApprovalSourceRef 'conversation:synthetic' 2>&1 | Out-Null
        }
        catch { $blocked = $_.Exception.Message -match 'Execution blocked' }
        if (-not $blocked) { Add-Failure 'Probe execution was not blocked by an incorrect approval phrase.' }
    }
    catch { Add-Failure "Probe preparation failed: $($_.Exception.Message)" }

    $manifestDocument = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $runtimeContract = @($manifestDocument.input_contracts | Where-Object { $_.kind -eq 'runtime_bindings' })[0]
    $runtimeContract.revision = 'sha256:stale'
    $manifestDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $staleBlocked = $false
    try { & $preflightScript @bindingArguments 2>&1 | Out-Null }
    catch { $staleBlocked = $_.Exception.Message -match 'do not match the path and revision' }
    if (-not $staleBlocked) { Add-Failure 'Changed runtime-binding revision did not invalidate preflight preparation.' }

    $invalidRuntimePath = Join-Path $validationRoot 'runtime-bindings-wrong-type.json'
    $invalidRuntime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
    (@($invalidRuntime.bindings | Where-Object { $_.id -eq 'activate-request' })[0]).datatype = 'REAL'
    $invalidRuntime | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidRuntimePath -Encoding utf8
    $runtimeContract.path = $invalidRuntimePath.Substring($repositoryRoot.Length + 1).Replace('\', '/')
    $runtimeContract.revision = "sha256:$((Get-FileHash -LiteralPath $invalidRuntimePath -Algorithm SHA256).Hash.ToLowerInvariant())"
    $manifestDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $wrongTypeArguments = $bindingArguments.Clone()
    $wrongTypeArguments.RuntimeBindingsPath = $invalidRuntimePath
    $wrongTypeBlocked = $false
    try { & $preflightScript @wrongTypeArguments 2>&1 | Out-Null }
    catch { $wrongTypeBlocked = $_.Exception.Message -match 'must have Boolean datatype' }
    if (-not $wrongTypeBlocked) { Add-Failure 'Non-Boolean bounded-probe binding did not block preflight preparation.' }

    $runtimeContract.path = $runtimeRelative
    $runtimeContract.revision = $runtimeRevision
    $manifestDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $adapterDirectory = Split-Path -Parent (Join-Path $repositoryRoot $adapterRelative)
    $null = New-Item -ItemType Directory -Path $adapterDirectory -Force
    Set-Content -LiteralPath (Join-Path $adapterDirectory 'Invoke-Synthetic.ps1') -Value 'param()' -Encoding utf8
    [ordered]@{
        schema_version = '0.1.0'; asset_id = 'asset-valve'; supported_interfaces = @('open')
        entrypoint = 'Invoke-Synthetic.ps1'; verification_status = 'verified'
        input_revisions = $revisions; evidence_refs = @("cases/$caseId/raw/runtime/$runId/execution-facts.json")
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $repositoryRoot $adapterRelative) -Encoding utf8

    $rawRoot = Join-Path $caseRoot "raw/runtime/$runId"
    $null = New-Item -ItemType Directory -Path $rawRoot -Force
    $rawReference = "cases/$caseId/raw/runtime/$runId/probe-ads.json"
    $factsPath = Join-Path $rawRoot 'execution-facts.json'
    [ordered]@{
        schema_version = '0.1.0'; kind = 'normalized_supervised_probe_facts'; run_id = $runId; case_id = $caseId
        asset_id = 'asset-valve'; requested_interface = 'open'; operation_id = 'ABCDEF123456'; input_revisions = $revisions
        approval = [ordered]@{ approved_at = '2026-09-10T12:00:06Z'; scope = 'Synthetic bounded probe.'; maximum_duration_seconds = 5; restore_target = 'inactive actuation and inactive mode'; source_ref = 'conversation:synthetic' }
        started_at = '2026-09-10T12:00:07Z'; finished_at = '2026-09-10T12:00:12Z'
        initial_state = [ordered]@{ mode_active = $false; actuation_active = $false }
        events = @(
            [ordered]@{ timestamp = '2026-09-10T12:00:07Z'; kind = 'read'; binding_id = 'active-state'; value = $false; outcome = 'succeeded'; raw_evidence_ref = $rawReference },
            [ordered]@{ timestamp = '2026-09-10T12:00:08Z'; kind = 'write'; binding_id = 'activate-request'; value = $true; outcome = 'succeeded'; raw_evidence_ref = $rawReference },
            [ordered]@{ timestamp = '2026-09-10T12:00:11Z'; kind = 'restore'; outcome = 'succeeded'; detail = 'Synthetic restore verified.'; raw_evidence_ref = $rawReference }
        )
        timeouts = [ordered]@{ overall_seconds = 25; triggered = $false }
        restore = [ordered]@{ attempted = $true; status = 'verified'; evidence_refs = @($rawReference) }
        final_state = [ordered]@{ mode_active = $false; actuation_active = $false }
        execution_status = 'succeeded'; raw_evidence_refs = @($rawReference)
    } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $factsPath -Encoding utf8

    try {
        $executionPath = & $completeScript -ManifestPath $manifestPath -ExecutionFactsPath $factsPath `
            -HypothesisStatement 'The functional request opens the synthetic valve.' -HypothesisStatus confirmed `
            -HumanObservation 'Synthetic visible movement.' -HumanObservationAt '2026-09-10T12:00:09Z' `
            -HumanObservationSourceRef 'conversation:synthetic' -AdapterRef $adapterRelative
        $execution = Get-Content -LiteralPath $executionPath -Raw | ConvertFrom-Json
        if ($execution.resulting_assessment -ne 'validated_interface' -or $execution.adapter_ref -ne $adapterRelative) {
            Add-Failure 'Probe completion did not gate validated_interface on the verified adapter.'
        }
    }
    catch { Add-Failure "Probe completion failed: $($_.Exception.Message)" }

    $verificationPath = Join-Path $repositoryRoot $adapterRelative
    $verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
    $verification.verification_status = 'experimental'
    $verification | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $verificationPath -Encoding utf8
    $validationOutput = @(& $powerShell -NoProfile -File $validator -RecordPath $executionPath 2>&1)
    if ($LASTEXITCODE -eq 0 -or ($validationOutput -join ' ') -notmatch 'verification_status must be verified') {
        Add-Failure 'Commissioning validator accepted an unverified adapter reference.'
    }

    $verification.verification_status = 'verified'
    $verification.input_revisions[0].revision = 'sha256:stale-hardware'
    $verification | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $verificationPath -Encoding utf8
    $validationOutput = @(& $powerShell -NoProfile -File $validator -RecordPath $executionPath 2>&1)
    if ($LASTEXITCODE -eq 0 -or ($validationOutput -join ' ') -notmatch 'input revisions do not match') {
        Add-Failure 'Commissioning validator accepted adapter evidence from different input revisions.'
    }

    $probeSource = Get-Content -LiteralPath $probeScript -Raw
    if ($probeSource -match '\[string\]\$(?:Symbol|RequestSymbol|AcknowledgementSymbol)') {
        Add-Failure 'Supervised-probe dispatcher exposes free PLC-symbol parameters.'
    }
    if (Test-Path -LiteralPath (Join-Path $repositoryRoot 'scripts/capabilities/twincat/Invoke-AdsControlledAction.ps1')) {
        Add-Failure 'Retired controlled-action dispatcher still exists.'
    }
}
finally {
    if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
    if (Test-Path -LiteralPath $adapterRoot) { Remove-Item -LiteralPath $adapterRoot -Recurse -Force }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL $_" }
    exit 1
}
Write-Output 'All supervised-probe infrastructure tests passed.'
exit 0
