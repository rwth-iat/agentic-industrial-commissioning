[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repositoryRoot 'scripts/validate-commissioning-record.ps1'
$writer = Join-Path $repositoryRoot 'scripts/write-commissioning-record.ps1'
$runCreator = Join-Path $repositoryRoot 'scripts/new-commissioning-run.ps1'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures/commissioning-records'
$powerShell = (Get-Process -Id $PID).Path
$tempRoot = Join-Path $repositoryRoot "tmp/commissioning-records-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $tempRoot -Force
$failed = $false
$caseCount = 0
$caseRoot = $null
$generatedCaseRoot = $null

function Get-Fixture {
    param([string]$Name)
    return Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot $Name) | ConvertFrom-Json
}

function Invoke-RecordCase {
    param(
        [string]$Name,
        [object]$Document,
        [int]$ExpectedExitCode
    )
    $script:caseCount++
    $path = Join-Path $tempRoot "$Name.json"
    $Document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8
    $output = @(& $powerShell -NoProfile -File $validator -RecordPath $path -SkipPlacement 2>&1)
    $actualExitCode = $LASTEXITCODE
    if ($actualExitCode -eq $ExpectedExitCode) {
        Write-Output "PASS $Name (exit ${actualExitCode})"
        return
    }
    $script:failed = $true
    Write-Output "FAIL ${Name}: expected exit $ExpectedExitCode, got $actualExitCode"
    $output | ForEach-Object { Write-Output "  $_" }
}

function Invoke-MultiRecordValidation {
    param(
        [string]$Name,
        [string[]]$Paths,
        [switch]$SkipPlacement
    )
    $quotedValidator = $validator.Replace("'", "''")
    $quotedPaths = @($Paths | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ', '
    $skipText = if ($SkipPlacement) { ' -SkipPlacement' } else { '' }
    $driverPath = Join-Path $tempRoot "$Name-driver.ps1"
    $driver = "& '$quotedValidator' -RecordPath @($quotedPaths)$skipText; exit `$LASTEXITCODE"
    Set-Content -LiteralPath $driverPath -Value $driver -Encoding utf8
    $output = @(& $powerShell -NoProfile -File $driverPath 2>&1)
    return [PSCustomObject]@{
        Output = $output
        ExitCode = $LASTEXITCODE
    }
}

try {
    Invoke-RecordCase -Name 'valid-run-manifest' `
        -Document (Get-Fixture 'valid-run-manifest.v0.1.json') -ExpectedExitCode 0
    Invoke-RecordCase -Name 'valid-preflight' `
        -Document (Get-Fixture 'valid-preflight.v0.1.json') -ExpectedExitCode 0
    Invoke-RecordCase -Name 'valid-execution-record' `
        -Document (Get-Fixture 'valid-execution-record.v0.1.json') -ExpectedExitCode 0

    $document = Get-Fixture 'valid-run-manifest.v0.1.json'
    $document.input_contracts[3].kind = 'software_model'
    Invoke-RecordCase -Name 'invalid-missing-runtime-binding-revision' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-preflight.v0.1.json'
    $document.writes_observed = $true
    Invoke-RecordCase -Name 'invalid-preflight-with-write' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-preflight.v0.1.json'
    $document.assessment = 'hard_blocked'
    Invoke-RecordCase -Name 'invalid-hard-blocked-without-blocker' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-preflight.v0.1.json'
    $document.blockers = @([PSCustomObject]@{
        code = 'unsafe'
        description = 'Synthetic blocker.'
        required_evidence_or_mitigation = 'Synthetic evidence.'
        reevaluation_condition = 'Evidence becomes available.'
    })
    Invoke-RecordCase -Name 'invalid-ready-with-hard-blocker' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-preflight.v0.1.json'
    $document.assessment = 'validated_interface'
    Invoke-RecordCase -Name 'invalid-validated-preflight-without-adapter' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-execution-record.v0.1.json'
    $document.PSObject.Properties.Remove('approval')
    Invoke-RecordCase -Name 'invalid-execution-without-approval' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-execution-record.v0.1.json'
    $document.finished_at = '2026-09-10T11:59:59Z'
    Invoke-RecordCase -Name 'invalid-reversed-execution-time' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-execution-record.v0.1.json'
    $document.events = @($document.events | Where-Object { $_.kind -ne 'write' })
    Invoke-RecordCase -Name 'invalid-execution-without-write' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-execution-record.v0.1.json'
    $document.restore.status = 'failed'
    Invoke-RecordCase -Name 'invalid-success-with-failed-restore' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-execution-record.v0.1.json'
    $document.timeouts.triggered = $true
    Invoke-RecordCase -Name 'invalid-triggered-timeout-without-event' -Document $document -ExpectedExitCode 1

    $document = Get-Fixture 'valid-execution-record.v0.1.json'
    $document.resulting_assessment = 'validated_interface'
    Invoke-RecordCase -Name 'invalid-validated-interface-without-adapter' -Document $document -ExpectedExitCode 1

    $testCaseId = "record-test-$([guid]::NewGuid().ToString('N'))"
    $testRunId = 'run-001'
    $caseRoot = Join-Path $repositoryRoot "cases/$testCaseId"
    $writerInputRoot = Join-Path $tempRoot 'writer'
    $null = New-Item -ItemType Directory -Path $writerInputRoot -Force
    $writtenPaths = @()
    foreach ($fixtureName in @(
        'valid-run-manifest.v0.1.json',
        'valid-preflight.v0.1.json',
        'valid-execution-record.v0.1.json'
    )) {
        $document = Get-Fixture $fixtureName
        $document.case_id = $testCaseId
        $document.run_id = $testRunId
        $inputPath = Join-Path $writerInputRoot $fixtureName
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $inputPath -Encoding utf8
        $writerOutput = @(& $powerShell -NoProfile -File $writer -InputPath $inputPath 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $failed = $true
            Write-Output "FAIL writer-$fixtureName"
            $writerOutput | ForEach-Object { Write-Output "  $_" }
        }
        else {
            $writtenPaths += [string]$writerOutput[-1]
            Write-Output "PASS writer-$fixtureName"
        }
    }

    if ($writtenPaths.Count -eq 3) {
        $placedResult = Invoke-MultiRecordValidation -Name 'placed-run' -Paths $writtenPaths
        if ($placedResult.ExitCode -eq 0) {
            Write-Output 'PASS placed-run-consistency'
        }
        else {
            $failed = $true
            Write-Output 'FAIL placed-run-consistency'
            $placedResult.Output | ForEach-Object { Write-Output "  $_" }
        }

        $manifestInput = Join-Path $writerInputRoot 'valid-run-manifest.v0.1.json'
        $null = @(& $powerShell -NoProfile -File $writer -InputPath $manifestInput 2>&1)
        if ($LASTEXITCODE -eq 0) {
            Write-Output 'PASS idempotent-identical-write'
        }
        else {
            $failed = $true
            Write-Output 'FAIL idempotent-identical-write'
        }

        $conflict = Get-Content -Raw -LiteralPath $manifestInput | ConvertFrom-Json
        $conflict.repository_revision = 'different-revision'
        $conflictPath = Join-Path $writerInputRoot 'conflicting-manifest.json'
        $conflict | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $conflictPath -Encoding utf8
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $conflictOutput = @(& $powerShell -NoProfile -File $writer -InputPath $conflictPath 2>&1)
        $conflictExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        if ($conflictExitCode -eq 1) {
            Write-Output 'PASS conflicting-overwrite-blocked'
        }
        else {
            $failed = $true
            Write-Output 'FAIL conflicting-overwrite-blocked'
        }

        $mismatchedExecution = Get-Fixture 'valid-execution-record.v0.1.json'
        $mismatchedExecution.input_revisions[3].revision = 'sha256:different-bindings'
        $mismatchPath = Join-Path $tempRoot 'mismatched-execution.json'
        $mismatchedExecution | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $mismatchPath -Encoding utf8
        $crossPaths = @(
            (Join-Path $fixtureRoot 'valid-run-manifest.v0.1.json'),
            (Join-Path $fixtureRoot 'valid-preflight.v0.1.json'),
            $mismatchPath
        )
        $mismatchResult = Invoke-MultiRecordValidation -Name 'mismatched-run' -Paths $crossPaths -SkipPlacement
        if ($mismatchResult.ExitCode -ne 0) {
            Write-Output 'PASS mismatched-input-revisions-blocked'
        }
        else {
            $failed = $true
            Write-Output 'FAIL mismatched-input-revisions-blocked'
            $mismatchResult.Output | ForEach-Object { Write-Output "  $_" }
        }
    }

    $generatedCaseId = "record-create-$([guid]::NewGuid().ToString('N'))"
    $generatedCaseRoot = Join-Path $repositoryRoot "cases/$generatedCaseId"
    $createOutput = @(& $powerShell -NoProfile -File $runCreator `
        -CaseId $generatedCaseId `
        -AssetId 'asset-y20' `
        -RequestedInterface 'open' `
        -ConnectionProfile 'synthetic_ads' `
        -HardwareModelPath (Join-Path $repositoryRoot 'examples/hc10/hc10-mvp-example.v0.2.json') `
        -SoftwareModelPath (Join-Path $repositoryRoot 'examples/software-models/process-cell.synthetic.v0.1.json') `
        -ImplementationLinksPath (Join-Path $repositoryRoot 'examples/implementation-links/process-cell.synthetic.v0.1.json') `
        -RuntimeBindingsPath (Join-Path $repositoryRoot 'examples/runtime-bindings/twincat-ads.synthetic.v0.1.json') 2>&1)
    if ($LASTEXITCODE -eq 0 -and $createOutput.Count -gt 0 -and
        (Test-Path -LiteralPath ([string]$createOutput[-1]) -PathType Leaf)) {
        $createdManifest = Get-Content -Raw -LiteralPath ([string]$createOutput[-1]) | ConvertFrom-Json
        if ($createdManifest.run_id -like 'run-*' -and $createdManifest.input_contracts.Count -eq 4 -and
            @($createdManifest.input_contracts | Where-Object { $_.revision -like 'sha256:*' }).Count -eq 4) {
            Write-Output 'PASS deterministic-run-manifest-creation'
        }
        else {
            $failed = $true
            Write-Output 'FAIL deterministic-run-manifest-creation: generated content is incomplete'
        }
    }
    else {
        $failed = $true
        Write-Output 'FAIL deterministic-run-manifest-creation'
        $createOutput | ForEach-Object { Write-Output "  $_" }
    }

    if ($failed) { exit 1 }
    Write-Output "All $caseCount commissioning-record validation cases and writer checks passed."
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    if ($null -ne $caseRoot -and (Test-Path -LiteralPath $caseRoot)) {
        Remove-Item -LiteralPath $caseRoot -Recurse -Force
    }
    if ($null -ne $generatedCaseRoot -and (Test-Path -LiteralPath $generatedCaseRoot)) {
        Remove-Item -LiteralPath $generatedCaseRoot -Recurse -Force
    }
}
