[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CaseId,
    [Parameter(Mandatory = $true)][string]$AssetId,
    [Parameter(Mandatory = $true)][string]$RequestedInterface,
    [Parameter(Mandatory = $true)][string]$ConnectionProfile,
    [Parameter(Mandatory = $true)][string]$HardwareModelPath,
    [Parameter(Mandatory = $true)][string]$SoftwareModelPath,
    [Parameter(Mandatory = $true)][string]$ImplementationLinksPath,
    [Parameter(Mandatory = $true)][string]$RuntimeBindingsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$writer = Join-Path $PSScriptRoot 'write-commissioning-record.ps1'
$powerShell = (Get-Process -Id $PID).Path

function Get-InputRevision {
    param([string]$Kind, [string]$Path)
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $prefix = $repositoryRoot
    if (-not $prefix.EndsWith([string][IO.Path]::DirectorySeparatorChar)) {
        $prefix += [IO.Path]::DirectorySeparatorChar
    }
    if (-not $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Commissioning input must be inside the repository: $resolvedPath"
    }
    return [ordered]@{
        kind = $Kind
        path = $resolvedPath.Substring($prefix.Length).Replace('\', '/')
        revision = "sha256:$((Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash.ToLowerInvariant())"
    }
}

$repositoryRevision = [string](& git -C $repositoryRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRevision)) {
    throw 'Could not determine repository revision.'
}
$repositoryRevision = $repositoryRevision.Trim()
$trackedChanges = @(& git -C $repositoryRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not determine repository worktree state.'
}
if ($trackedChanges.Count -gt 0) {
    $repositoryRevision += '-dirty'
}

$now = [DateTimeOffset]::UtcNow
$runId = "run-$($now.ToString('yyyyMMddTHHmmssfffZ'))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$document = [ordered]@{
    schema_version = '0.1.0'
    record_type = 'run_manifest'
    run_id = $runId
    case_id = $CaseId
    asset_id = $AssetId
    requested_interface = $RequestedInterface
    created_at = $now.ToString('o')
    data_classification = 'private'
    repository_revision = $repositoryRevision
    connection_profile = $ConnectionProfile
    input_contracts = @(
        Get-InputRevision -Kind 'hardware_model' -Path $HardwareModelPath
        Get-InputRevision -Kind 'software_model' -Path $SoftwareModelPath
        Get-InputRevision -Kind 'implementation_links' -Path $ImplementationLinksPath
        Get-InputRevision -Kind 'runtime_bindings' -Path $RuntimeBindingsPath
    )
    safety_boundary = [ordered]@{
        mode = 'read_only_preflight'
        state_changes_authorized = $false
    }
}

$candidatePath = [IO.Path]::GetTempFileName()
try {
    $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $candidatePath -Encoding utf8
    $writerOutput = @(& $powerShell -NoProfile -File $writer -InputPath $candidatePath 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not persist run manifest: $($writerOutput -join '; ')"
    }
    Write-Output ([string]$writerOutput[-1])
}
finally {
    if (Test-Path -LiteralPath $candidatePath) {
        Remove-Item -LiteralPath $candidatePath -Force
    }
}
