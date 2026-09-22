[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DocumentPath,

    [Parameter(Mandatory = $true)]
    [string]$SchemaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedDocumentPath = (Resolve-Path -LiteralPath $DocumentPath).Path
$resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path
$rawDocument = Get-Content -Raw -LiteralPath $resolvedDocumentPath

try {
    $valid = Test-Json -Json $rawDocument -SchemaFile $resolvedSchemaPath -ErrorAction SilentlyContinue
}
catch {
    Write-Output "JSON Schema validation failed: $($_.Exception.Message)"
    exit 1
}

if (-not $valid) {
    Write-Output 'document does not conform to the JSON Schema'
    exit 1
}

exit 0
