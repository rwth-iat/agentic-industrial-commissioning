[CmdletBinding()]
param(
    [string]$ComputerName,

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ConfigPath,

    [PSCredential]$Credential,

    [ValidateSet('Default', 'Negotiate', 'Kerberos')]
    [string]$Authentication = 'Negotiate',

    [string]$StateFile = (Join-Path (Get-Location) '.agent-remote-bridge.json'),

    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxRequests = 0,

    [switch]$ShowEndpointDetails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ConfigPath) {
    $localConfig = Import-PowerShellDataFile -LiteralPath $ConfigPath
    if (-not $PSBoundParameters.ContainsKey('ComputerName') -and $localConfig.ContainsKey('ComputerName')) {
        $ComputerName = [string]$localConfig.ComputerName
    }
    if (-not $PSBoundParameters.ContainsKey('Authentication') -and $localConfig.ContainsKey('Authentication')) {
        $Authentication = [string]$localConfig.Authentication
    }
}

if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    throw 'ComputerName must be supplied directly or through ConfigPath.'
}

$session = $null
$listener = $null
$credentialInUse = $Credential

try {
    Write-Host 'Agent Remote Bridge'
    if ($ShowEndpointDetails) {
        Write-Host "Target server: $ComputerName"
    }
    else {
        Write-Host 'Target server configured.'
    }

    if ($null -eq $credentialInUse) {
        $credentialInUse = Get-Credential -Message "Authenticate for $ComputerName"
    }

    $session = New-PSSession `
        -ComputerName $ComputerName `
        -Credential $credentialInUse `
        -Authentication $Authentication

    $remoteInfo = Invoke-Command -Session $session -ScriptBlock {
        [PSCustomObject]@{
            Host = hostname
            User = whoami
            Time = Get-Date
        }
    }

    $tokenBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($tokenBytes)
    }
    finally {
        $rng.Dispose()
    }
    $sessionToken = [Convert]::ToBase64String($tokenBytes)

    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback,
        0
    )
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

    $state = [PSCustomObject]@{
        schemaVersion = 1
        host          = '127.0.0.1'
        port          = $port
        token         = $sessionToken
        processId     = $PID
        createdAt     = (Get-Date).ToUniversalTime().ToString('o')
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8

    Write-Host ''
    Write-Host 'REMOTE BRIDGE READY'
    if ($ShowEndpointDetails) {
        Write-Host "Remote host: $($remoteInfo.Host)"
        Write-Host "Remote user: $($remoteInfo.User)"
    }
    else {
        Write-Host 'Remote host and user verified.'
    }
    Write-Host "Remote time: $($remoteInfo.Time)"
    Write-Host "Local endpoint: 127.0.0.1:$port"
    if ($ShowEndpointDetails) {
        Write-Host "State file: $StateFile"
    }
    else {
        Write-Host 'Transient state file created.'
    }
    Write-Host 'Stop with Ctrl+C.'

    $requestCount = 0
    while ($true) {
        if (-not $listener.Pending()) {
            Start-Sleep -Milliseconds 200
            continue
        }

        $client = $listener.AcceptTcpClient()
        $reader = $null
        $writer = $null
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader(
                $stream,
                [System.Text.Encoding]::UTF8
            )
            $writer = New-Object System.IO.StreamWriter(
                $stream,
                [System.Text.Encoding]::UTF8
            )
            $writer.AutoFlush = $true

            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            $request = $line | ConvertFrom-Json
            if ([string]$request.token -cne $sessionToken) {
                $writer.WriteLine((
                    [PSCustomObject]@{
                        success = $false
                        output  = ''
                        error   = 'Bridge authentication failed.'
                    } | ConvertTo-Json -Compress
                ))
                continue
            }

            try {
                $codeBytes = [Convert]::FromBase64String([string]$request.code)
                $code = [System.Text.Encoding]::UTF8.GetString($codeBytes)
                $argumentJson = if ($request.PSObject.Properties.Name -contains 'arguments') {
                    $request.arguments | ConvertTo-Json -Depth 20 -Compress
                }
                else {
                    '{}'
                }
                $remoteErrors = @()
                $result = Invoke-Command `
                    -Session $session `
                    -ScriptBlock {
                        param($SourceCode, $ArgumentJson)

                        $argumentObject = $ArgumentJson | ConvertFrom-Json
                        $namedArguments = @{}
                        foreach ($property in $argumentObject.PSObject.Properties) {
                            $namedArguments[$property.Name] = $property.Value
                        }

                        $remoteScript = [ScriptBlock]::Create($SourceCode)
                        & $remoteScript @namedArguments
                    } `
                    -ArgumentList $code, $argumentJson `
                    -ErrorVariable remoteErrors `
                    -ErrorAction Continue `
                    2>&1

                $writer.WriteLine((
                    [PSCustomObject]@{
                        success = ($remoteErrors.Count -eq 0)
                        output  = (($result | Out-String).TrimEnd())
                        error   = (($remoteErrors | Out-String).TrimEnd())
                    } | ConvertTo-Json -Compress
                ))
            }
            catch {
                $writer.WriteLine((
                    [PSCustomObject]@{
                        success = $false
                        output  = ''
                        error   = $_.Exception.ToString()
                    } | ConvertTo-Json -Compress
                ))
            }
        }
        finally {
            if ($null -ne $reader) { $reader.Dispose() }
            if ($null -ne $writer) { $writer.Dispose() }
            $client.Close()
        }

        $requestCount++
        if ($MaxRequests -gt 0 -and $requestCount -ge $MaxRequests) {
            break
        }
    }
}
finally {
    Write-Host 'Stopping Agent Remote Bridge...'
    if ($null -ne $listener) {
        try { $listener.Stop() } catch { }
    }
    if (Test-Path -LiteralPath $StateFile) {
        Remove-Item -LiteralPath $StateFile -Force
    }
    if ($null -ne $session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
    $credentialInUse = $null
    Write-Host 'Remote session closed. Bridge stopped.'
}
