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

- `raw/` contains opaque source evidence available for the case;
- `derived/` contains canonical-shaped fragments extracted from that evidence;
- `results/` contains deterministic pipeline outputs;
- `validation/` contains expectations that are specific to the case;
- `run.ps1` supplies the case paths to the generic runner.

The method imposes no required file type, filename, directory taxonomy, or
combination of evidence inside `raw/`. It may contain documents, exports,
images, databases, archives, source projects, recordings, or other artifacts.
Its internal organization is case-local and has no semantic meaning to the
core. The generic core never scans or interprets `raw/` directly.

Files in `derived/`, their concrete provenance entries, and files in `results/`
are case artifacts. Every derived JSON document uses the same neutral fragment
shape and may contribute any combination of sources, assets, connections, and
extensions. Fragment filenames and boundaries are not part of the contract.

## Environment-specific connector

When programmatic extraction is required, replaceable environment-specific
code belongs under `generated/connectors/<environment-id>/`. Such code may use
vendor APIs and source formats, but it must emit structured data for the
canonical processing path. Vendor-specific branches must not be added to the
generic matching logic.

## Current maturity

`src/commissioning_core/` is the first core candidate derived during the HC10
MVP development. It is deliberately limited to the current MVP signal profile.
The name "core" means vendor-independent within that defined profile; it does
not claim universal coverage of industrial hardware.
