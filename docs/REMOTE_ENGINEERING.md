# Remote Engineering

> [!NOTE]
> Phase 3 moved the verified bridge implementation to its canonical location.
> Phase 15 removed the former catalog, selectors, and commissioning workflows.
> The human owns the bridge lifecycle; it is not an agent-facing workflow.

## Purpose

The remote engineering path lets an agent running in this repository execute
technical discovery code on a human-approved engineering host without embedding
plant semantics or credentials in the repository.

```text
Agent workstation
        | local loopback bridge
        v
Human-authenticated PowerShell session
        | WinRM / PowerShell Remoting
        v
Engineering host
        | vendor API, engineering tool, or runtime protocol
        v
Controller or industrial environment
```

The bridge decides **where** code runs. The minimal TwinCAT runtime implements
the technical READ/WRITE mechanism. The four models and the LLM determine
**what** an observed asset or signal means.

## Components

- `capabilities/twincat/Start-RemoteBridge.ps1` is started interactively by a
  human. It loads the `Remote` section of the ignored consolidated profile,
  prompts for authentication, opens a persistent PowerShell session, binds a
  listener to loopback only, and writes transient connection data to
  `.agent-remote-bridge.json`.
- `scripts/remote/Invoke-AgentRemote.ps1` sends a command or script through an
  already running local bridge. It was retained for the successful Phase-3
  migration proof. Phase 4 copied the needed client behavior into private
  helpers in `capabilities/twincat/Runtime.psm1`; the standalone client remains
  only as a fallback until READ and WRITE are verified.
- `scripts/remote/Start-AgentRemoteBridge.ps1` remains the previous verified
  bridge implementation and fallback during migration.
- `capabilities/twincat/Runtime.psm1` contains the private bridge client and
  exposes exactly `Read-Binding` and `Write-Binding`.
- `creds/` contains ignored local endpoint configuration, RDP profiles,
  credentials-related notes, and private operational records.

For compatibility with the established local path, ignored convenience
wrappers remain unchanged at `creds/Start-AgentRemoteBridge.ps1` and
`creds/Invoke-AgentRemote.ps1`. They contain no bridge implementation and
continue to forward to `scripts/remote/` until the replacement path is fully
verified.

The bridge scripts contain no TwinCAT or plant-specific logic.

## Human-controlled session lifecycle

1. Connect the workstation to the required trusted network or VPN.
2. Start `capabilities/twincat/Start-RemoteBridge.ps1` in a dedicated terminal
   with `-ConfigPath .\creds\hc10-twincat.local.psd1`, then supply human
   credentials through `Get-Credential`.
3. Confirm that the script reports `REMOTE BRIDGE READY` and keep that terminal
   open.
4. During the Phase-3 migration proof, use `Invoke-AgentRemote.ps1` from a
   separate terminal for one harmless remote command. It is not part of the
   target agent interface.
5. End the agent activity, then stop the bridge with `Ctrl+C`.
6. Confirm that the remote session, loopback listener, and transient state file
   were removed. A subsequent invocation must fail while no bridge is active.

See [`capabilities/twincat/README.md`](../capabilities/twincat/README.md) for
canonical bridge syntax and [`scripts/remote/README.md`](../scripts/remote/README.md)
for the retained migration client and fallback path.

## Security and safety boundary

The bridge is bound to loopback and is usable only while the human-held process
and its authenticated remote session are alive. A random per-session token in
the ignored state file prevents an unrelated local caller from issuing an
unauthenticated request accidentally.

This is an access-lifecycle boundary, not a complete security or industrial
safety boundary. While open, the bridge can execute arbitrary PowerShell in the
remote session's authority. Therefore:

- opening the bridge authorizes only remote engineering access within the
  current task;
- write, deployment, controller-state, and actuation operations still require
  separate explicit human approval for the exact action;
- applicable plant safety conditions, interlocks, and operating procedures
  must be verified independently;
- runtime writability is not evidence of approval;
- credentials and concrete endpoints must remain in ignored local files;
- remote output used by the project must be preserved in the ignored local
  case `raw/` area and normalized before entering the generic core.

## RDP and programmatic access

Remote Desktop may be used by a human to observe an engineering host or verify
a visible state change. It is not part of the programmatic path. Closing an RDP
window does not necessarily close WinRM, ADS, or the local bridge; stopping the
bridge process is the explicit way to end agent access.

## Local configuration

Do not place real endpoints in tracked examples. Local files may follow this
pattern:

```text
creds/
├── remote.local.psd1
├── twincat-ads.local.psd1
├── *.rdp
└── docs/                       # private full-detail records
```

Tracked `*.example.psd1` files contain placeholders and document the expected
shape only.
