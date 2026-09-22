[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$activeSuites = @(
    'models.tests.ps1'
    'twincat-runtime.tests.ps1'
    'privacy.tests.ps1'
)
foreach ($suite in $activeSuites) {
    & (Join-Path $PSScriptRoot $suite)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

exit 0
