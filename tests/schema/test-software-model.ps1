[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repositoryRoot 'scripts/validate-software-model.ps1'
$basePath = Join-Path $repositoryRoot 'examples/software-models/process-cell.synthetic.v0.1.json'
$casePath = Join-Path $repositoryRoot 'tests/schema/fixtures/software-models/cases.json'
$powerShell = (Get-Process -Id $PID).Path
$tempRoot = Join-Path $repositoryRoot "tmp/software-model-schema-$([guid]::NewGuid().ToString('N'))"
$privateCaseRoot = Join-Path $repositoryRoot "cases/privacy-contract-$([guid]::NewGuid().ToString('N'))"
$privateTempRoot = Join-Path $privateCaseRoot 'derived/private'
$null = New-Item -ItemType Directory -Path $tempRoot -Force
$null = New-Item -ItemType Directory -Path $privateTempRoot -Force

try {
    $baseRaw = Get-Content -Raw -LiteralPath $basePath
    $caseDocument = Get-Content -Raw -LiteralPath $casePath | ConvertFrom-Json
    $cases = @()
    foreach ($caseItem in $caseDocument) { $cases += $caseItem }
    $failed = $false

    foreach ($case in $cases) {
        $document = $baseRaw | ConvertFrom-Json
        $usePrivatePath = $false
        switch ([string]$case.mutation) {
            'none' { }
            'classify-private-correctly' {
                $document.data_classification = 'private'
                $usePrivatePath = $true
            }
            'remove-signal-evidence' {
                $document.component_interfaces[0].signals[0].status = 'inferred'
                $document.component_interfaces[0].signals[0].PSObject.Properties.Remove('evidence')
            }
            'set-static-signal-validated' {
                $document.component_interfaces[0].signals[0].status = 'validated'
            }
            'set-dangling-object-reference' {
                $document.component_interfaces[0].signals[0].software_object_ref = 'missing-object'
            }
            'set-dangling-condition-reference' {
                $document.component_interfaces[0].signals[0].availability.conditions[0].subject_ref = 'missing-signal'
            }
            'reverse-engineering-range' {
                $document.component_interfaces[0].signals[0].engineering_range.minimum = 101
                $document.component_interfaces[0].signals[0].engineering_range.maximum = 0
            }
            'duplicate-signal-id' {
                $document.component_interfaces[1].signals[0].id = $document.component_interfaces[0].signals[0].id
            }
            'reference-case-raw' {
                $document.sources[0].locator = 'cases/private-plant/raw/bom.json'
            }
            'classify-private-outside-case-private' {
                $document.data_classification = 'private'
            }
            'remove-relative-effect-reference' {
                $document.component_interfaces[0].signals[0].expected_effect.expected = 50
            }
            'add-unexamined-source-to-complete-inventory' {
                $document.scope.unexamined_sources = @('Synthetic source intentionally left unexamined.')
            }
            default { throw "Unknown mutation '$($case.mutation)'" }
        }

        $outputRoot = if ($usePrivatePath) { $privateTempRoot } else { $tempRoot }
        $documentPath = Join-Path $outputRoot "$($case.name).json"
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $documentPath -Encoding utf8
        $validatorOutput = & $powerShell -NoProfile -File $validator -ModelPath $documentPath 2>&1
        $actualExitCode = $LASTEXITCODE
        if ($actualExitCode -eq [int]$case.expected_exit_code) {
            Write-Output "PASS $($case.name) (exit ${actualExitCode})"
        }
        else {
            $failed = $true
            Write-Output "FAIL $($case.name): expected exit $($case.expected_exit_code), got ${actualExitCode}"
            $validatorOutput | ForEach-Object { Write-Output "  $_" }
        }
    }

    if ($failed) { exit 1 }
    Write-Output "All $($cases.Count) software-model validation tests passed."
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $privateCaseRoot) {
        Remove-Item -LiteralPath $privateCaseRoot -Recurse -Force
    }
}
