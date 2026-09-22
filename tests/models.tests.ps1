[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$expectedSchemas = @(
    'hardware-model.schema.json'
    'implementation-link.schema.json'
    'runtime-binding.schema.json'
    'software-model.schema.json'
)
$actualSchemas = @(
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'spec') -File -Filter '*.schema.json' |
        Select-Object -ExpandProperty Name |
        Sort-Object
)

if (($actualSchemas -join ',') -cne (($expectedSchemas | Sort-Object) -join ',')) {
    throw "Active schemas are [$($actualSchemas -join ', ')] instead of exactly the four knowledge contracts."
}

foreach ($schemaName in $expectedSchemas) {
    $schemaPath = Join-Path $repositoryRoot "spec/$schemaName"
    try {
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Schema '$schemaName' is not valid JSON: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$schema.'$schema') -or
        [string]::IsNullOrWhiteSpace([string]$schema.'$id')) {
        throw "Schema '$schemaName' does not declare both `$schema and `$id."
    }
}

$modelSuites = @(
    'schema/test-hardware-model.ps1'
    'schema/test-software-model.ps1'
    'schema/test-implementation-links.ps1'
    'schema/test-runtime-bindings.ps1'
)
foreach ($suite in $modelSuites) {
    & (Join-Path $PSScriptRoot $suite)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Output 'Minimal model checks passed.'
exit 0
