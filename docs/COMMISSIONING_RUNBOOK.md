# Component commissioning runbook

## Purpose

This is the operational path for commissioning one requested component
interaction in an existing PLC system. The user may describe the component and
desired effect in natural language. The agent resolves technical identities
from the four offline contract types.

`AGENTS.md` remains authoritative for safety, evidence, privacy, and repository
boundaries. Contract details remain in their model documentation. The three
run-record types and deterministic writer are defined in
[COMMISSIONING_RECORDS.md](COMMISSIONING_RECORDS.md).

## Inputs

A run resolves:

- the case and requested component;
- the requested read or interaction;
- the relevant slice of the system-wide hardware model;
- that component's software model;
- that component's implementation links;
- that component's runtime bindings;
- the required connector and available capabilities.

The user does not need to provide asset IDs, binding IDs, runtime locators, or
file paths. If several components remain plausible, report the candidates and
ask the user to select one.

## Workflow

### 1. Assemble the run context

Create a unique run ID. Record the selected component, requested interaction,
repository revision, resolved input files and revisions, connection-profile
key, and applicable safety boundary. Do not record secrets.

Load dependencies only when they affect the requested interaction. Do not
require project-wide software or runtime aggregates.

### 2. Perform read-only preflight

Before any approval request or state change:

1. Confirm the connector path and controller/runtime state.
2. Resolve required runtime bindings and verify existence, access, and
   datatype.
3. Inspect current mode, ownership, relevant conditions, protections, feedback,
   timeout, abort, and restoration paths.
4. Compare observations with the offline baseline.
5. Preserve raw, timestamped connector output privately.
6. Record agreements, contradictions, ambiguity, and unavailable evidence.

This phase never writes, pulses a request, changes mode or controller state,
deploys code, activates configuration, or actuates hardware.

For the current TwinCAT ADS path, resolve the component request binding IDs and
prepare or execute the read-only acquisition through
`scripts/capabilities/twincat/Invoke-AdsBindingPreflight.ps1`. The user does not
supply PLC symbols. Optional ownership, permit, protection, or other
preconditions are passed as binding-ID expectations derived from the component
contracts.

A request for `current`, `now`, `again`, or equivalent wording requires a fresh
acquisition after that request. If it fails, report the timestamped last-known
value as such.

### 3. Assess the requested interaction

Compute one result for the component, requested interaction, input revisions,
and current runtime context:

- `hard_blocked`: potential harm cannot currently be bounded. Record the exact
  blocker, required evidence or mitigation, and reevaluation condition.
- `ready_for_supervised_probe`: remaining uncertainty can be learned through a
  reversible, time-bounded, observable probe.
- `validated_interface`: the live path, semantics, effect, restoration, and
  deterministic adapter are evidenced for the recorded context.

Do not store this as a permanent component readiness document. Recompute it
when relevant inputs or runtime context change.

A sensor or read-only objective may finish after this step. Unknown behavior is
not automatically a hard blocker when a safe bounded probe can resolve it.

### 4. Obtain exact approval

For a state-changing probe, present only the information needed for a decision:

- resolved component and semantic effect;
- current preconditions and ownership;
- maximum value or active duration;
- observation method and remaining uncertainty;
- abort conditions and restoration target.

Request a new explicit approval for that exact probe. Approval expires when the
target, effect, bounds, input revisions, runtime state, or safety context
changes. No separate persistent operation-plan document is required.

### 5. Execute the bounded probe

Immediately recheck the preconditions. Then use the guarded connector and
capability path to:

1. enter any evidenced prerequisite state;
2. apply only the approved semantic request;
3. observe the expected and contradictory signals within the approved bounds;
4. abort on deviation or timeout;
5. remove the request and restore the recorded target state;
6. verify and record the final state.

Do not improvise an alternative write or automatically retry after a mismatch.
If restoration cannot be verified, report it immediately and invalidate the
interaction assessment.

For the current ADS path, prepare the locator-free approval view through
`scripts/capabilities/twincat/Invoke-AdsSupervisedProbe.ps1`. The agent selects
finite main and restore lists from catalogued capabilities and maps their
parameters to runtime-binding IDs. Execute the same fingerprinted operation
only after exact current approval. The runner rechecks initial conditions and
preserves capability results and normalized facts under the run's raw evidence
path.

### 6. Record, refine, and codify

Retain only the required run records:

- `run-manifest.json` for identity, scope, revisions, and safety boundary;
- `preflight.json` for observations and the computed assessment;
- `execution-record.json` when a state-changing probe occurred.

Store raw observations under `cases/<case-id>/raw/runtime/<run-id>/`, the
manifest and preflight under
`cases/<case-id>/validation/private/<run-id>/`, and the execution record under
`cases/<case-id>/results/private/probes/<run-id>/`. A record may reference large
raw payloads instead of duplicating them.

Persist these files through `scripts/write-commissioning-record.ps1` and
validate the complete run with `scripts/validate-commissioning-record.ps1`.
Do not replace executor facts with an agent-written narrative.

After the probe and required human observation, use
`scripts/complete-supervised-probe.ps1` to combine the immutable executor facts
with the observation, hypothesis result, and optional verified adapter
reference. Do not finalize successful probe evidence as `validated_interface`
until the adapter exists and passes its completion gate.

Update only the component contract supported by new evidence. Preserve the old
version, provenance, conflicts, and validator result.

After a successful probe, generate or update a deterministic semantic adapter
under:

```text
generated/connectors/<environment-id>/components/<component-id>/
```

The adapter uses binding IDs and the connector/capability boundary. It does not
duplicate credentials or hard-code a new plant-wide control layer. Record its
input revisions, evidence references, verification state, and limitations.

Reassess the interface after relevant project, binding, connector,
configuration, hardware, or observed-behavior changes. If a validated adapter
still applies, reuse it instead of exploring again.

### 7. Completion boundary

The original high-level commissioning request covers exploration, evidence
capture, targeted model refinement, adapter generation, and adapter
verification. A successful probe is not the end of the task and the user does
not need to request adapter generation separately.

The task may finish only with a verified adapter and `validated_interface`, or
with a concrete `hard_blocked` result. If adapter generation or verification is
unfinished, report the interaction as not yet validated and continue within
the same task when safe work remains.

Acceptance of the method occurs in a fresh operational session started from
the prepared repository state. That agent receives only the high-level
component objective. It must discover the four inputs and use this runbook
without relying on the architecture conversation.
