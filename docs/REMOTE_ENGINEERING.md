# Remote Engineering

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

The bridge decides **where** code runs. Capability recipes describe **how** a
technical interface can be used. The canonical model and evidence determine
**what** an observed asset or signal means.

## Components

- `scripts/remote/Start-AgentRemoteBridge.ps1` is started interactively by a
  human. It prompts for authentication, opens a persistent PowerShell session,
  binds a listener to loopback only, and writes transient connection data to
  `.agent-remote-bridge.json`.
- `scripts/remote/Invoke-AgentRemote.ps1` sends a command or script through an
  already running local bridge.
- `capabilities/` contains reusable technical recipes that may be transmitted
  through the bridge.
- `scripts/capabilities/` contains human-facing selectors that resolve catalog
  entries, load ignored local configuration, and invoke the appropriate recipe.
- `creds/` contains ignored local endpoint configuration, RDP profiles,
  credentials-related notes, and private operational records.

For compatibility with the established local workflow, ignored convenience
wrappers remain at `creds/Start-AgentRemoteBridge.ps1` and
`creds/Invoke-AgentRemote.ps1`. They contain no bridge implementation: they
forward to `scripts/remote/`, and the start wrapper automatically uses
`creds/remote.local.psd1`.

The bridge scripts contain no TwinCAT or plant-specific logic.

## Human-controlled session lifecycle

1. Connect the workstation to the required trusted network or VPN.
2. Start `Start-AgentRemoteBridge.ps1` in a dedicated terminal and supply the
   target engineering host and human credentials.
3. Confirm that the script reports `REMOTE BRIDGE READY` and keep that terminal
   open.
4. Run the agent in a separate terminal. It may use
   `Invoke-AgentRemote.ps1` only within the user's task and safety authority.
5. End the agent activity, then stop the bridge with `Ctrl+C`.
6. Confirm that the remote session, loopback listener, and transient state file
   were removed. A subsequent invocation must fail while no bridge is active.

See [`scripts/remote/README.md`](../scripts/remote/README.md) for command syntax.
For the read-only TwinCAT ADS menu, see
[`scripts/capabilities/twincat/README.md`](../scripts/capabilities/twincat/README.md).

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
- a command-line `-HumanApproved` flag is a defensive check, not evidence of
  approval;
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
