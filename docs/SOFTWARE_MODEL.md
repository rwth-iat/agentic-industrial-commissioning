# Static Software Model

## Purpose

The static software model is the vendor-neutral contract for evidence-backed
controller software facts and component-facing semantics reconstructed from an
engineering environment. Its active schema is
[`spec/software-model.schema.json`](../spec/software-model.schema.json), version
`0.1.0`.

The model helps an agent answer which software signal represents a component
value or request, which conditions affect it, what outcome is expected, and
which facts remain uncertain. It does not contain runtime connection details,
authorize writes, define an executable operation, or claim complete formal
verification of controller behavior.

## Contract boundary

The contracts remain separate:

- the canonical hardware model identifies physical assets, ports, interfaces,
  and physical connections;
- the static software model represents engineering objects, relations,
  component-facing signals, dependencies, coverage, and gaps;
- implementation links connect canonical hardware identities to static
  component interfaces and signals;
- runtime bindings map semantic interfaces to environment-specific runtime
  locators;
- bounded commissioning probes combine runtime bindings under the approval and
  restoration rules of the commissioning runbook; validated recurring behavior
  is codified in generated component adapters.

Static qualified names are engineering-project identifiers. They are not
validated runtime locators and must not be copied into runtime bindings without
separate discovery and evidence.

## Component queries and reuse

`scripts/query-component.py` resolves a human selector such as a reference
designation against canonical asset identities, then returns the corresponding
component interface, software objects, implementation links, hardware endpoints,
conditions, dependencies, evidence, and explicit gaps. The query reports one of
`available`, `partial`, `missing`, `ambiguous`, `stale`, `rejected`, or
`conflicting` and records whether existing knowledge can be reused or requires a
targeted reconstruction scope.

When a reconstruction manifest is supplied, source and derived revisions are
checked before reuse. Facts matching a missing component selector are returned as
bounded input for targeted reconstruction; they are not silently promoted to a
canonical asset or semantic conclusion.

The optional runtime-candidate output of `scripts/query-component.py` translates
statically evidenced qualified software objects into the separate
runtime-binding contract. Because that automatic translation cannot establish
deployed symbol existence, access rights, or safe write semantics, its generated
candidates are `inferred`, private, and read-only. A separately reconstructed
functional request candidate may record `write` or `read_write` access when the
static evidence supports that direction, but it remains unvalidated and grants
no executable authorization. Static/runtime disagreements remain visible and
prevent automatic reuse.

## Sources and revisions

Every claim carries evidence entries referencing a declared source. File-backed
sources require a SHA-256 revision. A revision records which artifact supported
the claim; it does not prove that the extractor interpreted the artifact
correctly. A later evidence-access layer must compare retained revisions with
the current source and mark affected knowledge stale rather than restamping old
answers with a new hash.

The public contract distinguishes these claim states:

- `extracted`: directly present in the cited engineering evidence;
- `inferred`: interpreted from cited evidence but not independently confirmed;
- `corroborated`: supported by at least two distinct cited sources;
- `validated`: supported by retained runtime-observation evidence;
- `rejected`: disproven, with the reason retained;
- `stale`: no longer current for the available evidence revision;
- `unresolved`: intentionally left open with a stated reason.

The semantic validator rejects unknown evidence references, requires two source
identities for `corroborated`, and prevents static-only evidence from being
marked `validated`.

## Coverage and inventory

`scope.mode` distinguishes project-wide and focused reconstruction. A focused
request must identify its starting assets, but dependencies may expand the
investigated scope. `inventory_complete` refers only to the attempted evidence
inventory; it does not claim complete software semantics.

Every inventoried canonical asset is represented by one component-interface
coverage record with one of these states:

- `reconstructed`;
- `partial`;
- `ambiguous`;
- `unresolved`.

Partial, ambiguous, and unresolved interfaces require explicit limitations.
Unsupported constructs and unexamined evidence are recorded at model scope.
Missing library internals and conflicting sources belong in `gaps`; they must
not be converted into guessed behavior.

## Conditions and expected effects

Conditions use recursive `predicate`, `all_of`, `any_of`, and `not` expressions.
Each predicate records:

- whether it references a software object or component signal;
- the comparison and expected value;
- explicit positive or negative polarity;
- the operating context, such as mode, command source, service state,
  interlock, or protection.

Command requests and manual setpoints require an expected effect. Effects may
express a state, value, range, or a value relative to another semantic signal.
This is still a static expectation. Probe timing, observation, failure, and
restore behavior belong in the bounded execution record and generated adapter,
not in the software model.

Signals classified as process values, command states, dynamic process values,
or feedback must state whether the observation is physical, independent
process feedback, calculated, logical, or unknown. Calculated PLC state must
not be presented as independent physical confirmation.

## Validation and privacy

Validate a document with:

```powershell
./scripts/validate-software-model.ps1 `
    -ModelPath <software-model.json>
```

The validator combines JSON Schema validation with reference, hierarchy,
range, evidence, status, coverage, and placement checks. Passing validation
does not prove that a semantic interpretation is correct.

Concrete plant models belong under
`cases/<case-id>/derived/private/`, `results/private/`, or
`validation/private/`. The entire case `raw/` directory is local and ignored.
Committed examples must be synthetic or explicitly sanitized. The public
example is
[`examples/software-models/process-cell.synthetic.v0.1.json`](../examples/software-models/process-cell.synthetic.v0.1.json).

## Live feedback and versioning

Commissioning runtime work starts from a frozen static software-model revision. A live
observation does not authorize overwriting that baseline. When direct runtime
evidence validates or contradicts a software relation, condition, expected
effect, datatype, or feedback classification, create the next model version and
reference the retained `runtime_observation` source.

Do not create a new software-model version merely because an ADS symbol was
read. Locator existence and access normally update the runtime-binding document.
Only supported software-semantic findings belong here, and physical truth still
belongs in the canonical hardware model. The complete feedback loop is defined
in [COMMISSIONING_RUNBOOK.md](COMMISSIONING_RUNBOOK.md).
