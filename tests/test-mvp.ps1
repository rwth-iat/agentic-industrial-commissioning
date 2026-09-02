[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'schema/test-hardware-model.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'core/test-core.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0
