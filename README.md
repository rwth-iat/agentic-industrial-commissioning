# Agentic Industrial Commissioning

A research prototype for **vendor-independent, agentic commissioning of industrial automation systems**.

The core idea is to let a coding/engineering agent inspect an industrial automation environment, discover available programmatic interfaces, derive or generate the required connector, normalize discovered hardware into a canonical model, and support commissioning with as little manual engineering as possible.

## Vision

Given:

- access to an engineering environment,
- a physical or simulated automation system,
- a bill of materials and/or device documentation,
- and optional existing engineering artifacts,

the system should be able to:

1. discover the automation environment,
2. identify available engineering/runtime interfaces,
3. generate or derive the required connector,
4. discover hardware and I/O topology,
5. normalize the result into a vendor-independent hardware model,
6. match sensors and actuators to compatible I/O channels,
7. represent ambiguity and confidence explicitly,
8. ask the engineer only for information that cannot be inferred safely,
9. generate commissioning artifacts such as mappings, variable definitions, configuration skeletons, documentation, and later PLC code.

## Project planning

The authoritative definition of the current project scope is maintained in [docs/MVP.md](docs/MVP.md). Potential future development stages are maintained separately in [docs/ROADMAP.md](docs/ROADMAP.md).

The design and active MVP proposal for the vendor-independent intermediate representation are documented in [docs/HARDWARE_MODEL.md](docs/HARDWARE_MODEL.md).

## Design principles

- **Vendor-independent core**: no Beckhoff-, Phoenix-, Siemens-, WAGO-, Turck-, or other vendor-specific assumptions in the core data model or matching logic.
- **Agent-generated integration**: vendor-specific access code should be discovered or generated dynamically where feasible.
- **Canonical intermediate representation**: all discovered systems are translated into one machine-readable hardware model.
- **Human-on-the-loop**: the system should ask for confirmation when evidence is insufficient.
- **Read-only first**: discovery must be safe by default.
- **Explicit uncertainty**: inferred mappings must carry confidence, provenance, and status.
- **Reproducibility**: generated connectors and mappings should be testable and auditable.
- **Future interoperability**: the canonical model should be designed so that mappings to standards such as MHS, AAS, OPC UA, or related automation models can be added later.

## Repository layout

```text
agentic-industrial-commissioning/
├── README.md
├── AGENTS.md
├── docs/
├── examples/
├── spec/
├── src/
│   └── commissioning_core/       # deterministic core candidate
├── scripts/
│   ├── run-case.ps1              # generic model-fragment runner
│   └── validate-hardware-model.ps1
├── tests/
│   ├── core/
│   └── schema/
└── cases/
    └── hc10/
        ├── raw/                  # opaque, unmodified source evidence
        ├── derived/              # agent-derived canonical fragments
        ├── results/              # deterministic pipeline results
        ├── validation/           # HC10-specific checks
        └── run.ps1
```

The boundary between method development and an operational case run is
documented in [docs/DEVELOPMENT_AND_OPERATION.md](docs/DEVELOPMENT_AND_OPERATION.md).

## Offline MVP

The core candidate does not prescribe or read the contents of `raw/`. That
directory may contain any available offline evidence in any organization or
format. An agent or connector interprets that evidence and writes one or more
canonical-shaped fragments to `derived/`. The generic runner merges all supplied
fragments without assigning them fixed roles such as BOM, topology, or wiring.

For HC10, the current fragment names describe how that particular case was
organized. They are examples, not a required input taxonomy for another case.

After an operational run has created the case fragments and runner, execute the
reproducible HC10 pipeline (including canonical-schema validation) with:

```powershell
./cases/hc10/run.ps1
```

It creates `cases/hc10/results/canonical-hardware-model.v0.2.json` and
`cases/hc10/results/matching-report.json`. Compatible declared or observed
connections are retained with their original status and suppress free candidate
generation when they identify one unopposed target. Only physical or functional
validation changes a connection to `validated`.

Run all automated checks:

```powershell
./tests/test-mvp.ps1
```

This generic test entry point covers the schema and core behavior only.
Case-specific validation under `cases/<case-id>/validation/` is generated and
run within the corresponding operational case.
