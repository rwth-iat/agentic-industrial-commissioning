# Technical capabilities

This directory contains vendor-specific technical access required by the
minimal runtime. A capability implements transport and primitive interaction;
it does not assign plant semantics or encode a commissioning workflow.

## Architectural boundary

```text
Four models + LLM
        | select one exact runtime binding and operation
        v
READ / WRITE
        | enforce technical constraints
        v
Vendor runtime capability
```

- `capabilities/twincat/Runtime.psm1` exposes exactly `Read-Binding` and
  `Write-Binding`.
- `capabilities/twincat/Start-RemoteBridge.ps1` provides the human-controlled
  transport lifecycle.
- `scripts/remote/` contains generic remote-execution transport tooling.
- `cases/<case-id>/` contains private plant models and runtime evidence.
- `creds/` contains ignored local profiles, endpoints, and transient state.

The former catalog, selector, generic recipe runner, binding preflight,
supervised probe, guarded write, and controller-state transition abstractions
were removed in Phase 15. They must not be recreated as compatibility wrappers.

READ is the default. WRITE remains a primitive technical operation and requires
separate exact human approval for every real state change. The LLM owns binding
selection, sequencing, semantic evaluation, and approval dialogue; the PLC
retains interlocks and real-time control. Repository-wide safety rules are in
the root `AGENTS.md`.
