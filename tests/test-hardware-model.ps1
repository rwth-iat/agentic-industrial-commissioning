[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $repositoryRoot 'scripts/validate-hardware-model.ps1'
$powerShell = Join-Path $PSHOME 'pwsh.exe'

$cases = @(
    @{
        Path = 'examples/hc10/hc10-mvp-example.v0.2.json'
        ExpectedExitCode = 0
    },
    @{
        Path = 'examples/hc10/hc10-mvp-unambiguous.v0.2.json'
        ExpectedExitCode = 0
    },
    @{
        Path = 'examples/hc10/hc10-mvp-incompatible.v0.2.json'
        ExpectedExitCode = 0
    },
    @{
        Path = 'tests/fixtures/hardware-model/invalid-schema-missing-interface.v0.2.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/fixtures/hardware-model/invalid-schema-inferred-without-evidence.v0.2.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/fixtures/hardware-model/invalid-schema-version.v0.2.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/fixtures/hardware-model/invalid-semantic-duplicate-asset-id.v0.2.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/fixtures/hardware-model/invalid-semantic-dangling-reference.v0.2.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/fixtures/hardware-model/invalid-semantic-reversed-range.v0.2.json'
        ExpectedExitCode = 1
    }
)

$failed = $false
foreach ($case in $cases) {
    $modelPath = Join-Path $repositoryRoot $case.Path
    $validatorOutput = & $powerShell -NoProfile -File $validator -ModelPath $modelPath 2>&1
    $actualExitCode = $LASTEXITCODE

    if ($actualExitCode -eq $case.ExpectedExitCode) {
        Write-Output "PASS $($case.Path) (exit ${actualExitCode})"
        continue
    }

    $failed = $true
    Write-Output "FAIL $($case.Path): expected exit $($case.ExpectedExitCode), got ${actualExitCode}"
    $validatorOutput | ForEach-Object { Write-Output "  $_" }
}

if ($failed) {
    exit 1
}

Write-Output "All $($cases.Count) hardware-model validation tests passed."
exit 0
