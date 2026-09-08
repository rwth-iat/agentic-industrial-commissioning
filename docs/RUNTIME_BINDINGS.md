# Runtime bindings

## Purpose

A runtime-binding document records how canonical assets and interfaces are
represented in one concrete engineering or controller runtime. It answers
"how is this asset addressed here?" without adding vendor-specific locators to
the canonical hardware model.

The active contract is `spec/runtime-binding.schema.json` at schema version
`0.1.0`.

```text
Canonical Hardware Model
        | asset and interface identity
        v
Runtime bindings
        | evidence-backed runtime locators and interaction semantics
        v
Technical capabilities
        | read, request, write, wait, and verify primitives
        v
Environment-specific connector / controlled operation
```

Runtime bindings are not credentials, connection settings, executable
procedures, or proof that an operation is safe.

Multi-step procedures over binding IDs use the separate controlled-operation
contract documented in [CONTROLLED_OPERATIONS.md](CONTROLLED_OPERATIONS.md).

## Separation from the canonical model

The canonical hardware model remains vendor-independent and describes physical
assets, interfaces, signals, connections, semantics, uncertainty, and
provenance. Runtime bindings may contain vendor- or project-specific locators,
but they remain a separate artifact and refer back to canonical `asset_id`
values.

The generic schema must never contain concrete hosts, IP addresses, AMS NetIds,
accounts, or credentials. `environment.connection_profile` is only a logical
key. It is resolved through ignored local configuration when a connector or
capability is executed.

## Binding semantics

Each binding records:

- the canonical asset and optional interface it belongs to;
- its role, access direction, locator, and runtime datatype;
- whether it behaves as a level, request, pulse, setpoint, measurement,
  feedback, state, or constant;
- an optional acknowledgement binding;
- whether automatic request reset is expected;
- explicit write constraints for numeric writable setpoints;
- whether feedback is physical, independent process evidence, calculated,
  logical, or still unknown;
- status, confidence, source references, and limitations.

This distinction is necessary for cyclic PLC programs. A request bit may be
accepted and reset in a later PLC cycle, so reading the request bit itself is
not necessarily a valid acknowledgement. A separate active-state, effective
setpoint, command-state, or process binding must be used where available.

## Status and evidence

Supported binding states are:

- `discovered`: the locator was observed but its meaning is not established;
- `inferred`: the mapping is a documented inference;
- `reported_success`: a credible summary reports a successful interaction, but
  the required raw runtime record is not yet preserved;
- `validated`: preserved `runtime_observation` evidence supports the mapping;
- `rejected`: the candidate mapping was disproven;
- `stale`: the mapping was previously useful but no longer matches the current
  environment.

The validator requires every `validated` binding to reference at least one
source of type `runtime_observation`. Summaries and user statements remain
valuable evidence, but they do not silently become direct runtime evidence.

## Storage and privacy

The schema, validator, synthetic examples, and generic tests are committed.
Concrete plant bindings are operational case artifacts and may expose symbol
names or other sensitive implementation details. Store local-only bindings
under `cases/<case-id>/derived/private/`. Private subdirectories below a case
are ignored repository-wide.

Original runtime exports, scripts, logs, and transcripts belong under the
case's local, repository-ignored `raw/` area. Case-specific verification that
exposes plant knowledge belongs under `validation/private/`. Executable
environment adaptation remains under
`generated/connectors/<environment-id>/`; validation evidence does not.

## Validation

Validate one or more documents with:

```powershell
./scripts/validate-runtime-bindings.ps1 `
    -BindingPath <path-to-runtime-bindings.json>
```

Run the committed contract tests with:

```powershell
./tests/schema/test-runtime-bindings.ps1
```

The public example under `examples/runtime-bindings/` is synthetic and must not
be treated as a real plant binding.
