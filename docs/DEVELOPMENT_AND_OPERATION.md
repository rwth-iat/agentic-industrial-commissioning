# Development and Operation Boundary

## Purpose

This repository separates development of the method from application of the
method to a concrete industrial system. Both activities may be performed by an
agent, but they produce different artifacts and require different review.

## Method and core development

The following paths define or implement the reusable method:

- `AGENTS.md`, `docs/`, `spec/`, and `examples/` define the rules and contract;
- `src/commissioning_core/` contains the deterministic core candidate;
- `scripts/run-case.ps1` and `scripts/validate-hardware-model.ps1` expose the
  generic execution and validation paths;
- `tests/core/` and `tests/schema/` protect reusable behavior.

Changing these paths is a development activity. A normal case run uses them
without silently adapting the core to a manufacturer or engineering system.
If a case reveals a genuinely generic limitation, the agent must report it as
core-development work and add a general test with the change.

## Operational case

Each concrete system is kept under `cases/<case-id>/`:

- `raw/` contains local, opaque source evidence available for the case;
- `derived/` contains canonical-shaped fragments extracted from that evidence;
- `results/` contains deterministic pipeline outputs;
- `validation/` contains expectations that are specific to the case;
- `run.ps1` supplies the case paths to the generic runner.

The entire `raw/` subtree is private-by-default and ignored by Git. It may
contain sensitive plant documents, source projects, exports, observations, or
recordings and must not be committed. Publishable source fixtures belong under
`examples/` or `tests/fixtures/` and must be explicitly synthetic or sanitized.
Previously tracked raw files predate this policy; removing them from tracking
and repository history is a separate migration and does not permit additional
raw evidence to be committed.

The method imposes no required file type, filename, directory taxonomy, or
combination of evidence inside `raw/`. It may contain documents, exports,
images, databases, archives, source projects, recordings, or other artifacts.
Its internal organization is case-local and has no semantic meaning to the
core. The generic core never scans or interprets `raw/` directly.

Files in `derived/`, their concrete provenance entries, and files in `results/`
are case artifacts. Artifacts that expose concrete plant identities, topology,
symbols, behavior, or source locations must be stored below the corresponding
ignored `private/` subdirectory in `derived/`, `results/`, or `validation/`.
Only explicitly synthetic or sanitized artifacts may be committed. Every
derived JSON document uses the same neutral fragment shape and may contribute
any combination of sources, assets, connections, and extensions. Fragment
filenames and boundaries are not part of the contract.

Static controller software knowledge uses the separate contract in
`spec/software-model.schema.json`. Hardware-to-software traceability uses
`spec/implementation-link.schema.json`. Concrete instances of both are private
case artifacts; only their schemas, validators, synthetic fixtures, and method
documentation belong to the reusable public layer. Static qualified names are
not runtime locators, and neither contract authorizes execution.

Runtime bindings are also derived case artifacts, but they use the separate
contract in `spec/runtime-binding.schema.json` rather than the canonical model
fragment shape. They map canonical asset/interface identities to concrete
runtime representations without changing the canonical hardware schema.
Concrete binding instances that expose plant symbol locators remain ignored
local artifacts; committed examples must be synthetic or explicitly sanitized.

Controlled-operation documents are deterministic case results that reference
runtime-binding IDs and describe preconditions, steps, observations, restore
behavior, and approval scope. Real operation plans remain private when they
expose sensitive operating knowledge. Validation evidence for their execution
belongs under the case's `validation/` directory, not under a generated
connector.

## Environment-specific connector

When programmatic extraction is required, replaceable environment-specific
code belongs under `generated/connectors/<environment-id>/`. Such code may use
vendor APIs and source formats, but it must emit structured data for the
canonical processing path. Vendor-specific branches must not be added to the
generic matching logic.

## Reusable capability and transport layers

Curated technical interaction patterns belong under `capabilities/`. They may
be specific to a vendor, protocol, runtime, or engineering API, but they must
not contain concrete local endpoints, credentials, plant symbol defaults, or
case semantics. Capability metadata and verification status are part of this
reusable method layer.

Human-facing selection and orchestration scripts belong under
`scripts/capabilities/`. Generic remote-execution transport belongs under
`scripts/remote/`. Concrete local configuration and credentials remain under
ignored `creds/`.

An environment-specific connector may compose capabilities and remote
transport, but it remains responsible for adapting them to one environment,
preserving raw discovery output in the ignored local case area, and emitting
canonical-shaped fragments. Raw runtime or engineering output must not bypass
the canonical processing path.

## Current maturity

`src/commissioning_core/` is the first core candidate derived from the HC10
offline evidence and matching proof point. It is deliberately limited to the
currently validated signal profile. The name "core" means vendor-independent
within that defined profile; it does not claim universal coverage of industrial
hardware.
