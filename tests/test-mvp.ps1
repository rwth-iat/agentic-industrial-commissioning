[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Backward-compatible entry point. New documentation uses test-offline-core.ps1.
& (Join-Path $PSScriptRoot 'test-offline-core.ps1')
exit $LASTEXITCODE
