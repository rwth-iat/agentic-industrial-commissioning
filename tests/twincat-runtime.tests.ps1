[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'capabilities/twincat/test-runtime-module.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output 'Minimal TwinCAT runtime checks passed.'
exit 0
