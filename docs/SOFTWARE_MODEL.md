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
  locators.

The LLM uses these contracts together to choose relevant READ and WRITE
bindings. The software model does not define an executable operation or fixed
commissioning sequence.

Static qualified names are engineering-project identifiers. They are not
validated runtime locators and must not be copied into runtime bindings without
separate discovery and evidence.

## Component selection and reuse

The LLM relates the requested component directly across the hardware model,
software model, implementation links, and runtime bindings. It preserves
missing, ambiguous, stale, rejected, and conflicting claims instead of hiding
them behind a deterministic component-query or reconstruction tool.

Existing component contracts may be reused only when their identities,
revisions, evidence, and known limitations fit the current task. Static
qualified names do not establish deployed runtime symbols, access rights, or
safe write behavior. Those claims remain in the runtime-binding contract with
their own evidence and status; disagreements between static and runtime
evidence remain explicit.

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
This is still a static expectation. The LLM decides observation timing, failure
handling, and any required restoration for the current approved action; those
decisions do not belong in the software model.

Signals classified as process values, command states, dynamic process values,
or feedback must state whether the observation is physical, independent
process feedback, calculated, logical, or unknown. Calculated PLC state must
not be presented as independent physical confirmation.

## Validation and privacy

Validate a document with:

```powershell
./spec/validation/validate-software-model.ps1 `
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
belongs in the canonical hardware model. The agent decides which feedback to
read and how it bears on the user's goal; the model does not encode that
sequence.
