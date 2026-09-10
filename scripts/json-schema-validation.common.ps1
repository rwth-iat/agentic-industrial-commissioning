Set-StrictMode -Version Latest

$script:JsonSchemaValidationRunner = Join-Path $PSScriptRoot 'test-json-schema.ps1'

function Resolve-PowerShell7Executable {
    $configuredPath = [Environment]::GetEnvironmentVariable('AIC_PWSH_PATH')
    if (-not [string]::IsNullOrWhiteSpace($configuredPath) -and
        (Test-Path -LiteralPath $configuredPath -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $configuredPath).Path
    }

    $command = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        return $command.Source
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates.Add((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates.Add((Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe'))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Test-JsonSchemaFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocumentPath,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    $resolvedDocumentPath = (Resolve-Path -LiteralPath $DocumentPath).Path
    $resolvedSchemaPath = (Resolve-Path -LiteralPath $SchemaPath).Path
    $testJsonCommand = Get-Command Test-Json -ErrorAction SilentlyContinue

    if ($null -ne $testJsonCommand) {
        try {
            $rawDocument = Get-Content -Raw -LiteralPath $resolvedDocumentPath
            $valid = Test-Json -Json $rawDocument -SchemaFile $resolvedSchemaPath -ErrorAction SilentlyContinue
            return [pscustomobject]@{
                Valid = [bool]$valid
                Engine = "Test-Json in PowerShell $($PSVersionTable.PSVersion)"
                Error = if ($valid) { $null } else { 'document does not conform to the JSON Schema' }
            }
        }
        catch {
            return [pscustomobject]@{
                Valid = $false
                Engine = "Test-Json in PowerShell $($PSVersionTable.PSVersion)"
                Error = $_.Exception.Message
            }
        }
    }

    $powerShell7 = Resolve-PowerShell7Executable
    if ([string]::IsNullOrWhiteSpace($powerShell7)) {
        return [pscustomobject]@{
            Valid = $false
            Engine = 'unavailable'
            Error = 'JSON Schema validation requires PowerShell 7. Set AIC_PWSH_PATH or install pwsh when Test-Json is unavailable.'
        }
    }

    try {
        $runnerOutput = @(& $powerShell7 -NoProfile -File $script:JsonSchemaValidationRunner `
            -DocumentPath $resolvedDocumentPath -SchemaPath $resolvedSchemaPath 2>&1)
        $runnerExitCode = $LASTEXITCODE
        return [pscustomobject]@{
            Valid = $runnerExitCode -eq 0
            Engine = "Test-Json via $powerShell7"
            Error = if ($runnerExitCode -eq 0) { $null } else { ($runnerOutput -join '; ') }
        }
    }
    catch {
        return [pscustomobject]@{
            Valid = $false
            Engine = "Test-Json via $powerShell7"
            Error = $_.Exception.Message
        }
    }
}
