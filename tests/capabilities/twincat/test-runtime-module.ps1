[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$modulePath = Join-Path $repositoryRoot 'capabilities/twincat/Runtime.psm1'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $failures.Add($Message)
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $modulePath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    Add-Failure "Runtime.psm1 has $($parseErrors.Count) parse error(s)."
}

$module = Import-Module $modulePath -Force -PassThru
try {
    $exported = @($module.ExportedFunctions.Keys | Sort-Object)
    $expected = @('Read-Binding', 'Write-Binding')
    if (($exported -join ',') -cne ($expected -join ',')) {
        Add-Failure "Runtime exports [$($exported -join ', ')] instead of exactly READ and WRITE."
    }

    $readCommand = Get-Command Read-Binding -Module $module.Name
    $writeCommand = Get-Command Write-Binding -Module $module.Name
    foreach ($name in @('RuntimeBindingsPath', 'BindingId')) {
        if (-not $readCommand.Parameters.ContainsKey($name) -or
            -not @($readCommand.Parameters[$name].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }).Count) {
            Add-Failure "Read-Binding requires mandatory parameter '$name'."
        }
        if (-not $writeCommand.Parameters.ContainsKey($name) -or
            -not @($writeCommand.Parameters[$name].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }).Count) {
            Add-Failure "Write-Binding requires mandatory parameter '$name'."
        }
    }
    if (-not $writeCommand.Parameters.ContainsKey('Value') -or
        -not @($writeCommand.Parameters.Value.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
        }).Count) {
        Add-Failure "Write-Binding requires mandatory parameter 'Value'."
    }
    if (-not $writeCommand.Parameters.ContainsKey('Mode') -or
        -not @($writeCommand.Parameters.Mode.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
        }).Count) {
        Add-Failure "Write-Binding requires mandatory parameter 'Mode'."
    }
    if (-not $writeCommand.Parameters.ContainsKey('PulseDurationMilliseconds')) {
        Add-Failure "Write-Binding does not expose optional parameter 'PulseDurationMilliseconds'."
    }
    if ($writeCommand.Parameters.ContainsKey('HumanApproved')) {
        Add-Failure 'Write-Binding must not expose a pseudo-approval parameter.'
    }

    $privateHelpers = @(
        'Get-AicBridgeState',
        'Invoke-AicRemoteScript',
        'Read-AicRuntimeBindingDocument',
        'Get-AicSelectedBinding',
        'ConvertTo-AicAdsType',
        'ConvertTo-AicPrimitiveValue',
        'ConvertTo-AicInvariantText',
        'Assert-AicWriteConstraints',
        'Import-AicConnectionProfile',
        'Get-AicAdsReadSource',
        'Get-AicAdsWriteSource',
        'Get-AicAdsPulseWriteSource'
    )
    $privateNames = & $module {
        @(Get-Command Get-AicBridgeState, Invoke-AicRemoteScript,
            Read-AicRuntimeBindingDocument, Get-AicSelectedBinding,
            ConvertTo-AicAdsType, ConvertTo-AicPrimitiveValue,
            ConvertTo-AicInvariantText, Assert-AicWriteConstraints,
            Import-AicConnectionProfile, Get-AicAdsReadSource,
            Get-AicAdsWriteSource, Get-AicAdsPulseWriteSource -CommandType Function |
            Select-Object -ExpandProperty Name)
    }
    if (@($privateNames).Count -ne $privateHelpers.Count) {
        Add-Failure 'Runtime READ/WRITE helpers are missing from private module scope.'
    }
    foreach ($privateName in $privateHelpers) {
        if (Get-Command $privateName -ErrorAction SilentlyContinue) {
            Add-Failure "Private helper '$privateName' leaked into the public session."
        }
    }

    $missingBridgeMessage = & $module {
        $originalStateFile = $script:BridgeStateFile
        try {
            $script:BridgeStateFile = Join-Path ([IO.Path]::GetTempPath()) (
                'aic-missing-bridge-' + [guid]::NewGuid().ToString('N') + '.json'
            )
            try { Get-AicBridgeState } catch { $_.Exception.Message }
        }
        finally {
            $script:BridgeStateFile = $originalStateFile
        }
    }
    if ($missingBridgeMessage -cne 'Runtime access unavailable: remote session is not active.') {
        Add-Failure 'Missing bridge does not produce the required concrete technical error.'
    }

    $testId = [guid]::NewGuid().ToString('N')
    $portFile = Join-Path ([IO.Path]::GetTempPath()) "aic-runtime-port-$testId.txt"
    $stateFile = Join-Path ([IO.Path]::GetTempPath()) "aic-runtime-state-$testId.json"
    $testToken = 'phase4-test-token'
    $serverJob = Start-Job -ArgumentList $portFile, $testToken -ScriptBlock {
        param($PortFile, $ExpectedToken)

        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Loopback,
            0
        )
        $listener.Start()
        $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
        [IO.File]::WriteAllText($PortFile, [string]$port)

        $client = $listener.AcceptTcpClient()
        $reader = $null
        $writer = $null
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
            $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
            $writer.AutoFlush = $true
            $request = $reader.ReadLine() | ConvertFrom-Json
            $source = [Text.Encoding]::UTF8.GetString(
                [Convert]::FromBase64String([string]$request.code)
            )
            $valid = (
                [string]$request.token -ceq $ExpectedToken -and
                $source -ceq "'PHASE4_REMOTE_OK'" -and
                [string]$request.arguments.Name -ceq 'value'
            )
            $writer.WriteLine((
                [PSCustomObject]@{
                    success = $valid
                    output  = $(if ($valid) { 'PHASE4_REMOTE_OK' } else { '' })
                    error   = $(if ($valid) { '' } else { 'Unexpected request.' })
                } | ConvertTo-Json -Compress
            ))
        }
        finally {
            if ($null -ne $reader) { $reader.Dispose() }
            if ($null -ne $writer) { $writer.Dispose() }
            $client.Close()
            $listener.Stop()
        }
    }
    try {
        $deadline = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $portFile) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $portFile)) {
            Add-Failure 'Loopback test bridge did not publish a port.'
        }
        else {
            $state = [PSCustomObject]@{
                schemaVersion = 1
                host          = '127.0.0.1'
                port          = [int](Get-Content -Raw -LiteralPath $portFile)
                token         = $testToken
            }
            $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
            $transportOutput = & $module {
                param($TestStateFile)
                $originalStateFile = $script:BridgeStateFile
                try {
                    $script:BridgeStateFile = $TestStateFile
                    Invoke-AicRemoteScript -SourceCode "'PHASE4_REMOTE_OK'" -Arguments @{ Name = 'value' }
                }
                finally {
                    $script:BridgeStateFile = $originalStateFile
                }
            } $stateFile
            if ($transportOutput -cne 'PHASE4_REMOTE_OK') {
                Add-Failure 'Private runtime transport did not preserve the bridge protocol.'
            }
        }
        $null = Wait-Job -Job $serverJob -Timeout 10
        if ($serverJob.State -ne 'Completed') {
            Add-Failure "Loopback test bridge ended in state '$($serverJob.State)'."
        }
    }
    finally {
        if ($null -ne $serverJob -and $serverJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $serverJob
        }
        if ($null -ne $serverJob) { Remove-Job -Job $serverJob -Force }
        foreach ($path in @($portFile, $stateFile)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }

    $readTestId = [guid]::NewGuid().ToString('N')
    $readTestRoot = Join-Path ([IO.Path]::GetTempPath()) "aic-runtime-read-$readTestId"
    $readPortFile = Join-Path $readTestRoot 'port.txt'
    $readStateFile = Join-Path $readTestRoot 'state.json'
    $writePortFile = Join-Path $readTestRoot 'write-port.txt'
    $writeStateFile = Join-Path $readTestRoot 'write-state.json'
    $pulsePortFile = Join-Path $readTestRoot 'pulse-port.txt'
    $pulseStateFile = Join-Path $readTestRoot 'pulse-state.json'
    $bindingsFile = Join-Path $readTestRoot 'runtime-bindings.json'
    $profileFile = Join-Path $readTestRoot 'synthetic-read.local.psd1'
    $readToken = 'phase5-read-test-token'
    $readServerJob = $null
    $writeServerJob = $null
    $pulseServerJob = $null
    New-Item -ItemType Directory -Path $readTestRoot | Out-Null
    try {
        @'
@{
    Ads = @{
        NetId = '1.2.3.4.5.6'
        Port   = 851
        AdsDll = 'C:\Synthetic\TwinCAT.Ads.dll'
    }
}
'@ | Set-Content -LiteralPath $profileFile -Encoding UTF8

        [PSCustomObject]@{
            environment = [PSCustomObject]@{
                platform           = 'TwinCAT'
                connection_profile = 'synthetic-read'
            }
            bindings = @(
                [PSCustomObject]@{
                    id       = 'selected-binding'
                    access   = 'read'
                    datatype = 'BOOL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.Value'
                    }
                },
                [PSCustomObject]@{
                    id       = 'write-only-binding'
                    access   = 'write'
                    datatype = 'BOOL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.Command'
                    }
                },
                [PSCustomObject]@{
                    id       = 'unsupported-type-binding'
                    access   = 'read'
                    datatype = 'TIME'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.Timer'
                    }
                },
                [PSCustomObject]@{
                    id       = 'writable-setpoint'
                    access   = 'read_write'
                    datatype = 'REAL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.Setpoint'
                    }
                    interaction = [PSCustomObject]@{
                        semantics = 'setpoint'
                    }
                    write_constraints = [PSCustomObject]@{
                        minimum        = 0
                        maximum        = 100
                        allowed_values = @(25, 50, 75)
                    }
                },
                [PSCustomObject]@{
                    id       = 'unsupported-write-semantics'
                    access   = 'read_write'
                    datatype = 'BOOL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.Request'
                    }
                    interaction = [PSCustomObject]@{
                        semantics = 'request'
                    }
                    write_semantics = [PSCustomObject]@{
                        type = 'unsupported'
                    }
                },
                [PSCustomObject]@{
                    id       = 'pulse-binding'
                    access   = 'read_write'
                    datatype = 'BOOL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.Request'
                    }
                    interaction = [PSCustomObject]@{
                        semantics = 'request'
                    }
                },
                [PSCustomObject]@{
                    id       = 'pulse-real-binding'
                    access   = 'read_write'
                    datatype = 'REAL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.InvalidPulse'
                    }
                    interaction = [PSCustomObject]@{
                        semantics = 'request'
                    }
                    write_semantics = [PSCustomObject]@{
                        type        = 'pulse'
                        duration_ms = 100
                    }
                },
                [PSCustomObject]@{
                    id       = 'pulse-missing-duration'
                    access   = 'read_write'
                    datatype = 'BOOL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.MissingDuration'
                    }
                    interaction = [PSCustomObject]@{
                        semantics = 'request'
                    }
                    write_semantics = [PSCustomObject]@{
                        type = 'pulse'
                    }
                },
                [PSCustomObject]@{
                    id       = 'pulse-short-duration'
                    access   = 'read_write'
                    datatype = 'BOOL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.ShortPulse'
                    }
                    interaction = [PSCustomObject]@{
                        semantics = 'request'
                    }
                    write_semantics = [PSCustomObject]@{
                        type        = 'pulse'
                        duration_ms = 1
                    }
                },
                [PSCustomObject]@{
                    id       = 'level-with-duration'
                    access   = 'read_write'
                    datatype = 'REAL'
                    locator  = [PSCustomObject]@{
                        kind  = 'ads_symbol'
                        value = 'GVL_Synthetic.Level'
                    }
                    interaction = [PSCustomObject]@{
                        semantics = 'setpoint'
                    }
                    write_semantics = [PSCustomObject]@{
                        type        = 'level'
                        duration_ms = 100
                    }
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $bindingsFile -Encoding UTF8

        foreach ($errorCase in @(
            @{ Id = 'SELECTED-BINDING'; Pattern = 'not found' },
            @{ Id = 'write-only-binding'; Pattern = 'not readable' },
            @{ Id = 'unsupported-type-binding'; Pattern = 'Unsupported PLC datatype' }
        )) {
            try {
                & $module {
                    param($Root, $BindingsPath, $SelectedId)
                    $originalProfileRoot = $script:ConnectionProfileRoot
                    try {
                        $script:ConnectionProfileRoot = $Root
                        Read-Binding -RuntimeBindingsPath $BindingsPath -BindingId $SelectedId
                    }
                    finally {
                        $script:ConnectionProfileRoot = $originalProfileRoot
                    }
                } $readTestRoot $bindingsFile $errorCase.Id
                Add-Failure "Read-Binding accepted invalid selection '$($errorCase.Id)'."
            }
            catch {
                if ($_.Exception.Message -notmatch $errorCase.Pattern) {
                    Add-Failure "Read-Binding returned the wrong error for '$($errorCase.Id)'."
                }
            }
        }

        $missingProfileMessage = & $module {
            param($Root)
            $originalProfileRoot = $script:ConnectionProfileRoot
            try {
                $script:ConnectionProfileRoot = $Root
                try { Import-AicConnectionProfile -ProfileKey 'absent-profile' }
                catch { $_.Exception.Message }
            }
            finally {
                $script:ConnectionProfileRoot = $originalProfileRoot
            }
        } $readTestRoot
    if ($missingProfileMessage -notmatch 'Connection profile not found') {
        Add-Failure 'Missing connection profile does not produce an explicit error.'
    }

        $expectedAdsTypes = [ordered]@{
            BOOL  = 'Boolean'
            BYTE  = 'Byte'
            INT   = 'Int16'
            UINT  = 'UInt16'
            WORD  = 'UInt16'
            DINT  = 'Int32'
            UDINT = 'UInt32'
            DWORD = 'UInt32'
            REAL  = 'Single'
            LREAL = 'Double'
        }
        foreach ($plcType in $expectedAdsTypes.Keys) {
            $actualAdsType = & $module {
                param($Datatype)
                ConvertTo-AicAdsType -PlcDatatype $Datatype
            } $plcType
            if ([string]$actualAdsType -cne [string]$expectedAdsTypes[$plcType]) {
                Add-Failure "PLC datatype '$plcType' mapped to '$actualAdsType'."
            }
        }

        foreach ($writeErrorCase in @(
            @{ Id = 'SELECTED-BINDING'; Value = $true; Mode = 'level'; Pattern = 'not found' },
            @{ Id = 'selected-binding'; Value = $true; Mode = 'level'; Pattern = 'not writable' },
            @{ Id = 'writable-setpoint'; Value = 'not-a-number'; Mode = 'level'; Pattern = 'not convertible' },
            @{ Id = 'writable-setpoint'; Value = -1; Mode = 'level'; Pattern = 'outside the allowed range' },
            @{ Id = 'writable-setpoint'; Value = 40; Mode = 'level'; Pattern = 'not in the allowed value set' },
            @{ Id = 'pulse-binding'; Value = $false; Mode = 'pulse'; Duration = 100; Pattern = 'requires trigger value TRUE' },
            @{ Id = 'pulse-real-binding'; Value = 1; Mode = 'pulse'; Duration = 100; Pattern = 'requires PLC datatype BOOL' },
            @{ Id = 'pulse-missing-duration'; Value = $true; Mode = 'pulse'; Pattern = 'requires PulseDurationMilliseconds' },
            @{ Id = 'level-with-duration'; Value = 50; Mode = 'level'; Duration = 100; Pattern = 'must not specify PulseDurationMilliseconds' }
        )) {
            $hasDuration = $writeErrorCase.ContainsKey('Duration')
            $duration = if ($hasDuration) { $writeErrorCase.Duration } else { 0 }
            try {
                & $module {
                    param($Root, $BindingsPath, $SelectedId, $SelectedValue, $SelectedMode, $Duration, $HasDuration)
                    $originalProfileRoot = $script:ConnectionProfileRoot
                    try {
                        $script:ConnectionProfileRoot = $Root
                        $parameters = @{
                            RuntimeBindingsPath = $BindingsPath
                            BindingId = $SelectedId
                            Value = $SelectedValue
                            Mode = $SelectedMode
                        }
                        if ($HasDuration) { $parameters.PulseDurationMilliseconds = $Duration }
                        Write-Binding @parameters
                    }
                    finally {
                        $script:ConnectionProfileRoot = $originalProfileRoot
                    }
                } $readTestRoot $bindingsFile $writeErrorCase.Id $writeErrorCase.Value `
                    $writeErrorCase.Mode $duration $hasDuration
                Add-Failure "Write-Binding accepted invalid input for '$($writeErrorCase.Id)'."
            }
            catch {
                if ($_.Exception.Message -notmatch $writeErrorCase.Pattern) {
                    Add-Failure "Write-Binding returned the wrong error for '$($writeErrorCase.Id)': $($_.Exception.Message)"
                }
            }
        }

        $readServerJob = Start-Job -ArgumentList $readPortFile, $readToken -ScriptBlock {
            param($PortFile, $ExpectedToken)

            $listener = [System.Net.Sockets.TcpListener]::new(
                [System.Net.IPAddress]::Loopback,
                0
            )
            $listener.Start()
            $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
            [IO.File]::WriteAllText($PortFile, [string]$port)

            $client = $listener.AcceptTcpClient()
            $reader = $null
            $writer = $null
            try {
                $stream = $client.GetStream()
                $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
                $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
                $writer.AutoFlush = $true
                $request = $reader.ReadLine() | ConvertFrom-Json
                $source = [Text.Encoding]::UTF8.GetString(
                    [Convert]::FromBase64String([string]$request.code)
                )
                $valid = (
                    [string]$request.token -ceq $ExpectedToken -and
                    $source -match 'ReadSymbol' -and
                    $source -notmatch 'WriteSymbol' -and
                    [string]$request.arguments.Symbol -ceq 'GVL_Synthetic.Value' -and
                    [string]$request.arguments.Type -ceq 'Boolean' -and
                    [string]$request.arguments.NetId -ceq '1.2.3.4.5.6' -and
                    [int]$request.arguments.Port -eq 851 -and
                    [string]$request.arguments.AdsDll -ceq 'C:\Synthetic\TwinCAT.Ads.dll'
                )
                $observation = [PSCustomObject]@{
                    symbol      = 'GVL_Synthetic.Value'
                    type        = 'Boolean'
                    value       = $true
                    observed_at = '2026-09-17T12:00:00.0000000Z'
                    success     = $true
                } | ConvertTo-Json -Compress
                $writer.WriteLine((
                    [PSCustomObject]@{
                        success = $valid
                        output  = $(if ($valid) { $observation } else { '' })
                        error   = $(if ($valid) { '' } else { 'Unexpected READ request.' })
                    } | ConvertTo-Json -Compress
                ))
            }
            finally {
                if ($null -ne $reader) { $reader.Dispose() }
                if ($null -ne $writer) { $writer.Dispose() }
                $client.Close()
                $listener.Stop()
            }
        }

        $deadline = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $readPortFile) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $readPortFile)) {
            Add-Failure 'Phase-5 loopback bridge did not publish a port.'
        }
        else {
            [PSCustomObject]@{
                schemaVersion = 1
                host          = '127.0.0.1'
                port          = [int](Get-Content -Raw -LiteralPath $readPortFile)
                token         = $readToken
            } | ConvertTo-Json | Set-Content -LiteralPath $readStateFile -Encoding UTF8

            $readResult = & $module {
                param($Root, $StatePath, $BindingsPath)
                $originalProfileRoot = $script:ConnectionProfileRoot
                $originalStateFile = $script:BridgeStateFile
                try {
                    $script:ConnectionProfileRoot = $Root
                    $script:BridgeStateFile = $StatePath
                    Read-Binding -RuntimeBindingsPath $BindingsPath -BindingId 'selected-binding'
                }
                finally {
                    $script:ConnectionProfileRoot = $originalProfileRoot
                    $script:BridgeStateFile = $originalStateFile
                }
            } $readTestRoot $readStateFile $bindingsFile

            if ([string]$readResult.operation -cne 'read' -or
                [string]$readResult.binding_id -cne 'selected-binding' -or
                [string]$readResult.symbol -cne 'GVL_Synthetic.Value' -or
                [string]$readResult.datatype -cne 'BOOL' -or
                $readResult.value -ne $true -or
                [string]$readResult.observed_at -cne '2026-09-17T12:00:00.0000000Z' -or
                $readResult.success -ne $true) {
                Add-Failure "Read-Binding did not return the required structured observation: $($readResult | ConvertTo-Json -Depth 5 -Compress)"
            }
        }

        $null = Wait-Job -Job $readServerJob -Timeout 10
        if ($readServerJob.State -ne 'Completed') {
            Add-Failure "Phase-5 loopback bridge ended in state '$($readServerJob.State)'."
        }

        $writeServerJob = Start-Job -ArgumentList $writePortFile, $readToken -ScriptBlock {
            param($PortFile, $ExpectedToken)

            $listener = [System.Net.Sockets.TcpListener]::new(
                [System.Net.IPAddress]::Loopback,
                0
            )
            $listener.Start()
            $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
            [IO.File]::WriteAllText($PortFile, [string]$port)

            $client = $listener.AcceptTcpClient()
            $reader = $null
            $writer = $null
            try {
                $stream = $client.GetStream()
                $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
                $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
                $writer.AutoFlush = $true
                $request = $reader.ReadLine() | ConvertFrom-Json
                $source = [Text.Encoding]::UTF8.GetString(
                    [Convert]::FromBase64String([string]$request.code)
                )
                $valid = (
                    [string]$request.token -ceq $ExpectedToken -and
                    $source -match 'WriteSymbol' -and
                    $source -match 'ReadSymbol' -and
                    $source -match 'FindSymbol' -and
                    $source -notmatch 'HumanApproved' -and
                    [string]$request.arguments.Symbol -ceq 'GVL_Synthetic.Setpoint' -and
                    [string]$request.arguments.Type -ceq 'Single' -and
                    [string]$request.arguments.PlcDatatype -ceq 'REAL' -and
                    [string]$request.arguments.Value -ceq '50' -and
                    [string]$request.arguments.NetId -ceq '1.2.3.4.5.6' -and
                    [int]$request.arguments.Port -eq 851 -and
                    [string]$request.arguments.AdsDll -ceq 'C:\Synthetic\TwinCAT.Ads.dll'
                )
                $observation = [PSCustomObject]@{
                    symbol       = 'GVL_Synthetic.Setpoint'
                    type         = 'Single'
                    plc_datatype = 'REAL'
                    value        = 50.0
                    observed_at  = '2026-09-17T12:05:00.0000000Z'
                    success      = $true
                } | ConvertTo-Json -Compress
                $writer.WriteLine((
                    [PSCustomObject]@{
                        success = $valid
                        output  = $(if ($valid) { $observation } else { '' })
                        error   = $(if ($valid) { '' } else { 'Unexpected WRITE request.' })
                    } | ConvertTo-Json -Compress
                ))
            }
            finally {
                if ($null -ne $reader) { $reader.Dispose() }
                if ($null -ne $writer) { $writer.Dispose() }
                $client.Close()
                $listener.Stop()
            }
        }

        $deadline = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $writePortFile) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $writePortFile)) {
            Add-Failure 'Phase-6 loopback bridge did not publish a port.'
        }
        else {
            [PSCustomObject]@{
                schemaVersion = 1
                host          = '127.0.0.1'
                port          = [int](Get-Content -Raw -LiteralPath $writePortFile)
                token         = $readToken
            } | ConvertTo-Json | Set-Content -LiteralPath $writeStateFile -Encoding UTF8

            $writeResult = & $module {
                param($Root, $StatePath, $BindingsPath)
                $originalProfileRoot = $script:ConnectionProfileRoot
                $originalStateFile = $script:BridgeStateFile
                try {
                    $script:ConnectionProfileRoot = $Root
                    $script:BridgeStateFile = $StatePath
                    Write-Binding `
                        -RuntimeBindingsPath $BindingsPath `
                        -BindingId 'writable-setpoint' `
                        -Value 50 `
                        -Mode level
                }
                finally {
                    $script:ConnectionProfileRoot = $originalProfileRoot
                    $script:BridgeStateFile = $originalStateFile
                }
            } $readTestRoot $writeStateFile $bindingsFile

            if ([string]$writeResult.operation -cne 'write' -or
                [string]$writeResult.binding_id -cne 'writable-setpoint' -or
                [string]$writeResult.symbol -cne 'GVL_Synthetic.Setpoint' -or
                [string]$writeResult.datatype -cne 'REAL' -or
                [string]$writeResult.semantics -cne 'level' -or
                [single]$writeResult.requested_value -ne [single]50 -or
                [single]$writeResult.value -ne [single]50 -or
                [string]$writeResult.observed_at -cne '2026-09-17T12:05:00.0000000Z' -or
                $writeResult.success -ne $true) {
                Add-Failure "Write-Binding did not return the required structured readback: $($writeResult | ConvertTo-Json -Depth 5 -Compress)"
            }
        }

        $null = Wait-Job -Job $writeServerJob -Timeout 10
        if ($writeServerJob.State -ne 'Completed') {
            Add-Failure "Phase-6 loopback bridge ended in state '$($writeServerJob.State)'."
        }

        $pulseServerJob = Start-Job -ArgumentList $pulsePortFile, $readToken -ScriptBlock {
            param($PortFile, $ExpectedToken)

            $listener = [System.Net.Sockets.TcpListener]::new(
                [System.Net.IPAddress]::Loopback,
                0
            )
            $listener.Start()
            $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
            [IO.File]::WriteAllText($PortFile, [string]$port)

            $client = $listener.AcceptTcpClient()
            $reader = $null
            $writer = $null
            try {
                $stream = $client.GetStream()
                $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
                $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
                $writer.AutoFlush = $true
                $request = $reader.ReadLine() | ConvertFrom-Json
                $source = [Text.Encoding]::UTF8.GetString(
                    [Convert]::FromBase64String([string]$request.code)
                )
                $valid = (
                    [string]$request.token -ceq $ExpectedToken -and
                    $source -match 'Start-Sleep' -and
                    $source -match '(?s)\$raised\s*=\s*\$true.*WriteSymbol\(\$Symbol, \$true' -and
                    $source -match 'WriteSymbol\(\$Symbol, \$true' -and
                    $source -match '(?s)finally\s*\{.*WriteSymbol\(\$Symbol, \$false' -and
                    $source -notmatch 'Acknowledgement' -and
                    [string]$request.arguments.Symbol -ceq 'GVL_Synthetic.Request' -and
                    [int]$request.arguments.DurationMilliseconds -eq 100 -and
                    [string]$request.arguments.NetId -ceq '1.2.3.4.5.6' -and
                    [int]$request.arguments.Port -eq 851 -and
                    [string]$request.arguments.AdsDll -ceq 'C:\Synthetic\TwinCAT.Ads.dll'
                )
                $observation = [PSCustomObject]@{
                    symbol        = 'GVL_Synthetic.Request'
                    type          = 'Boolean'
                    plc_datatype  = 'BOOL'
                    initial_value = $false
                    value         = $false
                    duration_ms   = 100
                    reset         = $true
                    observed_at   = '2026-09-17T12:10:00.0000000Z'
                    success       = $true
                } | ConvertTo-Json -Compress
                $writer.WriteLine((
                    [PSCustomObject]@{
                        success = $valid
                        output  = $(if ($valid) { $observation } else { '' })
                        error   = $(if ($valid) { '' } else { 'Unexpected PULSE request.' })
                    } | ConvertTo-Json -Compress
                ))
            }
            finally {
                if ($null -ne $reader) { $reader.Dispose() }
                if ($null -ne $writer) { $writer.Dispose() }
                $client.Close()
                $listener.Stop()
            }
        }

        $deadline = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $pulsePortFile) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $pulsePortFile)) {
            Add-Failure 'Phase-7 loopback bridge did not publish a port.'
        }
        else {
            [PSCustomObject]@{
                schemaVersion = 1
                host          = '127.0.0.1'
                port          = [int](Get-Content -Raw -LiteralPath $pulsePortFile)
                token         = $readToken
            } | ConvertTo-Json | Set-Content -LiteralPath $pulseStateFile -Encoding UTF8

            $pulseResult = & $module {
                param($Root, $StatePath, $BindingsPath)
                $originalProfileRoot = $script:ConnectionProfileRoot
                $originalStateFile = $script:BridgeStateFile
                try {
                    $script:ConnectionProfileRoot = $Root
                    $script:BridgeStateFile = $StatePath
                    Write-Binding `
                        -RuntimeBindingsPath $BindingsPath `
                        -BindingId 'pulse-binding' `
                        -Value $true `
                        -Mode pulse `
                        -PulseDurationMilliseconds 100
                }
                finally {
                    $script:ConnectionProfileRoot = $originalProfileRoot
                    $script:BridgeStateFile = $originalStateFile
                }
            } $readTestRoot $pulseStateFile $bindingsFile

            if ([string]$pulseResult.operation -cne 'write' -or
                [string]$pulseResult.binding_id -cne 'pulse-binding' -or
                [string]$pulseResult.semantics -cne 'pulse' -or
                $pulseResult.requested_value -ne $true -or
                $pulseResult.initial_value -ne $false -or
                $pulseResult.value -ne $false -or
                [int]$pulseResult.duration_ms -ne 100 -or
                $pulseResult.reset -ne $true -or
                $pulseResult.success -ne $true) {
                Add-Failure "Write-Binding did not return the required pulse reset result: $($pulseResult | ConvertTo-Json -Depth 5 -Compress)"
            }
        }

        $null = Wait-Job -Job $pulseServerJob -Timeout 10
        if ($pulseServerJob.State -ne 'Completed') {
            Add-Failure "Phase-7 loopback bridge ended in state '$($pulseServerJob.State)'."
        }
    }
    finally {
        if ($null -ne $readServerJob -and
            $readServerJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $readServerJob
        }
        if ($null -ne $readServerJob) { Remove-Job -Job $readServerJob -Force }
        if ($null -ne $writeServerJob -and
            $writeServerJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $writeServerJob
        }
        if ($null -ne $writeServerJob) { Remove-Job -Job $writeServerJob -Force }
        if ($null -ne $pulseServerJob -and
            $pulseServerJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $pulseServerJob
        }
        if ($null -ne $pulseServerJob) { Remove-Job -Job $pulseServerJob -Force }
        foreach ($path in @(
            $readPortFile,
            $readStateFile,
            $writePortFile,
            $writeStateFile,
            $pulsePortFile,
            $pulseStateFile,
            $bindingsFile,
            $profileFile
        )) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        if (Test-Path -LiteralPath $readTestRoot) {
            Remove-Item -LiteralPath $readTestRoot -Force
        }
    }

    $source = Get-Content -LiteralPath $modulePath -Raw
    foreach ($requiredMechanism in @(
        '127.0.0.1', 'schemaVersion', 'session token', 'TcpClient',
        'ToBase64String', 'ConvertTo-Json -Depth 20'
    )) {
        if ($source -notmatch [regex]::Escape($requiredMechanism)) {
            Add-Failure "Runtime transport is missing '$requiredMechanism'."
        }
    }
    if ($source -match '(?i)\bY\d+\b|\bF\d+\b|\bT\d+\b') {
        Add-Failure 'Runtime module contains a component identifier.'
    }
    if ($source -match '(?i)requested_interface|asset_id|component_id|user goal') {
        Add-Failure 'Runtime module contains semantic binding-selection inputs.'
    }
    $readSource = & $module { Get-AicAdsReadSource }
    $writeSource = & $module { Get-AicAdsWriteSource }
    $pulseSource = & $module { Get-AicAdsPulseWriteSource }
    foreach ($remoteSourceCase in @(
        @{ Name = 'READ'; Source = $readSource },
        @{ Name = 'level WRITE'; Source = $writeSource },
        @{ Name = 'pulse WRITE'; Source = $pulseSource }
    )) {
        try {
            [void][scriptblock]::Create([string]$remoteSourceCase.Source)
        }
        catch {
            Add-Failure "$($remoteSourceCase.Name) remote source does not parse: $($_.Exception.Message)"
        }
    }
    if ($readSource -notmatch 'ReadSymbol' -or $readSource -match 'WriteSymbol') {
        Add-Failure 'Phase-5 runtime source is not a strictly read-only ADS path.'
    }
    if ($writeSource -notmatch 'WriteSymbol' -or
        $writeSource -notmatch 'ReadSymbol' -or
        $writeSource -notmatch 'FindSymbol' -or
        $writeSource -match 'HumanApproved') {
        Add-Failure 'Phase-6 runtime source does not preserve the minimal guarded WRITE path.'
    }
    if ($pulseSource -notmatch 'ReadSymbol' -or
        $pulseSource -notmatch 'Start-Sleep' -or
        $pulseSource -notmatch '(?s)\$raised\s*=\s*\$true.*WriteSymbol\(\$Symbol, \$true' -or
        $pulseSource -notmatch 'WriteSymbol\(\$Symbol, \$true' -or
        $pulseSource -notmatch '(?s)finally\s*\{.*WriteSymbol\(\$Symbol, \$false' -or
        $pulseSource -match 'Acknowledgement') {
        Add-Failure 'Phase-7 pulse source does not guarantee technical reset without feedback orchestration.'
    }
}
finally {
    Remove-Module $module -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "FAIL $failure" }
    exit 1
}

Write-Output 'Minimal TwinCAT runtime module checks passed.'
exit 0
