# Stage 2 component runbook

**Runbook version:** `0.4`

## Purpose and boundary

This runbook defines the minimal component-scoped Stage 2 workflow for an
existing automation project. A user may identify a component and objective in
natural language. The agent resolves that description to a canonical asset,
selects the focused component package and required dependencies, validates the
runtime path, and feeds supported live knowledge back into versioned private
artifacts.

Separate component packages are sufficient; a merged project-wide software or
runtime model is not required. `AGENTS.md` remains authoritative for safety,
privacy, uncertainty, and repository boundaries. Contract details remain in
the corresponding model documentation and are not repeated here.

## Identity resolution

The user does not need to supply an asset ID, runtime locator, binding ID, or
component-package path. The agent must resolve them from the case evidence and
canonical model. It records the selected canonical asset ID and evidence in the
run manifest. If multiple components remain plausible, it presents the
candidates and stops for a user decision instead of choosing arbitrarily.

A focused package may expand to other component packages when dependencies are
needed to interpret the requested component. The agent must not infer permission
or physical meaning merely from a name, comment, locator, or writable datatype.

## Workflow

### 1. Read-only validation

Every component run starts as a separately bounded read-only phase:

1. Read `AGENTS.md`, this runbook, the capability catalog, the canonical model,
   and the selected component and dependency packages.
2. Create the run manifest before live access. Record a unique run ID,
   repository revision, actual model and reasoning setting, exact filled prompt,
   input paths, and SHA-256 hashes. Record an explicit `unknown` when model or
   reasoning metadata is unavailable; do not silently omit the field.
3. Confirm the connection path and runtime state without exposing secrets.
4. Use catalogued `READ_ONLY` capabilities. Resolve required binding candidates,
   verify runtime datatypes, and preserve timestamped values and metadata.
5. Compare live observations with the static artifacts and retain agreements,
   contradictions, missing locators, ambiguity, and unavailable information.
6. Validate every changed contract and cross-document reference.

This phase never authorizes PLC writes, request pulses, mode or controller-state
changes, deployment, configuration activation, or physical actuation. If it
cannot continue read-only, it stops and preserves the partial evidence.

For a sensor or a read-only objective, the run ends here. For an actuator, the
agent reports whether modes, ownership, functional requests, conditions,
interlocks and protections, feedback independence, timeouts, stop behavior, and
restoration are sufficiently understood to prepare an operation.

### Fresh values and repeated reads

In a runtime conversation, `current`, `now`, `momentan`, `aktuell`, `jetzt`,
`erneut`, and equivalent wording always request a new live acquisition after
the user's message. The agent must not answer such a request from the previous
sample, even when the user asks for a very fast or very short response. Report
the acquisition timestamp with the value. If a new read is unavailable, label
the previous value as `last known`, include its timestamp, and report the live
read blocker instead of presenting it as current.

Repeated reads of the same component and objective may remain part of the
active run while its repository revision, selected binding, connection context,
and safety boundary remain unchanged. Preserve each acquisition as a distinct,
timestamped sample below that run. Start a new run when the component,
objective, selected binding version, repository revision, connection context,
or safety boundary changes materially.

A changing process value is observation data, not by itself new model
knowledge. It therefore does not create a new runtime-binding, readiness,
software-model, implementation-link, or hardware-model version. Version a
contract only when the new observation changes a locator, datatype, access
path, semantic claim, status, confidence, limitation, or readiness decision.

### 2. Actuator operation preparation

Only after a successful read-only actuator assessment may the agent create a
case-private controlled-operation document with status `draft`. It references
runtime-binding IDs rather than copying locators and defines the exact bounded
request, preconditions, acknowledgements, independent observation where needed,
timeouts, abort behavior, stop, restore, and approval scope.

Preparation does not execute the operation. If any required condition or restore
path remains unresolved, the agent records the blocker and stops. Otherwise it
validates the draft and presents the resolved asset, intended effect, maximum
duration, current preconditions, observation method, remaining uncertainty,
restore behavior, document location, and hash.

### 3. Exact approval and execution

A state-changing action requires a new user message approving the exact plan in
the current plant state. Approval applies once and does not carry over when the
plan, hash, effect, duration, target, prerequisite, ownership, or runtime state
changes. The agent rechecks all preconditions immediately before executing and
does not improvise or retry after a mismatch.

## Evidence and artifact feedback

Preserve raw runtime output under
`cases/<case-id>/raw/runtime/<run-id>/`, derived run assessment and validator
output under `cases/<case-id>/validation/private/<run-id>/`, component contracts
under `cases/<case-id>/derived/private/components/<component>/`, and operation
drafts or results under `cases/<case-id>/results/private/controlled-operations/`.

Use the following layout as the preferred form, especially when a run contains
multiple samples:

```text
cases/<case-id>/raw/runtime/<run-id>/
├── run-manifest.json
└── observations/
    └── <timestamp>-<binding-id>.json

cases/<case-id>/validation/private/<run-id>/
├── run-assessment.json
└── contract-validation.json
```

The run manifest is required, but the `observations/` subdirectory is a
recommended organization rather than a contract boundary. A single, uniquely
named observation file may be stored directly below `<run-id>/`. Multiple or
repeated acquisitions should normally use `observations/` so that they remain
grouped as samples of one run. Either form is conformant when the evidence is
unambiguous, timestamped, private, and referenced by the run assessment.

Each observation preserves the raw connector result privately and also records
a normalized representation. Store normalized numeric values as JSON numbers
using the JSON decimal point, for example `626.5479`, not as locale-dependent
strings such as `"626,5479"`. When the connector returns localized text, retain
it separately as `raw_value`; a localized `display_value` may be added for human
output. Record at least the acquisition timestamp, binding ID, runtime datatype,
normalized value, unit where applicable, and read-only safety boundary.

Never overwrite the input baseline. Create a new version only where evidence
changes a claim:

| Artifact | When live evidence changes it |
|---|---|
| Runtime bindings | A locator, datatype, access path, interaction semantic, status, confidence, or limitation is confirmed, rejected, or changed. |
| Software model | Runtime evidence supports or contradicts software behavior, relations, conditions, effects, or feedback classification. |
| Implementation links | Evidence strengthens, rejects, or changes the hardware-to-software trace; symbol existence alone is insufficient. |
| Hardware model | New physical or hardware evidence supports a hardware claim; a runtime read alone is insufficient. |
| Readiness assessment | The resulting component status or referenced artifact hashes change. |
| Controlled operation | An actuator plan is prepared or an executed plan gains new evidence or status. |

Update affected references and hashes together. Promote a claim to `validated`
only when the applicable schema is supported by retained runtime-observation
evidence. A successful narrative without its raw record is not direct runtime
validation.

Run the repository contract validator for every changed contract. If that
validator is unavailable in the execution environment, a compatible fallback
may be used only when it performs both the applicable JSON Schema validation
and the repository's semantic and cross-reference checks. Record the validator,
version, result, and limitations in `contract-validation.json`. JSON parsing,
ad-hoc field inspection, or hash calculation alone is not equivalent contract
validation. Without a successful repository validator or demonstrably
equivalent fallback, preserve the observation but do not promote the affected
claim to `validated`. Successful contract validation is mandatory before an
actuator plan may proceed to exact approval and execution.

## Prompt placeholders

The prompts intentionally accept natural-language intent. The agent derives and
records the technical identities.

| Placeholder | Meaning |
|---|---|
| `<case>` | Natural case description or known case ID. |
| `<component>` | Natural component description, reference designation, or function. It need not be an asset ID. |
| `<requested-result>` | Concise desired value, state, diagnostic result, or future-operation readiness objective. The agent expands it using the resolved component-class profile. |
| `<requested-effect>` | Exact intended actuator effect, expressed functionally rather than as a PLC command. |
| `<maximum-duration>` | Maximum permitted active duration. |
| `<restore-target>` | Required final physical and logical state. |
| `<plan-hash>` | Hash displayed for the immediately preceding validated operation draft. |

The filled prompt, resolved asset ID, selected package, generated run ID, model,
reasoning setting, and input hashes form part of the private run evidence.

### Recommended `<requested-result>` profiles

After resolving the component, the agent must select the closest profile below
from the canonical component class and focused component package. The user may
state a short natural-language result and does not need to enumerate every
required state group. The selected profile defines the minimum investigation
scope for a low-capability agent and prevents omission of modes, ownership,
conditions, feedback, dependencies, or a future restore path. Adapt only the
functional nouns and intended future effect. These profiles remain generic and
must not introduce plant-specific asset IDs or runtime locators.

| Component class | Recommended requested result |
|---|---|
| Sensor | `Den aktuellen Prozesswert einschließlich Einheit, Qualität und Erfassungszeit read-only erfassen und den zugehörigen Runtime-Pfad validieren.` |
| Binary actuator | `Den aktuellen Betriebs-, Modus-, Anforderungs-, Kommando-, Rückmelde-, Freigabe-, Sperr- und Schutzzustand einschließlich relevanter Abhängigkeiten read-only erfassen und die Runtime-Pfade für eine spätere kontrollierte Zustandsänderung validieren.` |
| Modulating actuator | `Den aktuellen Betriebs-, Quellen-, Sollwert-, Stell-, Rückmelde-, Überwachungs-, Freigabe-, Sperr- und Schutzzustand einschließlich Skalierung und relevanter Abhängigkeiten read-only erfassen und die Runtime-Pfade für eine spätere kontrollierte Positionierung oder Zustandsänderung validieren.` |
| Drive or motor | `Den aktuellen Betriebs-, Quellen-, Modus-, Anforderungs-, Kommando-, Rückmelde-, Freigabe-, Schutz- und Störzustand einschließlich abhängiger Startbedingungen read-only erfassen und die Runtime-Pfade für einen späteren kontrollierten Start und Stopp validieren.` |

The profile is an agent obligation and an investigation scope, not text the
user must copy verbatim and not an instruction to write or actuate. Prompt 1
remains read-only. If a component combines multiple classes, use the union of
the applicable state groups and record why the scope was expanded.

## Minimal prompt sequence

### Prompt 1 — read-only component validation

Use for every sensor and actuator. A sensor or read-only objective ends after
this prompt.

```text
Führe im Case <case> für <component> einen komponentenbezogenen Stage-2-Lauf mit dem Ziel „<requested-result>“ durch.

Folge AGENTS.md und docs/STAGE2_RUNBOOK.md. Arbeite in diesem Lauf ausschließlich read-only. Löse die Komponente gegen das kanonische Modell auf, validiere die benötigten Runtime-Binding-Kandidaten, bewahre die Runtime-Evidenz reproduzierbar und privat auf und versioniere nur Artefakte, für die der Lauf tatsächlich neue Erkenntnisse liefert.

Berichte das Ergebnis, die aufgelöste Komponentenidentität, den Evidenzstatus, verbleibende Unsicherheit und gegebenenfalls den genauen Blocker.
```

### Prompt 2 — actuator-only operation preparation

Use only after the read-only actuator run supports further preparation.

```text
Bereite für die im vorherigen Read-only-Lauf eindeutig aufgelöste Komponente folgende kontrollierte Operation vor: „<requested-effect>“.

Maximale Dauer: <maximum-duration>
Wiederherstellungsziel: <restore-target>

Folge AGENTS.md und docs/STAGE2_RUNBOOK.md. Erstelle und validiere einen privaten Controlled-Operation-Entwurf auf Basis der nachgewiesenen Bindings. Führe nichts aus. Stoppe bei unzureichenden Voraussetzungen mit einem konkreten Blocker; andernfalls zeige den exakten Plan und fordere dessen einmalige Freigabe an.
```

### Prompt 3 — actuator-only exact approval

Fill and send only after Prompt 2 has displayed the exact current plan.

```text
Ich genehmige einmalig den unmittelbar zuvor vorgelegten Plan <plan-hash> für „<requested-effect>“, begrenzt auf <maximum-duration>, mit dem Wiederherstellungsziel <restore-target>.

Prüfe unmittelbar vorher erneut alle Voraussetzungen. Führe ausschließlich diesen Plan aus, bewahre die vollständige Ausführungs- und Wiederherstellungsevidenz privat auf und stoppe bei jeder Abweichung ohne alternativen Versuch oder Wiederholung.
```
