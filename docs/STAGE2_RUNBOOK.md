# Stage 2 component runbook

**Runbook version:** `0.1`

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
2. Record a unique run ID, repository revision, actual model and reasoning
   setting when available, exact filled prompt, input paths, and SHA-256 hashes.
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

## Prompt placeholders

The prompts intentionally accept natural-language intent. The agent derives and
records the technical identities.

| Placeholder | Meaning |
|---|---|
| `<case>` | Natural case description or known case ID. |
| `<component>` | Natural component description, reference designation, or function. It need not be an asset ID. |
| `<requested-result>` | Desired value, state, or diagnostic result. |
| `<requested-effect>` | Exact intended actuator effect, expressed functionally rather than as a PLC command. |
| `<maximum-duration>` | Maximum permitted active duration. |
| `<restore-target>` | Required final physical and logical state. |
| `<plan-hash>` | Hash displayed for the immediately preceding validated operation draft. |

The filled prompt, resolved asset ID, selected package, generated run ID, model,
reasoning setting, and input hashes form part of the private run evidence.

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

