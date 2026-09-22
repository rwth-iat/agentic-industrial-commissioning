[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$writer = Join-Path $repositoryRoot 'scripts/append-runtime-evidence.ps1'
$caseId = 'runtime-evidence-test-' + [guid]::NewGuid().ToString('N')
$timestamp = '20260917T130000.0000000Z'
$caseDirectory = Join-Path $repositoryRoot (Join-Path 'cases' $caseId)
$rawDirectory = Join-Path $caseDirectory 'raw'
$runtimeDirectory = Join-Path $rawDirectory 'runtime'
$evidenceDirectory = Join-Path $runtimeDirectory $timestamp
$eventsPath = Join-Path $evidenceDirectory 'events.jsonl'
$readEvent = '{"operation":"read","binding_id":"synthetic-read","value":12.5,"observed_at":"2026-09-17T13:00:00Z","success":true}'
$writeEvent = '{"operation":"write","binding_id":"synthetic-write","requested_value":25,"value":25,"observed_at":"2026-09-17T13:00:01Z","success":true}'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $failures.Add($Message)
}

try {
    $firstPath = & $writer -CaseId $caseId -Timestamp $timestamp -EventJson $readEvent
    $secondPath = & $writer -CaseId $caseId -Timestamp $timestamp -EventJson $writeEvent
    if ([string]$firstPath -cne $eventsPath -or [string]$secondPath -cne $eventsPath) {
        Add-Failure 'Runtime-evidence writer returned an unexpected path.'
    }
    if (-not (Test-Path -LiteralPath $eventsPath -PathType Leaf)) {
        Add-Failure 'Runtime-evidence writer did not create events.jsonl.'
    }
    else {
        $lines = [IO.File]::ReadAllLines($eventsPath)
        if ($lines.Count -ne 2 -or
            $lines[0] -cne $readEvent -or
            $lines[1] -cne $writeEvent) {
            Add-Failure 'Runtime events were not appended byte-for-line unchanged.'
        }
        $bytes = [IO.File]::ReadAllBytes($eventsPath)
        if ($bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Add-Failure 'events.jsonl unexpectedly contains a UTF-8 BOM.'
        }
    }

    $files = @(Get-ChildItem -LiteralPath $evidenceDirectory -File)
    if ($files.Count -ne 1 -or $files[0].Name -cne 'events.jsonl') {
        Add-Failure 'Runtime evidence directory contains more than events.jsonl.'
    }

    Push-Location $repositoryRoot
    try {
        $relativeEventsPath = "cases/$caseId/raw/runtime/$timestamp/events.jsonl"
        $null = & git check-ignore --no-index -- $relativeEventsPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Failure 'Runtime evidence path is not ignored by Git.'
        }
    }
    finally {
        Pop-Location
    }

    foreach ($invalidCase in @(
        @{ Name = 'case traversal'; CaseId = '../escape'; Timestamp = $timestamp; Json = $readEvent },
        @{ Name = 'timestamp traversal'; CaseId = $caseId; Timestamp = '../escape'; Json = $readEvent },
        @{ Name = 'multiple lines'; CaseId = $caseId; Timestamp = $timestamp; Json = "${readEvent}`n${writeEvent}" },
        @{ Name = 'invalid JSON'; CaseId = $caseId; Timestamp = $timestamp; Json = 'not-json' },
        @{ Name = 'JSON array'; CaseId = $caseId; Timestamp = $timestamp; Json = '[]' }
    )) {
        $rejected = $false
        try {
            $null = & $writer `
                -CaseId $invalidCase.CaseId `
                -Timestamp $invalidCase.Timestamp `
                -EventJson $invalidCase.Json
        }
        catch {
            $rejected = $true
        }
        if (-not $rejected) {
            Add-Failure "Runtime-evidence writer accepted invalid input '$($invalidCase.Name)'."
        }
    }
}
finally {
    if (Test-Path -LiteralPath $eventsPath) {
        Remove-Item -LiteralPath $eventsPath -Force
    }
    foreach ($directory in @(
        $evidenceDirectory,
        $runtimeDirectory,
        $rawDirectory,
        $caseDirectory
    )) {
        if (Test-Path -LiteralPath $directory) {
            Remove-Item -LiteralPath $directory -Force
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "FAIL $failure" }
    exit 1
}

Write-Output 'Minimal runtime-evidence checks passed.'
exit 0
