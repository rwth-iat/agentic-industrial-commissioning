[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'capabilities/twincat/ads/test-recipes.ps1')
exit $LASTEXITCODE
