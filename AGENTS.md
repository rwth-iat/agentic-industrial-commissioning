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
        ↓
Controlled engineering execution
        ↓
Observation / validation
        ↓
Model and capability refinement
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

The active working schema is `spec/hardware-model.schema.v0.2-proposal.json`; its scope and validation rules are documented in `docs/HARDWARE_MODEL.md`.

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

## Runtime bindings

Concrete mappings from canonical assets or interfaces to runtime locators are a
separate contract defined by `spec/runtime-binding.schema.json` and documented
in `docs/RUNTIME_BINDINGS.md`. Do not add PLC symbols, OPC UA NodeIds, API
resources, runtime datatypes, request handshakes, or similar environment details
to the canonical hardware model merely because they were discovered together.

Runtime-binding documents must preserve status, confidence, provenance,
interaction semantics, and the distinction between calculated, logical, and
independent physical or process feedback. A binding marked `validated` requires
preserved runtime-observation evidence; a successful narrative without its raw
record remains `reported_success`.

The public runtime-binding contract uses a logical connection-profile key and
must not contain concrete hosts, IP addresses, AMS NetIds, accounts, or
credentials. Concrete plant binding instances and symbol locators must remain
in ignored local case artifacts unless they have been explicitly sanitized for
publication.

Controlled multi-step behavior is a separate contract defined by
`spec/controlled-operation.schema.json` and documented in
`docs/CONTROLLED_OPERATIONS.md`. Operation steps reference runtime-binding IDs;
they must not duplicate concrete runtime locators. A structurally valid plan is
not executable authorization, and a `reported_success`, `draft`, `stale`, or
`rejected` plan must not be presented or executed as a validated procedure.

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

## Capability library

Reusable, vendor- or interface-specific technical access patterns belong under
`capabilities/`. A capability describes how to perform a technical interaction;
it does not assign plant semantics and does not replace an environment-specific
connector.

When using or extending the capability library:

- inspect the catalog and existing recipes before deriving an ad hoc vendor API
  call; explore only when no suitable procedure exists or current evidence
  shows that the existing procedure does not apply;
- prefer `READ_ONLY` recipes and inspect the current state before acting;
- never infer physical meaning or permission from filenames, PLC symbol names,
  comments, or addresses alone;
- supply concrete hosts, IP addresses, AMS NetIds, account details, installation
  paths, and plant symbol names through ignored local configuration rather than
  committing them as recipe defaults;
- keep generic remote transport under `scripts/remote/`, local credentials and
  endpoints under ignored `creds/`, and environment-specific adaptations under
  `generated/connectors/<environment-id>/`;
- use human-facing selectors under `scripts/capabilities/` for direct operator
  workflows; read-only selectors must reject state-changing catalog entries,
  and controlled selectors must require an operation-specific approval guard;
- preserve relevant discovery output as case evidence and translate it into
  canonical fragments before it enters matching or generation logic;
- promote a procedure into `capabilities/` only after practical verification or
  mark it explicitly as experimental;
- record verification status, environment versions, evidence, limitations, and
  remaining uncertainty without publishing local secrets or endpoints;
- do not treat a `HumanApproved` parameter or similar technical switch as proof
  of user authorization or plant safety.

State-changing recipes remain subject to the repository safety rules above.
The agent must obtain explicit human approval for the exact operation and must
not claim that applicable plant safety conditions have been verified unless
that verification is supported by current evidence.

When no reliable procedure exists, the agent may explore available interfaces
within the applicable safety boundary. It must preserve failures and evidence,
avoid converting guesses into facts, and codify a successful path into a small,
testable artifact for reuse. Deterministic generated code should be preferred
for recurring control behavior once the approach has been validated.

## Generated artifacts

Generated vendor-specific integration code should be isolated from the generic core.

Prefer a structure such as:

```text
generated/
└── connectors/
    └── <environment-id>/
```

Generated artifacts must record enough metadata to reproduce how they were created and how they were validated.

## Development and operational case boundary

Treat changes to `spec/`, `src/`, the generic scripts, and generic tests as
method-development work. A normal operational case run must not silently adapt
the canonical schema or generic core to a manufacturer or engineering system.

Store concrete system work under `cases/<case-id>/`:

- source evidence under `raw/`,
- agent-derived canonical fragments under `derived/`,
- deterministic outputs under `results/`,
- case-specific checks under `validation/`.

Environment-specific extraction code belongs under
`generated/connectors/<environment-id>/`. If a case exposes a genuinely generic
gap, report it explicitly and handle the core change as development work with a
general test.

Treat `raw/` as opaque evidence. Do not require a particular set of evidence
types, filenames, formats, or subdirectories, and do not infer semantics from
its folder layout. Discover and cite what is actually available. The generic
core must consume derived canonical fragments rather than reading `raw/`
directly.

## Development rules

- Prefer small, testable modules.
- Prefer structured schemas over free-form LLM output.
- Keep vendor names out of generic abstractions unless they are data values.
- Do not add complexity before the active roadmap stage requires it.
- Add tests for normalization, matching, and schema validation.
- Preserve raw discovery output for debugging and provenance.
- Make failures explicit rather than guessing.
- Keep logic testable offline where possible, even when a stage also requires
  explicit live validation against a physical or simulated environment.

## Project scope and roadmap

Before implementation work, consult [docs/VISION.md](docs/VISION.md) for the
long-term direction, [docs/ROADMAP.md](docs/ROADMAP.md) for the active development
stage, and [docs/MVP.md](docs/MVP.md) for completed and formally bounded proof
points. Do not duplicate their contents in this file.
