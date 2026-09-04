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
9. generate engineering artifacts such as mappings, configuration, PLC
   structures, documentation, and controller code;
10. execute approved engineering and commissioning actions, observe the result,
    and refine the model and reusable capabilities.

## Project planning

The long-term direction is documented in [docs/VISION.md](docs/VISION.md), and
planned development stages are maintained in [docs/ROADMAP.md](docs/ROADMAP.md).

The design and active proposal for the vendor-independent intermediate
representation are documented in [docs/HARDWARE_MODEL.md](docs/HARDWARE_MODEL.md).

## Current implementation layers

The repository currently contains two deliberately separated implementation
layers:

1. An offline evidence, canonical-model, and matching pipeline derives and
   reconciles structured hardware information from heterogeneous engineering
   evidence.
2. A remote capability layer provides a verified read-only path from a local
   agent through a human-opened PowerShell bridge to a TwinCAT ADS environment.

The capability layer remains isolated from the vendor-independent core. Its
recipes, transport, local configuration, safety boundaries, and verification
records are explicit repository artifacts.

## Design principles

- **Vendor-independent core**: no Beckhoff-, Phoenix-, Siemens-, WAGO-, Turck-, or other vendor-specific assumptions in the core data model or matching logic.
- **Agent-generated integration**: vendor-specific access code should be discovered or generated dynamically where feasible.
- **Explore, codify, reuse**: unfamiliar environments are explored within their
  safety boundary; validated procedures are converted into deterministic,
  reusable artifacts.
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
├── docs/                         # architecture and method documentation
├── capabilities/                 # curated technical recipes and catalogs
│   └── twincat/ads/
├── examples/
│   ├── runtime-bindings/          # synthetic binding contract example
│   └── controlled-operations/     # synthetic operation contract example
├── spec/
│   ├── hardware-model.schema.v0.2-proposal.json
│   ├── runtime-binding.schema.json
│   └── controlled-operation.schema.json
├── src/
│   └── commissioning_core/       # deterministic core candidate
├── scripts/
│   ├── capabilities/             # human-facing capability selectors
│   ├── remote/                   # generic remote execution transport
│   ├── run-case.ps1              # generic model-fragment runner
│   ├── validate-hardware-model.ps1
│   ├── validate-runtime-bindings.ps1
│   └── validate-controlled-operation.ps1
├── generated/
│   └── connectors/               # environment-specific adaptations
├── tests/
│   ├── capabilities/
│   ├── core/
│   └── schema/
├── cases/
│   └── hc10/
│       ├── raw/                  # opaque, unmodified source evidence
│       ├── derived/              # agent-derived canonical fragments
│       ├── results/              # deterministic pipeline results
│       ├── validation/           # HC10-specific checks
│       └── run.ps1
└── creds/                         # ignored local configuration and secrets
```

The boundary between method development and an operational case run is
documented in [docs/DEVELOPMENT_AND_OPERATION.md](docs/DEVELOPMENT_AND_OPERATION.md).
The separate mapping from canonical assets to concrete runtime representations
is documented in [docs/RUNTIME_BINDINGS.md](docs/RUNTIME_BINDINGS.md).
Bounded procedures over runtime-binding IDs are documented in
[docs/CONTROLLED_OPERATIONS.md](docs/CONTROLLED_OPERATIONS.md).

## Canonical offline pipeline

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

Run the offline schema and core checks:

```powershell
./tests/test-offline-core.ps1
```

This generic test entry point covers the hardware-model, runtime-binding, and
controlled-operation schemas plus core behavior.
Case-specific validation under `cases/<case-id>/validation/` is generated and
run within the corresponding operational case.

## TwinCAT ADS capability prototype

The current technical capability set provides reusable TwinCAT ADS recipes for
system-state reads, PLC-state reads, symbol discovery, primitive symbol reads,
guarded symbol writes, request/acknowledgement handshakes, and guarded system
state transitions. The catalog and verification status are
documented in [capabilities/twincat/ads/README.md](capabilities/twincat/ads/README.md).

Concrete endpoints, AMS NetIds, installation paths, RDP profiles, and
credentials belong in the ignored `creds/` directory. Tracked example
configuration files contain placeholders only.

Start the human-controlled remote bridge in one terminal:

```powershell
.\creds\Start-AgentRemoteBridge.ps1
```

In another terminal, list the available read-only operations:

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1 -List
```

Open the interactive selector:

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1
```

Or invoke a read-only capability directly:

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1 `
    -Capability ReadSystemState
```

The normal selector excludes all state-changing entries. State changes remain
available as guarded low-level recipes for an authorized agent workflow, but
they require explicit human approval for the exact operation and independent
verification of the safe plant state. `Run -> Config` remains experimental
until a successful final readback has been preserved.

Run the capability checks separately from the offline core suite:

```powershell
.\tests\test-capabilities.ps1
```

The remote architecture, session lifecycle, and safety boundary are documented
in [docs/REMOTE_ENGINEERING.md](docs/REMOTE_ENGINEERING.md). Sanitized records
of the real read-only integration check and the first supervised, bounded
request/acknowledgement actuation are kept under
`capabilities/twincat/ads/verification/`.
