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
│   ├── MVP.md
│   ├── ROADMAP.md
│   └── VISION.md
└── spec/
    └── hardware-model.schema.json
```

The repository will grow only when the authoritative project scope requires it.
