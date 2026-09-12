[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate-commissioning-record.ps1'
$resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
$powerShell = (Get-Process -Id $PID).Path

$validationOutput = @(& $powerShell -NoProfile -File $validator -RecordPath $resolvedInputPath -SkipPlacement 2>&1)
if ($LASTEXITCODE -ne 0) {
    $validationDetail = ($validationOutput | ForEach-Object { $_ | Out-String -Width 4096 }).Trim() -join [Environment]::NewLine
    throw "Commissioning record is invalid:`n$validationDetail"
}

$document = Get-Content -Raw -LiteralPath $resolvedInputPath | ConvertFrom-Json
$caseId = [string]$document.case_id
$runId = [string]$document.run_id
switch ([string]$document.record_type) {
    'run_manifest' {
        $targetPath = Join-Path $repositoryRoot "cases/$caseId/validation/private/$runId/run-manifest.json"
    }
    'preflight' {
        $targetPath = Join-Path $repositoryRoot "cases/$caseId/validation/private/$runId/preflight.json"
    }
    'execution_record' {
        $targetPath = Join-Path $repositoryRoot "cases/$caseId/results/private/probes/$runId/execution-record.json"
    }
    default {
        throw "Unsupported commissioning record type '$($document.record_type)'."
    }
}

$canonicalJson = $document | ConvertTo-Json -Depth 100
if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
    $existing = Get-Content -Raw -LiteralPath $targetPath | ConvertFrom-Json | ConvertTo-Json -Depth 100
    if ($existing -eq $canonicalJson) {
        Write-Output $targetPath
        exit 0
    }
    throw "Refusing to overwrite different commissioning evidence at '$targetPath'. Use a new run_id."
}

$targetDirectory = Split-Path -Parent $targetPath
$null = New-Item -ItemType Directory -Path $targetDirectory -Force
$temporaryPath = Join-Path $targetDirectory ".$([IO.Path]::GetFileName($targetPath)).$([guid]::NewGuid().ToString('N')).tmp"
try {
    Set-Content -LiteralPath $temporaryPath -Value $canonicalJson -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $targetPath
    $validationOutput = @(& $powerShell -NoProfile -File $validator -RecordPath $targetPath 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $targetPath -Force
        throw "Written commissioning record failed placement validation: $($validationOutput -join '; ')"
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

Write-Output $targetPath
exit 0
