[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repositoryRoot 'scripts/validate-controlled-operation.ps1'
$runtimeBindings = Join-Path $repositoryRoot 'examples/runtime-bindings/twincat-ads.synthetic.v0.1.json'
$powerShell = Join-Path $PSHOME 'pwsh.exe'

$cases = @(
    @{
        Path = 'examples/controlled-operations/twincat-mode-request.synthetic.v0.1.json'
        ExpectedExitCode = 0
    },
    @{
        Path = 'tests/schema/fixtures/controlled-operations/invalid-missing-restore.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/controlled-operations/invalid-unknown-binding.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/controlled-operations/invalid-validated-without-runtime-observation.v0.1.json'
        ExpectedExitCode = 1
    },
    @{
        Path = 'tests/schema/fixtures/controlled-operations/invalid-numeric-write-without-range.v0.1.json'
        ExpectedExitCode = 1
    }
)

$failed = $false
foreach ($case in $cases) {
    $operationPath = Join-Path $repositoryRoot $case.Path
    $validatorOutput = & $powerShell -NoProfile -File $validator `
        -OperationPath $operationPath `
        -RuntimeBindingPath $runtimeBindings 2>&1
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
Write-Output "All $($cases.Count) controlled-operation validation tests passed."
exit 0
