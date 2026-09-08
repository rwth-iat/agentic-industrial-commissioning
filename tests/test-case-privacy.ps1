[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$privatePaths = @(
    'cases/privacy-probe/raw/evidence.bin',
    'cases/privacy-probe/derived/private/software-model.json',
    'cases/privacy-probe/results/private/report.json',
    'cases/privacy-probe/validation/private/acceptance.json'
)
$publicPaths = @(
    'examples/software-models/process-cell.synthetic.v0.1.json',
    'examples/implementation-links/process-cell.synthetic.v0.1.json',
    'tests/schema/fixtures/software-models/cases.json'
)

Push-Location $repositoryRoot
try {
    foreach ($path in $privatePaths) {
        $null = & git check-ignore --no-index -- $path 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Output "FAIL expected ignored path: $path"
            exit 1
        }
        Write-Output "PASS ignored private path: $path"
    }
    foreach ($path in $publicPaths) {
        $null = & git check-ignore --no-index -- $path 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Output "FAIL expected public path: $path"
            exit 1
        }
        Write-Output "PASS visible public path: $path"
    }
}
finally {
    Pop-Location
}

Write-Output 'Case privacy policy checks passed.'
exit 0
