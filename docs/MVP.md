# MVP milestones

## Purpose

This document is a cumulative record of bounded project proof points. Completed
milestones remain documented instead of being overwritten by the next active
stage. Each milestone defines its own objective, safety boundary, acceptance
criteria, and completion evidence.

The long-term direction is defined in [VISION.md](VISION.md). Development order
and upcoming stages are maintained in [ROADMAP.md](ROADMAP.md).

## Status vocabulary

- `PLANNED`: scope is identified but acceptance criteria are not yet active.
- `ACTIVE`: implementation or validation is in progress.
- `COMPLETED`: all stated acceptance criteria have supporting evidence.
- `SUPERSEDED`: retained as history but replaced by a newer proof point.

---

## MVP 1 — Static engineering evidence reconciliation and I/O matching

**Status:** `COMPLETED`

**Completed:** 2026-09-03

### Objective

Validate the canonical hardware model and the core reasoning pipeline
independently of any automation vendor or physical testbed.

### Inputs

- an arbitrary set of static, offline evidence artifacts available for a case;
- one or more agent- or connector-derived canonical fragments;
- the active
  [canonical hardware-model v0.2 proposal](../spec/hardware-model.schema.v0.2-proposal.json).

The method does not require particular raw categories such as a BOM, datasheet,
wiring plan, or engineering export. Those are possible evidence types, not a
fixed interface. Raw evidence may use any format or local folder organization;
the core neither scans nor interprets it. An agent or connector selects relevant
evidence and translates it into neutral fragments containing canonical sources,
assets, connections, or extensions.

For this milestone, evidence was limited to static information. PLC application
code, GVLs, POUs, PLC symbol structures, logical PLC-variable links, and live
system interaction were outside its scope.

### Expected outputs

- normalized device and I/O-channel data represented through the canonical
  hardware model;
- an electrical compatibility matrix;
- candidate device-to-I/O mappings;
- explicit confidence and ambiguity information;
- focused human questions where the available evidence is insufficient.

### Acceptance criteria

MVP 1 required the project to:

1. validate representative input and output documents against the canonical
   schema;
2. normalize devices and I/O channels without introducing vendor-specific
   assumptions into the core;
3. preserve sourced manufacturer names and manufacturer product codes wherever
   available while retaining partially identified assets without inventing
   missing identity data;
4. determine electrical compatibility using structured signal information;
5. eliminate electrically incompatible mappings;
6. produce all remaining compatible candidate mappings;
7. identify cases in which multiple mappings remain possible;
8. preserve status, confidence, evidence, and provenance for inferred results;
9. request human input only where the available evidence cannot resolve a
   decision safely or uniquely;
10. pass automated tests for schema validation, normalization, compatibility
    matching, reconciliation, and ambiguity handling.

### Safety boundary

All processing in MVP 1 was offline. A human could create a static topology
snapshot from a real engineering environment under the applicable local safety
procedures, but only the resulting files entered the milestone. Live access,
configuration activation, controller-state changes, and I/O actuation were not
part of its proof.

### Required artifacts

- representative raw case evidence retained in the local case workspace;
- canonical fragments derived from that evidence;
- valid and invalid canonical-model examples;
- unambiguous, ambiguous, incompatible, and conflicting matching scenarios;
- automated schema and core tests;
- reproducible case results with retained provenance.

### Completion evidence

- `spec/hardware-model.schema.v0.2-proposal.json` defines the validated canonical
  contract used by the pipeline.
- `src/commissioning_core/` implements assembly, evidence reconciliation, and
  electrical compatibility matching without vendor-specific branches.
- Private operational case workspaces retained the representative engineering
  evidence and case artifacts used for the proof point; they are intentionally
  absent from the public repository.
- Schema fixtures cover valid documents, missing interfaces, missing evidence,
  schema-version errors, duplicate IDs, dangling references, and reversed
  ranges.
- Core tests cover compatibility, ambiguity, asserted connections, competing
  evidence, duplicate claims, and unresolved endpoints.
- `tests/test-offline-core.ps1` passes all schema and core checks.

The publication process removed raw plant files and case-specific artifacts
from Git history. The current privacy policy keeps every case `raw/` directory
and plant-specific `private/` artifact local and ignored. This changes the
public evidence boundary, not the historical completion claim.

### Historical non-goals

The following were deliberately excluded from MVP 1 and therefore do not weaken
its completed status:

- agent-controlled discovery from a live automation environment;
- runtime-value acquisition;
- production-ready vendor-specific connectors;
- PLC code generation or project modification;
- controller configuration, deployment, activation, or state changes;
- physical output actuation or machinery operation.

These topics belong to later milestones and the roadmap.

---

## MVP 2 — Supervised live discovery and bounded runtime interaction

**Status:** `COMPLETED`

**Completed:** 2026-09-07

### Objective

Demonstrate that an engineering agent can receive a high-level request for an
existing operational automation project, discover the required live access and
functional runtime interface, perform an explicitly approved bounded
interaction, observe the logical response, and restore the initial state.

This milestone proves a supervised live interaction loop. It does not complete
the broader Stage 2 objective of fully modeled, provenance-preserving runtime
integration for arbitrary reads and writes.

### Inputs

- the tracked repository with its generic remote and TwinCAT ADS capabilities;
- minimal ignored local connection configuration;
- an existing complete and operational PLC project;
- a high-level component interaction request from the operator;
- current human confirmation of the applicable plant-safety conditions and
  physical observations.

Concrete endpoints, credentials, PLC symbols, and plant-specific procedures
were not committed as public defaults.

### Expected outputs

- a discovered functional request and observation path for the selected
  component;
- explicit pre-operation and final-state observations;
- a time-bounded, reversible interaction within the approved scope;
- logical confirmation of activation and restoration;
- independent operator reporting of the physical response;
- retained uncertainty where PLC feedback was calculated or project-specific
  signal semantics remained unresolved.

### Acceptance criteria

MVP 2 required the project to demonstrate that:

1. the agent can establish the intended local-to-remote-to-ADS access path
   without embedding local endpoints or credentials in tracked recipes;
2. discovery begins read-only and identifies a functional controller-managed
   interface instead of silently forcing a mapped hardware output;
3. a human can authorize a concrete component, requested effect, bounded
   duration, and restoration target;
4. the agent can observe the initial runtime state, execute the approved
   interaction, and monitor logical acknowledgements;
5. the agent stops or restores when an observation contradicts its current
   hypothesis;
6. the selected component returns to its initial logical state after successful
   execution or an early abort;
7. physical operator observation is distinguished from calculated PLC
   feedback; and
8. incorrect signal interpretations remain correctable rather than being
   silently promoted to facts.

### Safety boundary

All state-changing tests were supervised at the physical plant and limited to
explicitly selected components, effects, and durations. They did not authorize
PLC deployment, project modification, configuration activation, safety-system
bypass, direct forcing of unresolved enable signals, or reuse in another plant
state.

The human approval applied per concrete run. Technical writability, an approval
parameter, or a successful earlier run was not treated as continuing
authorization.

### Completion evidence

- The remote bridge, read-only ADS recipes, guarded state-changing recipes,
  capability catalog, and approval-oriented dispatcher are covered by offline
  tests.
- The supervised bounded actuator run recorded in
  [`2026-09-04-supervised-bounded-actuation.md`](../capabilities/twincat/ads/verification/2026-09-04-supervised-bounded-actuation.md)
  verifies exact nested-symbol resolution, request/acknowledgement transitions,
  logical observation, restoration, and independent physical confirmation in
  one environment.
- The isolated-agent tests summarized in
  [`2026-09-07-fresh-agent-exploratory-interaction.md`](../capabilities/twincat/ads/verification/2026-09-07-fresh-agent-exploratory-interaction.md)
  report successful bounded interaction using Terra at medium and low reasoning
  effort, including recovery from incorrect Boolean polarity and an unsuitable
  project-specific postcondition.
- `spec/runtime-binding.schema.json` defined runtime meaning. The former
  `controlled-operation` contract represented bounded multi-step behavior as a
  proof of concept at milestone completion; it was later retired from the
  active architecture without changing this historical result.
- At milestone completion, the generic bounded request-actuation wrapper and
  its operation-bound approval plan passed offline checks under both Windows
  PowerShell 5.1 and PowerShell 7.

### Known limitations and non-goals

- The reported fresh-agent runs did not preserve complete structured runtime
  logs or their exact generated scripts in the repository; their evidence
  status remains `reported_success` rather than `validated`.
- PLC feedback used during the tests was not always independent physical
  feedback. Human observation supplied the independent physical confirmation.
- Automatic classification and correct placement of agent-generated
  exploration artifacts was not achieved consistently and is deferred to a
  separate issue.
- The generic bounded request-actuation wrapper has offline coverage but has not
  completed its own supervised live run and remains experimental.
- The separate guarded level-write path and final Run-to-Config readback were
  not validated by this milestone.
- No claim is made about another PLC project, vendor, controller version, or
  unsupervised plant operation.

These limitations remain active Stage 2 work and do not weaken the narrower
proof that supervised exploratory discovery, bounded actuation, observation,
correction, and restoration were achieved.

---

## Subsequent milestones

Future milestones are appended rather than replacing MVP 1 or MVP 2. Their
development direction is maintained in [ROADMAP.md](ROADMAP.md).
