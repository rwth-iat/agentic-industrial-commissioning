[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repositoryRoot 'scripts/validate-implementation-links.ps1'
$baseLinkPath = Join-Path $repositoryRoot 'examples/implementation-links/process-cell.synthetic.v0.1.json'
$baseSoftwarePath = Join-Path $repositoryRoot 'examples/software-models/process-cell.synthetic.v0.1.json'
$baseHardwarePath = Join-Path $repositoryRoot 'examples/hardware-models/process-cell.synthetic.v0.2.json'
$casePath = Join-Path $repositoryRoot 'tests/schema/fixtures/implementation-links/cases.json'
$powerShell = Join-Path $PSHOME 'pwsh.exe'
$tempRoot = Join-Path $repositoryRoot "tmp/implementation-link-schema-$([guid]::NewGuid().ToString('N'))"
$privateCaseRoot = Join-Path $repositoryRoot "cases/privacy-contract-$([guid]::NewGuid().ToString('N'))"
$privateTempRoot = Join-Path $privateCaseRoot 'derived/private'
$null = New-Item -ItemType Directory -Path $tempRoot -Force
$null = New-Item -ItemType Directory -Path $privateTempRoot -Force

try {
    $baseLinkRaw = Get-Content -Raw -LiteralPath $baseLinkPath
    $baseHardwareRaw = Get-Content -Raw -LiteralPath $baseHardwarePath
    $cases = @(Get-Content -Raw -LiteralPath $casePath | ConvertFrom-Json)
    $failed = $false

    foreach ($case in $cases) {
        $document = $baseLinkRaw | ConvertFrom-Json
        $hardware = $baseHardwareRaw | ConvertFrom-Json
        $usePrivatePath = $false
        switch ([string]$case.mutation) {
            'none' { }
            'classify-private-correctly' {
                $document.data_classification = 'private'
                $usePrivatePath = $true
            }
            'set-dangling-component-asset' {
                $document.links[0].hardware.component_asset_id = 'missing-asset'
            }
            'set-port-from-another-asset' {
                $document.links[0].hardware.endpoint.port_id = 'measurement-output'
            }
            'set-cross-asset-component' {
                $document.links[0].hardware.component_asset_id = 'demo-flow-sensor'
            }
            'set-dangling-signal' {
                $document.links[0].software.signal_id = 'missing-signal'
            }
            'set-static-link-validated' {
                $document.links[0].status = 'validated'
            }
            'set-direction-mismatch' {
                $hardware.assets[2].ports[0].direction = 'input'
            }
            'classify-private-outside-case-private' {
                $document.data_classification = 'private'
            }
            'reference-case-raw-model' {
                $document.hardware_model.model_ref = 'cases/private-plant/raw/hardware.json'
                $document.sources[0].locator = 'cases/private-plant/raw/hardware.json'
            }
            'set-wrong-software-model-id' {
                $document.software_model.id = 'different-software-model'
            }
            'set-wrong-hardware-system-id' {
                $document.hardware_model.system_id = 'different-system'
            }
            default { throw "Unknown mutation '$($case.mutation)'" }
        }

        $outputRoot = if ($usePrivatePath) { $privateTempRoot } else { $tempRoot }
        $documentPath = Join-Path $outputRoot "$($case.name).links.json"
        $hardwarePath = Join-Path $tempRoot "$($case.name).hardware.json"
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $documentPath -Encoding utf8
        $hardware | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $hardwarePath -Encoding utf8
        $validatorOutput = & $powerShell -NoProfile -File $validator `
            -LinkPath $documentPath `
            -SoftwareModelPath $baseSoftwarePath `
            -HardwareModelPath $hardwarePath 2>&1
        $actualExitCode = $LASTEXITCODE
        if ($actualExitCode -eq [int]$case.expected_exit_code) {
            Write-Output "PASS $($case.name) (exit ${actualExitCode})"
        }
        else {
            $failed = $true
            Write-Output "FAIL $($case.name): expected exit $($case.expected_exit_code), got ${actualExitCode}"
            $validatorOutput | ForEach-Object { Write-Output "  $_" }
        }
    }

    if ($failed) { exit 1 }
    Write-Output "All $($cases.Count) implementation-link validation tests passed."
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $privateCaseRoot) {
        Remove-Item -LiteralPath $privateCaseRoot -Recurse -Force
    }
}
