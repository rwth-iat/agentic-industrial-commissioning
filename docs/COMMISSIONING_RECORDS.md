# Commissioning run records

## Purpose

Commissioning records preserve the minimum evidence needed to reproduce and
assess one component-scoped run. They are technical execution evidence, not a
fifth plant knowledge model.

The active contract is `spec/commissioning-record.schema.json`, version
`0.1.0`. One compact schema covers three record types.

## Records and placement

All records share `run_id`, `case_id`, `asset_id`, `requested_interface`, a
creation timestamp, and private classification.

```text
cases/<case-id>/raw/runtime/<run-id>/
    <unchanged connector output>

cases/<case-id>/validation/private/<run-id>/
    run-manifest.json
    preflight.json

cases/<case-id>/results/private/probes/<run-id>/
    execution-record.json
```

Use one `run_id` across all paths. A read-only run has no execution record.

### `run-manifest.json`

Records the selected asset and interface, repository revision, logical
connection profile, the exact revisions of the hardware model and the
component's software model, implementation links, and runtime bindings, plus
the initial read-only safety boundary.

### `preflight.json`

Records timestamped raw-evidence references, read-only checks, hypotheses,
blockers, and one interaction-scoped assessment:

- `hard_blocked`;
- `ready_for_supervised_probe`;
- `validated_interface`.

`writes_observed` is required to be `false`. A hard block requires a concrete
resolution and reevaluation path. The assessment is not permanent component
state.

### `execution-record.json`

Exists only after a state-changing probe. It records:

- the four input revisions;
- initial and final state;
- exact approval scope and maximum duration;
- chronological reads, writes, observations, timeouts, errors, aborts, and
  restore events;
- human observations separately from runtime observations;
- restore status;
- confirmed or refuted hypotheses;
- execution status and resulting interaction assessment.

Successful execution requires verified restore. Failed restore requires
`hard_blocked`. `validated_interface` additionally requires a verified adapter
reference.

The adapter reference points to
`generated/connectors/<environment>/components/<component>/verification.json`.
Validation checks that the file and its local entrypoint exist, its status is
`verified`, it supports the requested interface, it identifies the same asset,
and its four input revisions match the commissioning run. The current
supervised actuator path additionally requires a retained human observation and
a confirmed interaction hypothesis. A non-empty string alone is not sufficient.

The small generated verification file has this shape:

```json
{
  "schema_version": "0.1.0",
  "asset_id": "<asset-id>",
  "supported_interfaces": ["<requested-interface>"],
  "entrypoint": "<file-inside-this-adapter-directory>",
  "verification_status": "verified",
  "input_revisions": [
    { "kind": "hardware_model", "path": "...", "revision": "sha256:..." },
    { "kind": "software_model", "path": "...", "revision": "sha256:..." },
    { "kind": "implementation_links", "path": "...", "revision": "sha256:..." },
    { "kind": "runtime_bindings", "path": "...", "revision": "sha256:..." }
  ],
  "evidence_refs": ["cases/<case-id>/raw/runtime/<run-id>/execution-facts.json"]
}
```

This is generated adapter metadata, not another plant-knowledge model.

## Deterministic writer

Create the initial manifest, including a generated run ID, UTC timestamp,
repository state, and SHA-256 revisions of all four inputs, with:

```powershell
./scripts/new-commissioning-run.ps1 `
    -CaseId <case-id> `
    -AssetId <asset-id> `
    -RequestedInterface <interface> `
    -ConnectionProfile <profile-key> `
    -HardwareModelPath <hardware-model.json> `
    -SoftwareModelPath <software-model.json> `
    -ImplementationLinksPath <implementation-links.json> `
    -RuntimeBindingsPath <runtime-bindings.json>
```

The input files must be inside the repository. The generated manifest begins
with a read-only boundary and is persisted through the same writer.

Persist a prepared record with:

```powershell
./scripts/write-commissioning-record.ps1 -InputPath <record.json>
```

The writer validates the document, derives its destination from record type,
case ID, and run ID, writes atomically, and validates the final placement. An
identical retry is idempotent. A different document at the same destination is
rejected; create a new run instead of overwriting evidence.

## Validation

Validate one record or a complete run with:

```powershell
./scripts/validate-commissioning-record.ps1 `
    -RecordPath <run-manifest.json>,<preflight.json>,<execution-record.json>
```

The validator checks JSON Schema, record-specific fields, the four required
input revisions, state/restore consistency, chronological events, timeout
reporting, placement, and identity/revision agreement across supplied records.

Synthetic fixtures and writer checks run through:

```powershell
./tests/schema/test-commissioning-records.ps1
```

## Executor integration

The runtime-binding-aware TwinCAT preflight and supervised-probe dispatchers
provide the first executor integration. Preflight writes raw read-only evidence
and `preflight.json`. A probe writes the unchanged ADS response plus normalized
execution facts under `raw/runtime/<run-id>/`. The bounded recipe emits its
actual reads, writes, timeouts, errors, aborts, and verified restore events.

`scripts/complete-supervised-probe.ps1` converts those executor facts into the
execution record after required human observation and adapter verification.
The agent supplies semantic conclusions but must not reconstruct writes or
timestamps from narrative. This path is covered synthetically and remains
operationally unverified until the separate Y20 run.
