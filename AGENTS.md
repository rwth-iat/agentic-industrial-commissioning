# AGENTS.md

## Project purpose

This repository develops a **generic, vendor-independent agentic approach for automated discovery, integration, reverse engineering, and commissioning of industrial automation systems**.

The project is not intended to hard-code integrations for individual automation vendors into the core.

## Core principle

Keep the core independent of vendor, PLC platform, fieldbus, engineering suite, and device manufacturer.

Where feasible, a coding/engineering agent should:

1. inspect the available environment,
2. discover a programmatic access path,
3. create or adapt the required connector,
4. validate that connector,
5. translate discovered information into the canonical hardware model defined under `spec/`.

Vendor-specific code may exist as a generated or replaceable artifact, but vendor-specific assumptions must not leak into the canonical model or core matching logic.

## Target pipeline

```text
Environment discovery
        ↓
Interface discovery
        ↓
Connector generation/adaptation
        ↓
Hardware / I/O discovery
        ↓
Normalization
        ↓
Canonical Hardware Model
        ↓
Device ↔ I/O matching
        ↓
Validation / ambiguity handling
        ↓
Commissioning artifact generation
```

## Primary use cases

The architecture should support three use cases:

1. **Greenfield commissioning**
   - discover a newly assembled automation system,
   - match known devices to available I/O,
   - generate initial engineering artifacts.

2. **Brownfield reconstruction**
   - inspect an existing system and engineering project,
   - reconstruct hardware, mappings, semantics, and documentation,
   - represent conflicting or missing information explicitly.

3. **System extension**
   - detect newly added or changed devices,
   - integrate them into an existing canonical system model,
   - minimize manual re-engineering.

## Canonical model

The canonical hardware model under `spec/` is the contract between discovery and downstream reasoning.

Do not bypass it by passing raw vendor-specific output directly into matching or generation logic.

The canonical model should represent at least:

- systems,
- controllers,
- I/O modules,
- channels,
- devices,
- electrical signal characteristics,
- engineering units and ranges,
- capabilities,
- constraints,
- mappings,
- confidence,
- provenance,
- validation state.

## Uncertainty

Never turn an inference into a fact silently.

For inferred information, preserve:

- `status`,
- `confidence`,
- `evidence`,
- `source` / provenance where available.

If multiple mappings remain physically compatible, return candidate mappings instead of choosing arbitrarily.

## Safety rules

Safety takes priority over autonomy.

Unless a task explicitly requires otherwise:

- discovery is read-only,
- do not activate physical outputs,
- do not change controller state,
- do not activate a configuration,
- do not download or deploy PLC code,
- do not start machinery,
- do not bypass interlocks or safety functions.

Any future write, deployment, or actuation path must require an explicit safety boundary and human approval.

## Connector behavior

A connector is an implementation detail used to access a concrete automation environment.

A generated connector should ideally expose a small, generic set of capabilities such as:

- inspect environment,
- discover topology,
- read channel metadata,
- read mappings,
- read diagnostics,
- optionally read runtime values.

Do not assume the same API exists across vendors.

The agent may use documentation, installed SDKs, CLIs, COM interfaces, engineering APIs, OPC UA, runtime APIs, file formats, or other available programmatic access paths.

## Generated artifacts

Generated vendor-specific integration code should be isolated from the generic core.

Prefer a structure such as:

```text
generated/
└── connectors/
    └── <environment-id>/
```

Generated artifacts must record enough metadata to reproduce how they were created and how they were validated.

## Development rules

- Prefer small, testable modules.
- Prefer structured schemas over free-form LLM output.
- Keep vendor names out of generic abstractions unless they are data values.
- Do not add complexity before the current project scope requires it.
- Add tests for normalization, matching, and schema validation.
- Preserve raw discovery output for debugging and provenance.
- Make failures explicit rather than guessing.
- Design offline-first where possible so development does not depend on access to a physical testbed.

## Project scope and roadmap

Before implementation work, consult [docs/MVP.md](docs/MVP.md) for the authoritative current scope and [docs/ROADMAP.md](docs/ROADMAP.md) for potential future development stages. Do not duplicate their contents in this file.
