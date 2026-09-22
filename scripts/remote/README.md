# Legacy remote bridge path

These scripts preserve the previously verified bridge and client during the
radical-reset migration. The canonical bridge now lives at
`capabilities/twincat/Start-RemoteBridge.ps1`. Phase 4 integrated the client
protocol as a private helper in `capabilities/twincat/Runtime.psm1`; this copy
remains only as a fallback until READ and WRITE are proven.

## Start a session

Start the canonical bridge in a dedicated PowerShell terminal:

```powershell
.\capabilities\twincat\Start-RemoteBridge.ps1 `
    -ConfigPath .\creds\hc10-twincat.local.psd1
```

The script prompts the human for credentials unless a `PSCredential` is supplied
explicitly. Keep the terminal open while remote access is intended.
Concrete host and user values are not echoed by default. Use
`-ShowEndpointDetails` only when local troubleshooting requires them.

The new bridge reads the `Remote` section of the consolidated local profile.
The old flat profile and legacy bridge remain available as a fallback:

```powershell
$remote = Import-PowerShellDataFile '.\creds\remote.local.psd1'
.\scripts\remote\Start-AgentRemoteBridge.ps1 @remote
```

Do not store a password in the data file; interactive human authentication is
the default session-opening boundary.

The ignored wrappers in `creds/` remain unchanged as migration fallbacks:

```powershell
.\creds\Start-AgentRemoteBridge.ps1
.\creds\Invoke-AgentRemote.ps1 -Command 'hostname'
```

They delegate to these versioned scripts and do not duplicate the bridge
implementation.

## Invoke remote code through the legacy fallback

These commands are retained for migration verification and maintenance. They
are not part of the target agent interface.

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
