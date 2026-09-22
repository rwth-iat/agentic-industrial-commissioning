[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $failures.Add($Message)
}

Push-Location $repositoryRoot
try {
    foreach ($privatePath in @(
        'creds/privacy-probe.local.psd1'
        'cases/privacy-probe/raw/evidence.jsonl'
        'cases/privacy-probe/derived/private/software-model.json'
        'cases/privacy-probe/results/private/result.json'
        'cases/privacy-probe/validation/private/check.json'
    )) {
        $null = & git check-ignore --no-index -- $privatePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "Private path is not ignored: $privatePath"
        }
    }

    $publicExamples = @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'examples') -Recurse -File)
    $ipv4Pattern = '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'
    $amsNetIdPattern = '(?<![\d.])(?:\d{1,3}\.){5}\d{1,3}(?![\d.])'
    foreach ($example in $publicExamples) {
        $content = Get-Content -LiteralPath $example.FullName -Raw
        if ($content -match $ipv4Pattern) {
            Add-Failure "Public example contains a concrete IPv4 host: $($example.FullName)"
        }
        if ($content -match $amsNetIdPattern) {
            Add-Failure "Public example contains a concrete AMS Net ID: $($example.FullName)"
        }
    }

    $trackedFiles = @(& git ls-files | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and
        (Test-Path -LiteralPath (Join-Path $repositoryRoot $_) -PathType Leaf)
    })
    foreach ($trackedFile in $trackedFiles) {
        if ([IO.Path]::GetExtension($trackedFile) -match '^\.(key|pem|p12|pfx|ovpn|rdp)$') {
            Add-Failure "Tracked credential or private-access file: $trackedFile"
        }
    }

    $keyBlockMarkerPattern = '-----BEGIN ' + '(?:RSA |OPENSSH |EC )?' + 'PRIVATE KEY-----'
    foreach ($trackedFile in $trackedFiles) {
        $extension = [IO.Path]::GetExtension($trackedFile)
        if ($extension -notin @('.json', '.psd1', '.ps1', '.yaml', '.yml', '.toml', '.env', '.txt', '.md')) {
            continue
        }
        $content = Get-Content -LiteralPath (Join-Path $repositoryRoot $trackedFile) -Raw
        if ($content -match $keyBlockMarkerPattern) {
            Add-Failure "Tracked file contains a private-key block: $trackedFile"
        }
        if ($extension -in @('.json', '.psd1', '.yaml', '.yml', '.toml', '.env') -and
            $content -match '(?im)^\s*["'']?(?:password|secret|api[_-]?key|private[_-]?key)["'']?\s*[:=]\s*["'']?(?!<|\$|REDACTED|CHANGEME)([^\s,"'']+)') {
            Add-Failure "Tracked configuration appears to contain a credential value: $trackedFile"
        }
        if ($extension -eq '.ps1' -and
            $content -match '(?im)^\s*\$(?:password|secret|api[_-]?key|private[_-]?key)\s*=\s*["''](?!<|\$|REDACTED|CHANGEME)([^"'']+)["'']') {
            Add-Failure "Tracked PowerShell appears to contain a hard-coded credential: $trackedFile"
        }
    }
}
finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "FAIL $failure" }
    exit 1
}

Write-Output 'Minimal privacy checks passed.'
exit 0
