# Roadmap

## Purpose

This roadmap describes staged proof points toward the autonomous engineering
vision in [VISION.md](VISION.md). It is directional rather than a commitment to
dates or a rigid implementation order.

The stages are cumulative. A later stage may expose a limitation in an earlier
one, but environment-specific findings must not silently reshape the generic
core. Completed proof points are retained in [MVP.md](MVP.md).

## Guiding development loop

Every stage follows the same agentic lifecycle:

```text
Explore -> Validate -> Codify -> Reuse
```

The agent first discovers what an unfamiliar environment provides. Once a
reliable and approved path has been demonstrated, it should be captured as a
deterministic connector, capability recipe, engineering script, PLC artifact,
or validation procedure.

## Stage 1 — Static evidence reconciliation and matching

**Status:** `COMPLETED`

The first proof point established the vendor-independent canonical model and
offline reasoning pipeline.

Demonstrated outcomes include:

- arbitrary static engineering evidence can be interpreted into neutral
  canonical fragments;
- BOM, datasheet, wiring, and engineering-project assertions can be reconciled;
- devices and I/O channels can be matched through electrical compatibility;
- ambiguous, incompatible, declared, observed, and conflicting relations remain
  explicit;
- confidence, provenance, and validation state are preserved;
- reusable schema and core behavior are protected by automated tests.

The bounded completion record is maintained as MVP 1 in
[MVP.md](MVP.md#mvp-1--static-engineering-evidence-reconciliation-and-io-matching).

## Stage 2 — Live interaction with an existing automation project

**Status:** `IN PROGRESS`

### Objective

Let the agent use a high-level component request to inspect and commission a
complete, already operational engineering project and controller runtime, then
codify the validated semantic access path as a deterministic component adapter.

The target architecture is defined in
[COMMISSIONING_ARCHITECTURE.md](COMMISSIONING_ARCHITECTURE.md). A run consumes
the relevant slice of the system-wide hardware model plus that component's
software model, implementation links, and runtime bindings. A project-wide
software aggregate is not required.

The operational sequence is defined in
[COMMISSIONING_RUNBOOK.md](COMMISSIONING_RUNBOOK.md).

### Foundation already established

- a human-controlled remote bridge reaches the engineering environment;
- a reusable TwinCAT ADS capability library and machine-readable catalog exist;
- concrete endpoints and credentials are isolated in ignored local
  configuration;
- the agent and a human-facing selector can invoke read-only recipes;
- system-state reads through the complete local-to-remote-to-ADS path have been
  verified;
- guarded Config-to-Run and Run-to-Config mechanisms are represented as
  state-changing recipes, with explicit verification status.
- generic guarded-write and request/acknowledgement recipes, a separate
  approval-oriented dispatcher, and runtime-binding contract are covered by
  offline checks; the former operation-plan contract was a proof of concept and
  has since been retired from the active architecture;
- a supervised, time-bounded binary-actuator sequence has validated the
  repository request/acknowledgement path, read-only observation, exact-symbol
  resolution, human approval boundary, and logical restore in one environment.
- isolated fresh-agent tests reportedly completed bounded component interaction
  and restoration with Terra at medium and low reasoning effort, including
  correction of an inverted Boolean interpretation and an unsuitable
  project-specific postcondition;
- a capability-neutral supervised runner now composes finite main and restore
  sequences from catalogued recipes through runtime-binding IDs; Boolean,
  analog, and future action semantics remain inside capabilities rather than
  the runner;
- a compact commissioning-record contract, deterministic path-aware writer,
  semantic validator, and offline tests cover the run manifest, read-only
  preflight, and optional execution record without adding another plant model.
- a runtime-binding-aware ADS preflight, supervised-probe dispatcher, direct
  executor event capture, verified restore record, and adapter completion gate
  are connected through synthetic offline tests; live Y20 use remains pending.

The bounded supervised live-interaction proof is retained as completed MVP 2 in
[MVP.md](MVP.md#mvp-2--supervised-live-discovery-and-bounded-runtime-interaction).
Stage 2 remains in progress because MVP 2 intentionally does not cover all
semantic integration, evidence, and reproducibility requirements below.

### Planned static software reconstruction extension

The historical implementation and acceptance plan is retained in
[archive/SOFTWARE_RECONSTRUCTION_PLAN.md](archive/SOFTWARE_RECONSTRUCTION_PLAN.md).
It covers evidence-driven component discovery from available BOM/hardware and
software sources, separate software and implementation-link contracts, reuse
with targeted reconstruction when knowledge is missing, private case storage,
and independent fresh-agent acceptance. Its status is `ACTIVE`: WP1 contracts,
WP2 bounded read-only extraction/private V03 reconstruction, and WP3 offline
component query/runtime-candidate integration are complete. Three bounded
independent offline runs with Luna at medium reasoning passed on 2026-09-08,
covering persisted-knowledge reuse, partial or unresolved knowledge, and
isolated focused reconstruction. WP4 remains incomplete because its frozen
project-wide, deliberately changed-evidence, and held-out synthetic coverage
was not fully executed. Existing MVP records and the remaining live proof points
below retain their scope.

### Remaining proof points

- resolve one requested component from the system hardware model and its
  component-specific software, implementation-link, and runtime-binding files;
- perform a separately bounded read-only preflight and preserve its concrete
  runtime observations;
- compute `hard_blocked`, `ready_for_supervised_probe`, or
  `validated_interface` for the requested interaction and current revisions;
- execute one explicitly approved, reversible, time-bounded component probe
  with observation, abort, and restoration behavior;
- live-verify the executor-to-record path during the first vertical component
  slice;
- update only component knowledge contradicted or strengthened by live
  evidence, retaining provenance and prior revisions;
- generate and offline-test a deterministic semantic component adapter from a
  successful probe;
- invalidate or reassess that adapter when relevant project, runtime, binding,
  hardware, or behavior evidence changes;
- add focused offline checks for approval, bounds, observation, abort, restore,
  evidence retention, and invalidation in the slimmer supervised-probe path.

### Exit condition

The stage is complete when the agent can receive a high-level component
interaction request, resolve the four relevant offline contract inputs, verify
the live path, safely explore a bounded uncertainty with exact approval, and
produce a verified reusable component adapter with structured evidence.

## Stage 3 — Engineering modification of an existing PLC project

**Status:** `PLANNED`

### Objective

Allow the agent to inspect and modify an existing engineering project when the
required PLC structure or mapping is incomplete.

Expected proof points include:

- discover a suitable TwinCAT XAE or Automation Interface access path;
- reconstruct project structure, tasks, POUs, data types, GVLs, symbols, and I/O
  links;
- generate or modify variables, function blocks, programs, configuration, and
  mappings from canonical evidence and high-level requirements;
- build and statically validate the changed project;
- test generated behavior in simulation or another controlled environment;
- present a reviewable change plan and request approval before deployment or
  activation;
- deploy an approved change and verify the resulting project and runtime state;
- codify successful exploratory procedures as reusable capabilities or
  connectors.

## Stage 4 — Greenfield generation from an empty engineering project

**Status:** `PLANNED`

### Objective

Start with engineering evidence, controlled environment access, and an empty or
missing PLC application. Generate the automation project required to operate the
plant.

Expected proof points include:

- discover the available controller and I/O environment;
- derive hardware configuration and I/O mappings from the canonical model;
- create project structure, data types, variables, tasks, function blocks, and
  application code;
- generate deterministic control and diagnostic behavior;
- build, simulate, test, and iteratively correct the project;
- activate and deploy only through explicit safety and human-approval gates;
- validate logical behavior against runtime observations and physical evidence;
- preserve all generated artifacts, decisions, and verification results.

## Stage 5 — Goal-driven autonomous commissioning and operation

**Status:** `PLANNED`

### Objective

Allow a user to express only a high-level process or engineering objective while
the agent plans and performs the necessary discovery, implementation,
commissioning, and validation work.

Representative objectives include:

- integrate a newly installed device;
- bring a reconstructed subsystem into operation;
- diagnose why an intended process behavior is not achieved;
- maintain a requested volumetric-flow setpoint;
- adapt an existing automation project to a changed plant configuration.

The agent should explore when no reliable path exists and generate deterministic
PLC or engineering artifacts once the path is understood. Real-time control
should normally execute in an appropriate deterministic runtime; the agent
remains responsible for engineering the solution, supervising results, adapting
when evidence changes, and escalating when safety or ambiguity requires human
authority.

### Exit condition

The stage is complete when a high-level objective can be transformed into a
traceable sequence of discovery, engineering, approved execution, and observed
validation without requiring the user to prescribe the low-level vendor steps.

## Cross-cutting validation tracks

These tracks apply throughout the roadmap rather than forming isolated final
stages.

### Cross-platform validation

Repeat the workflow on additional automation platforms. The canonical model,
generic reasoning, and safety principles should require no vendor-specific
branches. Platform-specific behavior belongs in replaceable capabilities and
connectors.

### Brownfield reconstruction

Continuously extend reconciliation across live discovery, engineering projects,
runtime observations, documentation, and human evidence. Missing and conflicting
information must remain explicit.

### Safety and authorization

Increase autonomy only with explicit operation boundaries, independent plant
safety measures, before-and-after observations, recoverable procedures where
possible, and human approval for consequential changes.

### Reproducibility and evaluation

For every proof point, preserve raw evidence, generated artifacts, deterministic
tests, verification status, unsuccessful approaches where informative, and the
conditions under which a result may be repeated.
