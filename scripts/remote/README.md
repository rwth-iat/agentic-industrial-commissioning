# Agent remote bridge

These scripts provide a generic, human-opened PowerShell execution path to an
engineering host. They contain no industrial or vendor-specific logic.

## Start a session

In a dedicated PowerShell terminal:

```powershell
.\scripts\remote\Start-AgentRemoteBridge.ps1 `
    -ComputerName '<ENGINEERING-HOST>'
```

The script prompts the human for credentials unless a `PSCredential` is supplied
explicitly. Keep the terminal open while remote access is intended.
Concrete host and user values are not echoed by default. Use
`-ShowEndpointDetails` only when local troubleshooting requires them.

For repeated local use, copy `config.example.psd1` to the ignored path
`creds/remote.local.psd1`, replace its placeholders, and splat the configuration:

```powershell
$remote = Import-PowerShellDataFile '.\creds\remote.local.psd1'
.\scripts\remote\Start-AgentRemoteBridge.ps1 @remote
```

The bridge can also load the same file directly:

```powershell
.\scripts\remote\Start-AgentRemoteBridge.ps1 `
    -ConfigPath '.\creds\remote.local.psd1'
```

Do not store a password in the data file; interactive human authentication is
the default session-opening boundary.

The ignored wrappers in `creds/` preserve the shorter established commands:

```powershell
.\creds\Start-AgentRemoteBridge.ps1
.\creds\Invoke-AgentRemote.ps1 -Command 'hostname'
```

They delegate to these versioned scripts and do not duplicate the bridge
implementation.

## Invoke remote code

From another terminal:

```powershell
.\scripts\remote\Invoke-AgentRemote.ps1 -Command 'hostname'
```

Or execute the contents of a local script remotely:

```powershell
.\scripts\remote\Invoke-AgentRemote.ps1 `
    -ScriptPath '.\path\to\script.ps1' `
    -Arguments @{ Name = 'value' }
```

The script file is read locally; its contents are transmitted and executed in
the persistent remote session. Arguments are serialized separately and supplied
as named PowerShell parameters on the engineering host, avoiding code-string
interpolation of local configuration values.

## End a session

Stop the bridge terminal with `Ctrl+C`. Cleanup closes the listener and remote
session and removes `.agent-remote-bridge.json`. An invocation must fail when
that state file or the bridge listener is absent.

## Important boundary

The bridge accepts arbitrary PowerShell within the authenticated remote user's
authority. Starting it does not authorize controller changes, deployment, or
physical actuation. See [`docs/REMOTE_ENGINEERING.md`](../../docs/REMOTE_ENGINEERING.md)
and the root `AGENTS.md` before using it.
