[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'capabilities/twincat/ads/test-recipes.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot 'capabilities/twincat/ads/test-supervised-probe.ps1')
exit $LASTEXITCODE
