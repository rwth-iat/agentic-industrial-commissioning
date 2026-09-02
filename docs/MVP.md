# Current MVP

## Authority

This document is the authoritative definition of the current minimum viable product (MVP). If another document conflicts with this definition, this document takes precedence.

## Objective

Validate the canonical hardware model and the core reasoning pipeline independently of any automation vendor or physical testbed.

## Inputs

- a small, manually prepared bill of materials (BOM),
- structured device descriptions derived from datasheets,
- a static I/O-topology snapshot manually exported from a simulated or real engineering environment,
- the active [canonical hardware-model v0.2 proposal](../spec/hardware-model.schema.v0.2-proposal.json).

The topology snapshot may use a vendor-native source format, but it must be processed offline and limited to hardware, module, interface, and channel information. PLC application code, GVLs, POUs, PLC symbol structures, and logical PLC-variable links are excluded from the MVP input.

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
3. determine electrical compatibility using structured signal information,
4. eliminate electrically incompatible mappings,
5. produce all remaining compatible candidate mappings,
6. identify cases in which multiple mappings remain possible,
7. preserve status, confidence, evidence, and provenance for inferred results,
8. request human input only when the available evidence cannot resolve a decision safely or uniquely,
9. pass automated tests for schema validation, normalization, compatibility matching, and ambiguity handling.

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

- a representative BOM fixture,
- structured device-description fixtures,
- at least one static I/O-topology fixture derived from a simulated or manually captured engineering environment,
- valid canonical-model examples,
- invalid examples for schema-validation tests,
- unambiguous, ambiguous, and incompatible matching scenarios,
- automated tests covering the acceptance criteria.

Raw input fixtures and intermediate normalized output should be retained so that results remain reproducible and auditable.

## Status

The MVP is defined but not yet implemented in this repository.

## Deferred work

Potential work beyond the current MVP is maintained in [ROADMAP.md](ROADMAP.md). Items listed there are not part of the current acceptance criteria unless they are explicitly moved into this document.
