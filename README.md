# Agentic Industrial Commissioning

A research prototype for **vendor-independent, agentic commissioning of industrial automation systems**.

> [!CAUTION]
> This is research software, not a certified safety or real-time control system.
> Read-only access does not authorize writes, deployment, controller-state
> changes, interlock bypasses, or physical actuation. Every consequential action
> requires a separately bounded safety assessment and exact human approval.

## Current scope

The active implementation targets brownfield commissioning with an existing
PLC application and a reconstructed offline baseline. That baseline keeps four
contracts separate: a system-scoped hardware model plus component-scoped
software models, implementation links, and runtime bindings. The agent uses
them for read-only preflight, bounded supervised exploration, evidence capture,
and generation of deterministic component adapters.

Static reconstruction, modification of existing projects, greenfield
generation, and goal-driven autonomy remain visible in the roadmap without
expanding the current runtime path beyond its demonstrated scope.

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

The active brownfield commissioning architecture is documented in
[docs/COMMISSIONING_ARCHITECTURE.md](docs/COMMISSIONING_ARCHITECTURE.md).

## Active architecture

The target architecture contains five deliberately separated layers:

1. An offline evidence, canonical-model, and matching pipeline derives and
   reconciles structured hardware information from heterogeneous engineering
   evidence.
2. A system-scoped hardware model plus repeated component-scoped software
   models, implementation links, and runtime bindings provide the offline
   commissioning baseline.
3. Environment connectors and reusable capabilities provide transport,
   read-only discovery, and guarded low-level interactions.
4. The agent performs read-only preflight and, when authorized, bounded
   exploratory probes against one requested component interaction.
5. Successful exploration is codified as a deterministic semantic component
   adapter under `generated/connectors/<environment-id>/components/`.

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
├── examples/                      # synthetic public examples for all contracts
├── spec/
│   ├── hardware-model.schema.v0.2-proposal.json
│   ├── software-model.schema.json
│   ├── implementation-link.schema.json
│   ├── runtime-binding.schema.json
│   └── commissioning-record.schema.json
├── src/
│   └── commissioning_core/       # deterministic core candidate
├── scripts/
│   ├── capabilities/             # human-facing capability selectors
│   ├── remote/                   # generic remote execution transport
│   ├── run-case.ps1              # generic model-fragment runner
│   ├── new-commissioning-run.ps1
│   ├── complete-supervised-probe.ps1
│   ├── commissioning/             # binding and run-context invariants
│   ├── capabilities/twincat/      # binding-aware preflight and probe dispatchers
│   ├── validate-hardware-model.ps1
│   ├── validate-software-model.ps1
│   ├── validate-implementation-links.ps1
│   ├── validate-runtime-bindings.ps1
│   ├── validate-commissioning-record.ps1
│   └── write-commissioning-record.ps1
├── generated/
│   └── connectors/               # environment-specific adaptations
├── tests/
│   ├── capabilities/
│   ├── core/
│   └── schema/
├── cases/
│   └── <case-id>/
│       ├── raw/                  # local, ignored source evidence
│       ├── derived/private/      # local plant-specific contracts
│       ├── results/private/      # local deterministic outputs and records
│       └── validation/private/   # local case-specific checks and evidence
└── creds/                         # ignored local configuration and secrets
```

The boundary between reusable method development and a concrete operational
case is governed by `AGENTS.md`; case artifacts remain under `cases/<case-id>/`
and environment-specific adaptations under `generated/connectors/`.
The separate mapping from canonical assets to concrete runtime representations
is documented in [docs/RUNTIME_BINDINGS.md](docs/RUNTIME_BINDINGS.md).
Static component-facing software knowledge and its hardware traceability are
documented in [docs/SOFTWARE_MODEL.md](docs/SOFTWARE_MODEL.md) and
[docs/IMPLEMENTATION_LINKS.md](docs/IMPLEMENTATION_LINKS.md).
The component-scoped preflight, supervised-probe, evidence, and adapter loop is
defined in
[docs/COMMISSIONING_RUNBOOK.md](docs/COMMISSIONING_RUNBOOK.md).
The minimal private run records and their deterministic persistence are defined
in [docs/COMMISSIONING_RECORDS.md](docs/COMMISSIONING_RECORDS.md).

## Canonical offline pipeline

The core candidate does not prescribe or read the contents of `raw/`. That
local, repository-ignored directory may contain any available offline evidence
in any organization or format. An agent or connector interprets that evidence
and writes one or more canonical-shaped fragments to `derived/`. Concrete plant
fragments belong under `derived/private/`; committed examples must be synthetic
or explicitly sanitized. The generic runner merges all supplied fragments
without assigning them fixed roles such as BOM, topology, or wiring.

Clone the repository and run the offline schema and core checks:

```powershell
git clone https://github.com/rwth-iat/agentic-industrial-commissioning.git
Set-Location agentic-industrial-commissioning
./tests/test-offline-core.ps1
```

This generic test entry point covers the hardware-model, software-model,
implementation-link, runtime-binding, and commissioning-record contracts plus
core behavior.
The contract validators also run from Windows PowerShell 5.1. When `Test-Json`
is unavailable there, they automatically delegate only the JSON Schema check to
an installed PowerShell 7 runtime and retain their repository-specific semantic
checks in the calling process. Set `AIC_PWSH_PATH` to a `pwsh.exe` path when
automatic discovery is not sufficient.
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

Create ignored local configuration from the public templates:

```powershell
New-Item -ItemType Directory -Force .\creds | Out-Null
Copy-Item .\scripts\remote\config.example.psd1 .\creds\remote.local.psd1
Copy-Item .\capabilities\twincat\ads\config.example.psd1 .\creds\twincat-ads.local.psd1
```

Fill in only your own environment values, then start the human-controlled
remote bridge in one terminal:

```powershell
.\scripts\remote\Start-AgentRemoteBridge.ps1 `
    -ConfigPath .\creds\remote.local.psd1
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

## Publication and private data

The public repository contains the method, schemas, generic tools, synthetic
examples, tests, and sanitized verification summaries. Credentials, endpoints,
network details, raw engineering projects, plant-specific runtime bindings,
operational procedures, and runtime observations stay in ignored local paths.
See [docs/PUBLICATION.md](docs/PUBLICATION.md) before adding case material or
publishing a fork.

## License

Licensed under the [Apache License 2.0](LICENSE).
