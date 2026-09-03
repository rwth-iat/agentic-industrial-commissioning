[CmdletBinding(DefaultParameterSetName = 'Command')]
param(
    [Parameter(ParameterSetName = 'Command', Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Command,

    [Parameter(ParameterSetName = 'File', Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ScriptPath,

    [hashtable]$Arguments = @{},

    [string]$StateFile = (Join-Path (Get-Location) '.agent-remote-bridge.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    throw "No active Agent Remote Bridge found. Expected state file: $StateFile"
}

$state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
if ($state.schemaVersion -ne 1) {
    throw "Unsupported bridge state schema: $($state.schemaVersion)"
}
if ([string]$state.host -ne '127.0.0.1') {
    throw "Refusing non-loopback bridge endpoint: $($state.host)"
}
if ([int]$state.port -lt 1 -or [int]$state.port -gt 65535) {
    throw "Invalid bridge port: $($state.port)"
}
if ([string]::IsNullOrWhiteSpace([string]$state.token)) {
    throw 'Bridge state does not contain a session token.'
}

if ($PSCmdlet.ParameterSetName -eq 'File') {
    $code = Get-Content -LiteralPath $ScriptPath -Raw
}
else {
    $code = $Command
}

$request = [PSCustomObject]@{
    token     = [string]$state.token
    code      = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($code))
    arguments = $Arguments
}
$requestJson = $request | ConvertTo-Json -Compress

$client = New-Object System.Net.Sockets.TcpClient
$reader = $null
$writer = $null
try {
    $client.Connect([string]$state.host, [int]$state.port)
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
    $writer.WriteLine($requestJson)

    $responseJson = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($responseJson)) {
        throw 'The Agent Remote Bridge returned an empty response.'
    }
    $response = $responseJson | ConvertFrom-Json

    if ($response.output) {
        Write-Output $response.output
    }
    if (-not $response.success) {
        $message = if ($response.error) { $response.error } else { 'Remote command failed.' }
        Write-Error $message
    }
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $writer) { $writer.Dispose() }
    $client.Close()
}
