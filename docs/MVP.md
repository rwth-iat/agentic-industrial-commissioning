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

- representative raw case evidence;
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
- `cases/hc10/` and `cases/hc10_v02/` retain representative engineering
  evidence and case artifacts.
- Schema fixtures cover valid documents, missing interfaces, missing evidence,
  schema-version errors, duplicate IDs, dangling references, and reversed
  ranges.
- Core tests cover compatibility, ambiguity, asserted connections, competing
  evidence, duplicate claims, and unresolved endpoints.
- `tests/test-offline-core.ps1` passes all schema and core checks.

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

## Subsequent milestones

The next milestone is not created by rewriting MVP 1. Once its bounded scope and
acceptance criteria are agreed, it should be appended here with status `ACTIVE`.
The current development direction is described in [ROADMAP.md](ROADMAP.md).
