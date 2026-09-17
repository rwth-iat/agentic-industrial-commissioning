# Runtime bindings

## Purpose

A runtime-binding document records how canonical assets and interfaces are
represented in one concrete engineering or controller runtime. It answers
"how is this asset addressed here?" without adding vendor-specific locators to
the canonical hardware model.

The active contract is `spec/runtime-binding.schema.json` at schema version
`0.1.0`.

```text
Four knowledge models
        | physical, software, link, and runtime context
        v
LLM agent
        | selects an exact binding from the user's goal
        v
READ / WRITE
        | technical validation and runtime access
        v
PLC
```

Runtime bindings are not credentials, connection settings, executable
procedures, or proof that an operation is safe.

The LLM selects binding IDs from the model context. Runtime code resolves the
selected ID exactly and does not choose among bindings semantically.

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
- optional technical write-semantics metadata that may inform the LLM's choice;
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

The LLM explicitly supplies WRITE mode and, for a pulse, its duration. The
runtime does not derive either from the binding. It validates only that the
selected execution is technically supported: level or pulse, pulse duration
between 10 and 60000 milliseconds, `BOOL`/`TRUE` for a pulse, declared hard
value constraints, and guaranteed reset. Missing optional `write_semantics`
does not block an otherwise valid explicit WRITE.

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
exposes plant knowledge belongs under `validation/private/`. Generic executable
runtime access belongs under `capabilities/`; concrete connection profiles stay
under ignored `creds/`. Runtime bindings provide locators and constraints but
do not generate component-specific executable adapters.

## Validation

Validate one or more documents with:

```powershell
./spec/validation/validate-runtime-bindings.ps1 `
    -BindingPath <path-to-runtime-bindings.json>
```

Run the committed contract tests with:

```powershell
./tests/schema/test-runtime-bindings.ps1
```

The public example under `examples/runtime-bindings/` is synthetic and must not
be treated as a real plant binding.

## Candidate promotion and versioning

Treat the runtime-binding candidates supplied to an agent task as a frozen
baseline. Preserve timestamped raw reads, create the next binding-document
version, and promote only the bindings directly supported by retained
`runtime_observation` evidence. Keep rejected, absent, conflicting, and stale
candidates visible with their reasons.

The new version must retain the canonical asset identity, verified datatype,
interaction semantics, feedback classification, limitations, and provenance.
Discovery of a replacement symbol by name is not sufficient for validation.
A current value requires a fresh READ, and any WRITE remains subject to the
exact human-approval boundary in [AGENTS.md](../AGENTS.md).
