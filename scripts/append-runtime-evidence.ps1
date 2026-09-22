[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EventJson,

    [ValidatePattern('^\d{8}T\d{6}(?:\.\d{1,7})?Z$')]
    [string]$Timestamp = (Get-Date).ToUniversalTime().ToString(
        'yyyyMMddTHHmmss.fffffffZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($EventJson.IndexOfAny([char[]]@("`r", "`n")) -ge 0) {
    throw 'Runtime evidence must be exactly one JSON line.'
}
$trimmedEventJson = $EventJson.Trim()
if (-not $trimmedEventJson.StartsWith('{') -or
    -not $trimmedEventJson.EndsWith('}')) {
    throw 'Runtime evidence must be a structured JSON object.'
}
try {
    $parsed = $EventJson | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Runtime evidence is not valid JSON. $($_.Exception.Message)"
}
if ($null -eq $parsed -or $parsed -isnot [PSCustomObject]) {
    throw 'Runtime evidence must be a structured JSON object.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$evidenceDirectory = Join-Path $repositoryRoot (
    Join-Path 'cases' (
        Join-Path $CaseId (
            Join-Path 'raw/runtime' $Timestamp
        )
    )
)
$eventsPath = Join-Path $evidenceDirectory 'events.jsonl'

$null = New-Item -ItemType Directory -Path $evidenceDirectory -Force
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::AppendAllText(
    $eventsPath,
    $EventJson + [Environment]::NewLine,
    $utf8WithoutBom
)

return $eventsPath
