# Roadmap

## Purpose

This roadmap tracks the active reduction of Agentic Industrial Commissioning
to the smallest experiment that can test the research hypothesis in
[VISION.md](VISION.md). It is not a request to preserve the previous pipeline.
Completed proof points remain historically documented in [MVP.md](MVP.md).

The detailed source of truth for the reset is
[AIC_RADICAL_RESET_PLAN_0-18.md](AIC_RADICAL_RESET_PLAN_0-18.md).

## Active target

```text
natural-language goal
        -> LLM + four models
        -> READ / WRITE
        -> deterministic TwinCAT runtime
        -> PLC
```

The LLM owns semantic interpretation, binding selection, action sequencing,
ambiguity handling, and result evaluation. The runtime owns only exact binding
resolution, technical validation, transport, ADS access, and faithful results.

The active target does not include a planner, semantic resolver, workflow DSL,
generic runner, supervised-probe protocol, readiness state, commissioning
record, or generated component adapter.

## Reset sequence

### Baseline and architecture

- Phase 0 — preserve the previous state and baseline evidence. This prerequisite
  was handled before the active documentation reset.
- Phase 1 — define the minimal architecture in active documentation and archive
  the superseded commissioning architecture, runbook, and record contract.

### Minimal technical runtime

- Phase 2 — separate plant knowledge, connection configuration, credentials,
  and runtime observations.
- Phase 3 — retain the existing human-controlled remote bridge as internal
  infrastructure.
- Phase 4 — expose exactly `Read-Binding` and `Write-Binding` from the minimal
  TwinCAT runtime module.
- Phase 5 — implement exact, technical READ behavior.
- Phase 6 — implement technically constrained WRITE behavior without a
  pseudo-approval parameter.
- Phase 7 — support only level and pulse write semantics initially.
- Phase 8 — retain raw structured runtime evidence without a run contract or
  state machine.

### Contracts and offline proof

- Phase 9 — retain only the hardware, software, implementation-link, and
  runtime-binding schemas as active knowledge contracts.
- Phase 10 — replace broad legacy suites with focused model, runtime, and
  privacy checks.

### Technical live proof

- Phase 11 — prove the technical READ path over the human-controlled remote
  TwinCAT ADS bridge.
- Phase 12 — separately approve and prove the bounded technical WRITE path.

### Removal before agentic proof

- Phase 15 — remove the old commissioning pipeline after the minimal runtime
  path is proven.
- Phase 16 — remove the old Stage-1 implementation from the active tree while
  preserving its historical result in Git and `MVP.md`.
- Phase 17 — retain one compact synthetic TwinCAT example with no encoded
  action sequence.

### Agentic proof on the reduced tree

- Phase 13 — give a fresh agent only a natural-language objective and the four
  models; require it to derive the relevant reads, exact write, and feedback
  observation.
- Phase 14 — repeat with changed IDs, symbols, ordering, polarity, and
  irrelevant bindings to detect hardcoding and unsafe guessing.

### Closeout

- Phase 18 — verify the architecture, runtime, privacy, agentic behavior, and
  reduced repository as a whole, then stop.

## Current status

Phases 1 and 2 are complete. Phase 2 added the ignored consolidated local
profile `creds/hc10-twincat.local.psd1` and classified the existing private
configuration, access information, RDP files, and executable wrappers without
deleting, moving, or rewiring them.

Phase 3 is complete. The verified bridge implementation now lives at
`capabilities/twincat/Start-RemoteBridge.ps1`, loads the consolidated local
profile, and preserves the loopback, session-token, transient-state, and
cleanup mechanics. A live operator-authenticated migration check returned the
expected harmless remote result, after which the bridge processes and state
file were removed. Existing profiles, bridge scripts, wrappers, ADS access,
and the remote client remain available as fallbacks.

Phase 4 is complete. `capabilities/twincat/Runtime.psm1` exports exactly
`Read-Binding` and `Write-Binding`; bridge-state validation and the preserved
remote-client protocol are private module details.

Phase 5 is complete. `Read-Binding` resolves only the exact caller-selected
binding ID, checks declared read access and the ADS-symbol locator, maps the PLC
datatype, loads the referenced ignored connection profile, performs the remote
ADS read, and returns a structured technical observation. Synthetic loopback
tests cover the full request and response path on PowerShell 7 and Windows
PowerShell 5. The separate live TwinCAT proof remains Phase 11.

Phase 6 is complete. `Write-Binding` checks the exact selected binding, write
access, deterministic primitive conversion, declared range and allowed-value
constraints, and the explicitly selected technical mode before contacting the bridge. The
remote ADS operation verifies the symbol, writability, and runtime datatype,
writes the value, reads the actual end state, and returns a structured technical
result. It has no pseudo-approval parameter and makes no semantic decision.
Synthetic loopback tests cover the full request and readback path on PowerShell
7 and Windows PowerShell 5. The separately approved live proof remains Phase
12.

Phase 7 is complete. The LLM supplies either `level` or `pulse` to WRITE and
selects the bounded duration for a pulse. Pulse execution must target `BOOL`,
rejects an already active request, raises `TRUE`, guarantees a `FALSE` reset
attempt in `finally`, and returns the actual final readback. Optional binding
`write_semantics` may inform reasoning but is not required for execution.
WRITE does not inspect acknowledgement bindings or evaluate feedback.

Phase 8 is complete. `scripts/append-runtime-evidence.ps1` appends an already
serialized READ or WRITE result unchanged as one UTF-8 JSON line under
`cases/<case-id>/raw/runtime/<timestamp>/events.jsonl`. The utility adds no
semantic fields and creates no manifest, preflight, execution, completion, or
state-machine artifact. READ and WRITE themselves remain free of persistence.

Phase 9 is complete. The active model layer now contains exactly the hardware,
software, implementation-link, and runtime-binding schemas. The validated
hardware-model v0.2 contract is canonical at `spec/hardware-model.schema.json`,
the superseded hardware baseline remains only in Git history, and the four
model validators live under `spec/validation/`. The commissioning-record
schema is no longer an active contract; Phase 15 subsequently removed its
remaining legacy pipeline.

Phase 10 is complete. `tests/models.tests.ps1`,
`tests/twincat-runtime.tests.ps1`, and `tests/privacy.tests.ps1` are the active
offline suites. They cover exactly the four model contracts, the minimal
TwinCAT READ/WRITE boundary, ignored private paths, sanitized public examples,
and tracked credential material without invoking the Commissioning Record
pipeline.

Phase 11 is complete. A fresh component value was read through the exact
runtime-binding ID, the ignored local connection profile, the active
human-controlled loopback bridge, and ADS. The returned symbol and datatype
came from the binding, and the unchanged structured result is retained as
ignored private runtime evidence. No adapter, runner, write, or controller
state change was involved.

Phase 12 is complete. After a separate read-only preflight and exact current
human approval, the minimal runtime executed bounded functional request pulses
through the active bridge. Every pulse reset to `FALSE`, the changed logical
state was read back, the restoration request completed, and final reads
confirmed the original closed/off logical state. The unchanged technical
events are retained as ignored private runtime evidence; calculated PLC
feedback is not presented as independent physical-position evidence.

A focused correction loop subsequently clarified the Phase-6/7 boundary:
the LLM now supplies WRITE mode and pulse duration explicitly, while the
runtime checks access, datatype, value constraints, technical execution, and
safe reset. Optional `write_semantics` is no longer an execution prerequisite.
The Phase-10 suites and the approved Phase-12 technical proof were repeated
successfully with that metadata absent from the selected writable bindings.

Phase 15 is complete. After the technical READ/WRITE path and focused offline
suites had passed, the obsolete commissioning pipeline was removed: capability
catalog and selector, generic runner, binding preflight, supervised probe,
guarded write and Config/Run recipes, commissioning-record scripts and tests,
and their active fixtures. Historical verification reports, archived design
documents, Git history, and the completed milestones in `MVP.md` remain.

Phases 13 and 14 are intentionally paused until the reduced tree is ready. The
Phase-16 contraction is complete: the Stage-1 implementation, generated
connectors, reconstruction scripts, and their core and connector tests have
been removed from the active tree. Their completed historical result remains in
Git history and `MVP.md`.

Phase 17 is complete. The public examples now contain one compact synthetic
TwinCAT process-cell case expressed through exactly the four active contracts.
It includes multiple physical and software components, implementation links,
readable and writable bindings, level and pulse write hints, and an unrelated
diagnostic binding without prescribing an action sequence. Schema edge cases
remain test fixtures rather than additional public examples.

The next implementation boundary is the resumed Phase 13, followed by the
Phase-14 hardcoding variant under `tests/fixtures/` and finally Phase 18.

## Acceptance gates

### Technical gate

- READ returns the current value selected through an exact binding ID.
- WRITE enforces declared technical constraints and returns an actual readback.
- Pulse writes reset in `finally`, including on failure.
- Missing bridge, symbols, profiles, type mismatches, and ADS failures remain
  explicit.

### Agentic gate

- The user supplies no binding ID, symbol, datatype, or action sequence.
- The agent relates all four models and selects the binding itself.
- The agent distinguishes request from feedback and reads relevant state.
- The agent requests concrete human approval before WRITE.
- The agent exposes ambiguity and revises contradicted hypotheses.
- The behavior survives changed identifiers and irrelevant bindings.

### Safety and privacy gate

- Technical writability is never treated as authorization or plant safety.
- The PLC retains real-time control, interlocks, and safety functions.
- Passwords are not stored in the repository or exposed to the agent.
- Concrete plant models, connection data, and runtime evidence remain private.

## Stop rule

After the minimal TwinCAT and fresh-agent tests, do not automatically add a
planner, adapter, workflow, runner, resolver, registry, or another DSL. If the
experiment fails, determine the specific missing information or technical
mechanism and change only that boundary.

```text
LLM reasons.
Models provide context.
READ and WRITE execute technically.
The PLC remains deterministic plant logic.
```
