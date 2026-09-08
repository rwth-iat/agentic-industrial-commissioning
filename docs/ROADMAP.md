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

Let the agent use high-level requests to inspect and interact with a complete,
already operational engineering project and controller runtime.

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
  approval-oriented dispatcher, and runtime-binding/controlled-operation
  contracts are covered by offline checks;
- a supervised, time-bounded binary-actuator sequence has validated the
  repository request/acknowledgement path, read-only observation, exact-symbol
  resolution, human approval boundary, and logical restore in one environment.
- isolated fresh-agent tests reportedly completed bounded component interaction
  and restoration with Terra at medium and low reasoning effort, including
  correction of an inverted Boolean interpretation and an unsuitable
  project-specific postcondition;
- a generic bounded request-actuation wrapper now represents enter, activate,
  monitored hold, deactivate, and restore as one approval-bound operation; its
  implementation is covered offline and remains experimental pending its own
  supervised live run.

The bounded supervised live-interaction proof is retained as completed MVP 2 in
[MVP.md](MVP.md#mvp-2--supervised-live-discovery-and-bounded-runtime-interaction).
Stage 2 remains in progress because MVP 2 intentionally does not cover all
semantic integration, evidence, and reproducibility requirements below.

### Planned static software reconstruction extension

The implementation and acceptance plan is recorded in
[SOFTWARE_RECONSTRUCTION_PLAN.md](SOFTWARE_RECONSTRUCTION_PLAN.md).
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

- preserve successful reads of concrete process values and their datatype,
  engineering unit, timestamp, and source;
- connect live PLC symbols and runtime observations to assets and interfaces in
  the canonical model without relying on names alone;
- answer high-level read requests by selecting and validating the correct
  runtime symbol;
- live-verify the separate guarded level-write path with suitable bounds and a
  reversible target;
- complete and preserve the final Run-to-Config readback verification;
- record live observations as case evidence and feed derived findings back into
  the canonical representation;
- systematically preserve and regression-test recovery from unavailable routes,
  wrong datatypes, stale symbols, invalid signal interpretations, and failed
  operations;
- classify and place successful exploratory findings as private case evidence
  or environment-specific generated artifacts instead of leaving them only in
  a session or storing engineering knowledge under `creds/`.

### Exit condition

The stage is complete when the agent can receive a high-level read or bounded
interaction request for an existing project, discover or select the required
technical path, execute it safely, and return a verified semantic result with
structured provenance and a correctly placed reusable artifact where the
exploration produced durable engineering knowledge.

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
