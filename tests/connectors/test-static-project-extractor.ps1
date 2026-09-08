[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

python -m unittest discover -s (Join-Path $PSScriptRoot '.') -p 'test_*.py' -v
exit $LASTEXITCODE
