# Current MVP

## Authority

This document is the authoritative definition of the current minimum viable product (MVP). If another document conflicts with this definition, this document takes precedence.

## Objective

Validate the canonical hardware model and the core reasoning pipeline independently of any automation vendor or physical testbed.

## Inputs

- an arbitrary set of static, offline evidence artifacts available for the case,
- one or more agent- or connector-derived canonical fragments,
- the active [canonical hardware-model v0.2 proposal](../spec/hardware-model.schema.v0.2-proposal.json).

The method does not require particular raw categories such as a BOM, datasheet,
wiring plan, or engineering export. Those are possible evidence types, not a
fixed interface. Raw evidence may use any format or local folder organization;
the core neither scans nor interprets it. An agent or connector selects relevant
evidence and translates it into neutral fragments containing canonical sources,
assets, connections, or extensions.

For the offline MVP, evidence must be limited to static information. PLC
application code, GVLs, POUs, PLC symbol structures, logical PLC-variable links,
and live system interaction remain excluded.

## Expected outputs

- normalized device and I/O-channel data represented through the canonical hardware model,
- an electrical compatibility matrix,
- candidate device-to-I/O mappings,
- explicit confidence and ambiguity information,
- focused human questions where the available evidence is insufficient.

## Acceptance criteria

The MVP is complete when it can:

1. validate representative input and output documents against the canonical schema,
2. normalize devices and I/O channels without introducing vendor-specific assumptions into the core,
3. preserve the sourced manufacturer name and manufacturer product code for every normalized asset,
4. determine electrical compatibility using structured signal information,
5. eliminate electrically incompatible mappings,
6. produce all remaining compatible candidate mappings,
7. identify cases in which multiple mappings remain possible,
8. preserve status, confidence, evidence, and provenance for inferred results,
9. request human input only when the available evidence cannot resolve a decision safely or uniquely,
10. pass automated tests for schema validation, normalization, compatibility matching, and ambiguity handling.

## Non-goals

The current MVP does not include:

- agent-controlled discovery from a live automation or engineering system,
- physical I/O access or runtime-value acquisition,
- generated or production-ready vendor-specific connectors,
- controller configuration, code download, deployment, or state changes,
- activation of outputs, machinery, interlocks, or safety functions,
- production commissioning artifacts or PLC code generation.

## Safety boundary

All agent processing within the current MVP is offline and must not interact directly with physical automation equipment. A human may create a static topology snapshot from a real engineering environment under the applicable local safety procedures. Only the resulting files are provided to the MVP; live access, configuration activation, controller state changes, FreeRun, and I/O actuation remain outside its safety boundary.

## Required test artifacts

The repository should contain:

- at least one representative set of raw case evidence,
- the canonical fragments derived from that evidence,
- valid canonical-model examples,
- invalid examples for schema-validation tests,
- unambiguous, ambiguous, and incompatible matching scenarios,
- automated tests covering the acceptance criteria.

Raw evidence and derived fragments should be retained so that results remain reproducible and auditable. A specific raw folder structure is not required.

## Status

An executable core candidate and the HC10 offline case are implemented. The
case now separates raw evidence, agent-derived structured inputs, deterministic
results, generic tests, and case-specific validation. The core remains an MVP
candidate until its limited signal profile and reconciliation behavior have
been formally accepted.

## Deferred work

Potential work beyond the current MVP is maintained in [ROADMAP.md](ROADMAP.md). Items listed there are not part of the current acceptance criteria unless they are explicitly moved into this document.
