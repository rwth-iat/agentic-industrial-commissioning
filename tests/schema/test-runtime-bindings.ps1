[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repositoryRoot 'spec/validation/validate-runtime-bindings.ps1'
$powerShell = (Get-Process -Id $PID).Path

$cases = @(
    @{
        Path = 'examples/runtime-bindings/twincat-ads.synthetic.v0.1.json'
        ExpectedExitCode = 0
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/valid-reported-success.v0.1.json'
        ExpectedExitCode = 0
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/valid-write-without-semantics.v0.1.json'
        ExpectedExitCode = 0
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/invalid-endpoint-leak.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/invalid-dangling-source.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/invalid-dangling-acknowledgement.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/invalid-cross-asset-acknowledgement.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/invalid-validated-without-runtime-observation.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/invalid-pulse-duration.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/runtime-bindings/invalid-pulse-datatype.v0.1.json'
        ExpectedExitCode = 1
    }
)

$failed = $false
foreach ($case in $cases) {
    $bindingPath = Join-Path $repositoryRoot $case.Path
    $validatorOutput = & $powerShell -NoProfile -File $validator -BindingPath $bindingPath 2>&1
    $actualExitCode = $LASTEXITCODE

    if ($actualExitCode -eq $case.ExpectedExitCode) {
        Write-Output "PASS $($case.Path) (exit ${actualExitCode})"
        continue
    }

    $failed = $true
    Write-Output "FAIL $($case.Path): expected exit $($case.ExpectedExitCode), got ${actualExitCode}"
    $validatorOutput | ForEach-Object { Write-Output "  $_" }
}

if ($failed) { exit 1 }

Write-Output "All $($cases.Count) runtime-binding validation tests passed."
exit 0
