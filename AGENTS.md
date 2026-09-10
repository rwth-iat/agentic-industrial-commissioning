# AGENTS.md

## Purpose and active focus

This repository develops a generic, vendor-independent method for agentic
industrial commissioning.

The active focus is brownfield commissioning with an existing PLC application
and an already reconstructed offline knowledge baseline. Static reconstruction,
greenfield generation, and broader operation remain documented in the roadmap,
but must not add complexity to the current commissioning path.

## Architecture boundary

Keep the generic core independent of vendor, PLC platform, fieldbus,
engineering suite, and device manufacturer. Vendor-specific technical access
belongs in capabilities or environment-specific generated connectors.

Commissioning uses four contract types:

1. The hardware model is normally case- or system-scoped.
2. Software models are component-scoped.
3. Implementation links are component-scoped.
4. Runtime bindings are component-scoped.

The last three contract types may occur repeatedly below component-specific
case directories. A run uses the requested component package and only the
relevant hardware-model slice. It must not require a merged project-wide
software, link, or binding document.

Do not mix their responsibilities:

- hardware models describe physical systems, devices, interfaces, signals,
  connections, uncertainty, and provenance;
- software models describe component-facing controller semantics;
- implementation links trace hardware identities to software semantics;
- runtime bindings describe concrete runtime access and interaction semantics.

Passing a schema proves structure, not runtime truth or authorization.

## Commissioning workflow

For component work, follow
[`docs/COMMISSIONING_RUNBOOK.md`](docs/COMMISSIONING_RUNBOOK.md). The architecture
and responsibility split are defined in
[`docs/COMMISSIONING_ARCHITECTURE.md`](docs/COMMISSIONING_ARCHITECTURE.md).

Every live run begins with a separately bounded read-only preflight. Read-only
access does not authorize later writes. Assess readiness for the requested
interaction from current evidence; do not treat readiness as a permanent
component property.

Persist run records through `scripts/write-commissioning-record.ps1` and
validate them with `scripts/validate-commissioning-record.ps1`. Their contract
and placement are defined in `docs/COMMISSIONING_RECORDS.md`. Execution events
must come from the technical executor; do not reconstruct reads, writes, or
timestamps from narrative.

After successful exploration, generate or update a small deterministic
component adapter under
`generated/connectors/<environment-id>/components/<component-id>/`. Recurring
multi-component behavior may compose validated component adapters. Do not add a
fifth static knowledge model merely to preserve the exploratory sequence.

A high-level state-changing commissioning request remains incomplete after a
successful probe. Continue through adapter generation and offline verification
without requiring a second user instruction. Claim `validated_interface` only
when the adapter verification references the current four input revisions and
retained evidence. Pause only for exact state-change approval, required human
observation, unresolved ambiguity, or a concrete blocker.

## Safety

Safety takes priority over autonomy.

Unless the exact task is explicitly approved:

- remain read-only;
- do not activate physical outputs;
- do not change controller state;
- do not activate configuration;
- do not download or deploy PLC code;
- do not start machinery;
- do not bypass interlocks or safety functions.

A state-changing probe requires exact human approval for the current component,
effect, bounds, duration, runtime context, observation, abort, and restoration
path. Recheck preconditions immediately before execution. Approval does not
carry over to another run or changed context. A technical `HumanApproved`
parameter is not proof of authorization or plant safety.

Prefer a validated controller-managed functional request interface over direct
writes to mapped outputs or internal variables. Never silently substitute a
primitive write for a requested semantic action.

The PLC or another deterministic controller retains hard real-time control,
interlocks, and safety functions. The agent performs commissioning,
exploration, validation, and supervisory orchestration around that boundary.

## Evidence and uncertainty

Never turn an inference into a fact silently. Preserve status, confidence,
evidence, provenance, contradictions, and rejected candidates. If multiple
identities or mappings remain plausible, present candidates instead of choosing
arbitrarily.

Preserve raw live output privately under
`cases/<case-id>/raw/runtime/<run-id>/` before promoting a claim. A request for
the current value requires a new acquisition after that request; otherwise
label any reused value as last known with its timestamp.

Treat the offline documents as the run's versioned input baseline. Do not
overwrite them. Create a new version only for the contract whose claim changed:

- locator, datatype, access, or runtime semantics update runtime bindings;
- controller behavior or signal meaning may update the software model;
- changed hardware-to-software trace may update implementation links;
- physical hardware claims require physical or hardware evidence.

A runtime read alone must not silently rewrite the hardware model. A
`validated` runtime claim requires retained runtime-observation evidence. Keep
input revisions and affected cross-document references consistent.

## Connectors and capabilities

A connector owns transport, session handling, environment discovery, and
environment-specific access. It does not assign plant semantics. Concrete
hosts, addresses, accounts, credentials, installation paths, and plant locators
belong in ignored local configuration or private case artifacts.

Reusable technical interaction patterns belong under `capabilities/`. Inspect
the catalog before deriving an ad hoc call. Prefer `READ_ONLY` recipes. Promote
a procedure only after practical verification, or mark it experimental.
Human-facing read selectors must reject state-changing entries; guarded write
selectors must preserve the approval boundary.

## Repository boundaries

Method development belongs in `AGENTS.md`, `docs/`, `spec/`, `examples/`,
`src/`, generic scripts, capabilities, and generic tests. An operational case
must not silently change the generic method or schemas.

Store concrete system work under `cases/<case-id>/`:

- source and runtime evidence under ignored `raw/`;
- agent-derived contracts under `derived/`;
- deterministic case outputs under `results/`;
- case-specific checks under `validation/`.

Concrete plant knowledge in `derived/`, `results/`, or `validation/` belongs in
an ignored `private/` subdirectory. Committed fixtures must be synthetic or
explicitly sanitized. The generic core consumes derived contracts, never raw
case evidence directly.

## Development rules

- Prefer small, testable modules and existing seams.
- Keep failures and uncertainty explicit.
- Keep generic behavior testable offline.
- Add complexity only when the active acceptance target requires it.
- Preserve unrelated worktree changes.

Before implementation work, consult `docs/VISION.md`, `docs/ROADMAP.md`, and
`docs/MVP.md`. Historical proof points remain historical records.
