[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]] $InputPath,

    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$env:PYTHONPATH = Join-Path $repositoryRoot 'src'
$env:PYTHONDONTWRITEBYTECODE = '1'
$modelOutput = Join-Path $OutputDirectory 'canonical-hardware-model.v0.2.json'
$reportOutput = Join-Path $OutputDirectory 'matching-report.json'

$pipelineArguments = @(
    '-m', 'commissioning_core.pipeline',
    '--model-out', $modelOutput,
    '--report-out', $reportOutput
)
foreach ($path in $InputPath) {
    $pipelineArguments += @('--input', $path)
}

python @pipelineArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot 'validate-hardware-model.ps1') -ModelPath $modelOutput
exit $LASTEXITCODE
