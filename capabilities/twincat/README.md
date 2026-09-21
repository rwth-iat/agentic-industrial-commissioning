# TwinCAT capabilities

This directory indexes technical interaction patterns for TwinCAT environments.

## Available interfaces

- [`Start-RemoteBridge.ps1`](Start-RemoteBridge.ps1): human-started transport
  infrastructure for the remote TwinCAT path. It loads the `Remote` section of
  an ignored consolidated connection profile, authenticates interactively, and
  exposes only a token-protected loopback endpoint while the session is alive.
- [`Runtime.psm1`](Runtime.psm1): minimal agent-runtime boundary. It exports
  exactly `Read-Binding` and `Write-Binding`; bridge-state loading and remote
  transport remain private implementation details.
- [`ads/verification/`](ads/verification/): historical verification reports
  retained as evidence; it contains no active runtime implementation.

The module surface was fixed in Phase 4. Phase 5 implements `Read-Binding` as a
strictly technical path: it resolves the exact caller-selected binding, checks
read access, maps the declared PLC datatype, loads the ignored connection
profile, and performs an ADS symbol read through the private bridge transport.
It returns the value and observation timestamp without adding plant semantics.

Phase 6 implements the corresponding technically constrained `Write-Binding`
path without a pseudo-approval parameter. It checks exact binding identity,
write access, value conversion, minimum/maximum and allowed-value constraints,
the explicitly selected technical execution, the ADS symbol's existence,
runtime datatype and writability, then returns the actual immediate readback.

Phase 7 limits technical write behavior to the explicitly selected `level` and
`pulse` modes. The caller supplies `-Mode`; pulse execution also requires an
explicit `-PulseDurationMilliseconds`. A level write persists the converted
value. A pulse must target `BOOL`, requires `TRUE`, reads and rejects an already
active request, enforces the technical duration bounds, resets it to `FALSE` in
`finally`, and reads the actual final state. Optional `write_semantics` binding
metadata is not a runtime default and its absence does not block an explicit
valid WRITE. WRITE does not follow acknowledgement bindings or evaluate
process feedback.

Start the bridge from the repository root in a dedicated terminal:

```powershell
.\capabilities\twincat\Start-RemoteBridge.ps1 `
    -ConfigPath .\creds\hc10-twincat.local.psd1
```

The operator supplies credentials through `Get-Credential`; passwords do not
belong in the profile. Stop the bridge with `Ctrl+C`. Its `finally` cleanup
closes the remote session and removes `.agent-remote-bridge.json`.

Phase 4 integrated the needed client behavior as a private helper in
`Runtime.psm1`; Phases 5 and 6 use it for READ and WRITE. Both implementations
are verified offline with a synthetic loopback bridge. Phase 11 and Phase 12
provide the live plant READ and separately approved WRITE proof points. The
previous `scripts/remote/Invoke-AgentRemote.ps1` is retained only as generic
maintenance fallback infrastructure; it is not an agent-facing capability or
part of the active commissioning architecture.

Phase 15 removed the former ADS catalog, selector, recipe runner, binding
preflight, supervised probe, guarded writes, and Config/Run transition recipes.
The minimal agent-facing path is now only `Read-Binding` and `Write-Binding`.

Future engineering access through TwinCAT XAE or the Automation Interface
belongs in a separate `xae/` area once it has been explored and verified. ADS
runtime access and XAE engineering access must not be treated as equivalent
capabilities.
