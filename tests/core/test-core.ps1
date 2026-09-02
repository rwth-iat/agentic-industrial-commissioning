[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$env:PYTHONPATH = Join-Path $repositoryRoot 'src'
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s (Join-Path $PSScriptRoot '.') -p 'test_*.py' -v
exit $LASTEXITCODE
