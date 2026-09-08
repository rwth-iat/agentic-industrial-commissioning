# Static software reconstruction: implementation and acceptance plan

**Status:** `ACTIVE` — WP1 through WP3 are complete. Three bounded independent
agent runs passed on 2026-09-08; WP4 remains incomplete because the full frozen
scenario set was not executed.

This is a bounded static-reconstruction extension supporting Stage 2 in
[ROADMAP.md](ROADMAP.md). The completed MVP 1 and MVP 2 records remain unchanged.
The previous software-feature implementation was withdrawn; its generated
answers are not an implementation baseline or acceptance oracle.

## Accepted objective

An agent reconstructs component-facing software knowledge from the available
engineering evidence and reconciles it with canonical hardware knowledge.
Components come from the case's BOM, hardware model, and other actual evidence;
they must not be built into the extraction tool. A BOM is useful but not mandatory.

1. Inventory the available evidence and components. Use an existing BOM and
   hardware model as starting points while retaining their uncertainty.
2. Reconstruct evidenced hardware/software paths and relevant dependencies.
3. Preserve missing information, alternative mappings, conflicts, and inaccessible
   library internals explicitly.
4. Support both project-wide reconstruction and a component-focused request.
   A focus limits the starting scope, not the dependencies that must be inspected.
5. Persist concrete plant knowledge in ignored private case artifacts. The
   generic core consumes derived contracts, never raw vendor project files.

For project-wide requests, report every inventoried component as reconstructed,
partially reconstructed, ambiguous, or unresolved, with evidence and reasons.
Inventory coverage is distinct from semantic completeness. Discoveries in software
are not automatically proof of physical installation, and omission from one source
is not proof of absence. Canonical asset identities must be preserved when known.

## Responsibility and contract boundaries

| Part | Responsibility |
|---|---|
| Agent | Select evidence, discover access methods, reconcile identities, interpret semantics, investigate gaps, and persist supported conclusions. |
| Replaceable adapter | Extract project facts through suitable files, exports, or APIs; preserve source locations and declare extraction limits. |
| Generic core | Validate and assemble derived contracts, resolve references, expose component knowledge and dependencies, and report conflicts and incompleteness. |
| Evaluator | Compare retained outputs against independently reviewed evidence and expected outcomes. |

Retain separate hardware, software, implementation-link, runtime-binding, and
controlled-operation contracts. Design the two new contracts from evidence-backed
requirements; do not extend the hardware schema with PLC implementation details.
Static qualified names identify engineering objects, not validated runtime locators.
Conditions need explicit polarity, logical composition, and operating context.
An expected outcome must express the requested effect, including setpoint-relative
values where necessary, and distinguish logical/calculated from physical feedback.

No full PLC-code canonicalizer or complete formal proof of program behavior is
required. A parser may have a bounded supported subset, but it must identify
unsupported or unexamined constructs instead of silently implying full coverage.
Vendor syntax knowledge is allowed in adapters; baked-in plant answers are not.

## Work packages

Each package is intended as one coherent implementation assignment including its
tests and documentation. Execute them in order; do not require routine user
confirmation inside a package. Material unresolved design choices remain explicit.

### WP1 — Contracts and acceptance specification

**Status:** `COMPLETED` on 2026-09-08. This establishes contracts and fixed
acceptance criteria only; it does not establish reconstruction capability.

Completion evidence:

- `spec/software-model.schema.json` and
  `spec/implementation-link.schema.json` define the versioned contracts;
- the semantic validators reject dangling identities, false validation,
  reversed ranges, invalid condition or effect references, port-ownership and
  direction errors, and private-placement failures;
- public process-cell examples and 24 positive and negative synthetic contract
  cases run without private V03 evidence;
- `docs/SOFTWARE_RECONSTRUCTION_ACCEPTANCE.md` freezes the initial prompts,
  isolation boundary, scoring rubric, hard failures, and retained run record;
- the repository privacy test verifies ignored `raw/` and private case paths
  while keeping public examples visible.

- Review actual project evidence to identify requirements without fixing component
  names or sample answers as the reconstruction algorithm.
- Add software and implementation-link contracts, semantic validators, and public
  synthetic examples. Keep existing contract behavior compatible.
- Replace or sanitize public example references that depend on legacy tracked
  case `raw/` files before those files are removed from Git tracking.
- Specify evidence, stable references, provenance, source revisions, incomplete
  coverage, conditional dependencies, expected effects, and feedback independence.
- Check cross-document identity and port ownership, unresolved references, ranges,
  status/evidence consistency, and actual private placement.
- Define the acceptance prompts and scoring rules before implementing extraction.

**Done when:** independent positive and negative synthetic fixtures exercise these
requirements; existing regressions pass; acceptance criteria are reviewable.
Passing this package does not establish reconstruction capability.

### WP2 — Evidence extraction and agentic reconstruction

**Status:** `COMPLETED` on 2026-09-08 for the bounded static, read-only scope.

Completion evidence:

- `generated/connectors/twincat-static-project/` inventories source files,
  declarations, instances, calls, assignments, configured I/O links, hardware
  nodes, libraries, and code-like inactive fragments without a component table;
- the adapter emits SHA-256 source and fact revisions and declares its unsupported
  constructs; `scripts/check-reconstruction-freshness.py` rejects a derivation
  whose recorded fact revision no longer matches;
- public fixtures with unrelated names verify that a rename, an added instance,
  and a changed mapping alter the facts without editing the adapter;
- V03 was processed as an ignored private case. Its hardware model, software
  model, implementation links, manifest, and reconstruction review validate
  against the WP1 contracts while preserving unresolved and conflicting evidence;
- the run was static and read-only: no controller/runtime connection, project
  modification, deployment, or output activation occurred.

This completion establishes the implemented extraction and first-case agentic
reconstruction path. It is not the independent fresh-agent acceptance required
by WP4 and does not establish runtime validity.

- Implement or adapt the simplest suitable read-only project access for the first
  supported source format. Inventory actual declarations, instances, I/O links,
  relevant calls and assignments, and distinguish inactive code where supported.
- Let the agent reconcile these facts with hardware/BOM evidence and derive the
  semantic model. Persist reasoning evidence, alternatives, and extraction limits.
- Exercise the flow on V03 as a private development case. The component inventory
  comes from its evidence, not from the components discussed in a previous chat.
- Retain a manifest and source revisions so changed evidence invalidates affected
  conclusions. Re-running a generator must not stamp old assumptions with new
  hashes and present them as newly established facts.

**Done when:** renaming components or adding an instance changes extracted facts
without editing component tables in the tool; changed mappings are detected;
the agent's semantic derivation and unresolved items remain independently auditable.

### WP3 — Component query, reuse, and runtime integration

**Status:** `COMPLETED` on 2026-09-08 for the offline integration scope.

Completion evidence:

- `src/commissioning_core/component_knowledge.py` and
  `scripts/query-component.py` implement canonical selector resolution,
  component-scoped retrieval, freshness-gated reuse, targeted fact collection,
  and static-to-runtime candidate generation;
- public offline tests cover reusable partial knowledge, a missing component,
  stale revisions, rejected links, a preserved static/runtime datatype conflict,
  and private inferred read-only binding candidates;
- the ignored V03 case retains a reusable Y20 query and runtime candidates plus
  targeted Y14 and N15 reconstruction results, each tied to input revisions;
- all generated runtime candidates remain read-only and explicitly provide no
  executable authorization. No controller connection, runtime observation,
  write, deployment, or output activation occurred.

- Return relevant implementation paths, hardware links, conditions, dependency
  signals, source evidence, and gaps for a requested canonical component.
- Distinguish available, partial, missing, stale, rejected, and conflicting
  knowledge. Reconstruct the necessary scope when knowledge is unavailable;
  do not require a complete software model before read-only exploration.
- Persist newly derived knowledge and check its consistency on reuse.
- Connect semantic signal references to runtime-binding candidates and check asset
  identity, role, access, interaction semantics, units, and feedback classification.
  Preserve static/runtime disagreements rather than silently overwriting them.
- Document only the new contract/use behavior in the existing documentation
  structure. Do not duplicate the general workflow already in AGENTS.md.

**Done when:** offline integration scenarios cover reuse, targeted reconstruction,
stale evidence, partial results, and contradiction. Queries and validators must
not provide executable authorization or activate outputs.

### WP4 — Independent agent acceptance and honest completion record

**Status:** `PARTIALLY COMPLETED` on 2026-09-08. Three bounded offline runs with
the intended Luna model at medium reasoning passed, but the frozen initial
criteria in
[`SOFTWARE_RECONSTRUCTION_ACCEPTANCE.md`](SOFTWARE_RECONSTRUCTION_ACCEPTANCE.md)
require the complete scenario set. WP4 therefore remains open rather than being
reported as complete.

Retained private case evidence records:

- reuse and direct revision checking for existing component knowledge;
- targeted investigation of partial or unresolved component knowledge without
  forcing unsupported certainty;
- isolated focused reconstruction without a previous software model,
  implementation links, prepared component answer, query result, or runtime
  candidate. The generated private software model and implementation links pass
  the full repository validators in the source environment.

The completed runs provide useful evidence for reuse, focused reconstruction,
dependency traversal, inactive-code discrimination, condition and feedback
classification, missing-library handling, and private placement. They do not
complete the frozen project-wide, deliberately changed-evidence, or held-out
synthetic scenarios. Those scenarios are retained as not executed; the passing
bounded runs must not be generalized into full WP4 acceptance.

- Run fresh agents using the repository, actual input evidence, and a high-level
  prompt, without conversation history or prepared component answers.
- Include V03 plus a held-out synthetic project with different component names
  and structure. Synthetic evidence must be authored independently of adapter
  output; expected outcomes must be reviewed from that evidence.
- Keep reference answers, previous outputs, evaluator notes, and answer-bearing
  tests outside the tested agent's accessible workspace. A fresh chat alone is
  insufficient isolation. Record the supplied file manifest and access boundary.
- Use the intended operational model and reasoning setting, recorded before the
  run. If that model cannot be run, retain the test as pending rather than using
  another model's success as evidence of its capability.
- Preserve inputs, tool outputs, generated artifacts, failures, and evaluation
  results. Separate software-test success from agent acceptance and live evidence.

**Done when:** all required acceptance scenarios below have retained results and
meet their criteria. Report failure or pending execution explicitly; do not claim
all work packages complete based solely on unit tests or reference JSON files.

## Acceptance scenarios and decision rules

| Scenario | Required evidence of success |
|---|---|
| Project-wide reconstruction | Every inventoried component is accounted for; evidenced software paths are reconstructed or have specific, source-backed gaps. No silent component omission. |
| Focused request, no software model | Agent investigates the requested component and required dependencies and stores the result without receiving PLC symbol hints. |
| Reuse of persisted knowledge | A subsequent fresh run uses retained knowledge, checks freshness, and reports the correct semantic interface and remaining limitations. |
| Misleading name/unit and inactive code | Agent selects the evidenced active path and explains why an attractive alternative is unsuitable or unresolved. |
| Mode/source ownership and interlocks | Agent preserves polarity, logical combinations, context, and feedback independence; no unsupported condition is presented as established. |
| Renamed/added instance or changed mapping | Results follow the modified evidence without edits to baked-in asset or symbol lists. |
| Missing library or conflicting evidence | Agent identifies the specific unknown or candidate alternatives; unsupported certainty fails the case. |
| Artifact privacy and portability | All case `raw/` evidence and plant-specific outputs and logs are ignored private artifacts; generic tests run without V03/private data and public defaults contain no plant symbols or endpoints. |

For each scenario, freeze the expected questions, supported answers, justified
unknowns, and scoring criteria before execution. Reject incorrect or unsupported
answers to those questions; reject an unexplained blanket 'unknown' where the
provided evidence supports reconstruction. Report inventory coverage and semantic
coverage separately, including all unresolved findings.

Record elapsed time, tool calls, and token usage when available. Efficiency is a
comparison metric, not a substitute for correctness. Model/reasoning changes and
prompt corrections create a new run; retain earlier failures rather than replacing
them. A bounded passing run is evidence for that model and case, not a guarantee
for arbitrary brownfield systems.

## Storage and execution scope

Public changes: generic contracts, validators, query code, reusable technical
adapters without plant defaults, synthetic examples/tests, and method documentation.

Private case artifacts: all source evidence under `cases/<case-id>/raw/`, plus
source inventories, plant software/hardware fragments, implementation links,
binding candidates, reference answers, run logs, and reports under the
appropriate `derived/private/`, `results/private/`, or `validation/private/`
area. Preserve existing raw evidence without moving or editing it. Environment
adaptations stay under `generated/connectors/<environment-id>/`; if they embed
plant knowledge, establish an explicit ignore rule before writing them. Verify
actual Git ignore behavior rather than relying on a JSON classification label.

Generic tests must not read the private V03 case. Case-specific checks belong to
its validation area. Test raw-source freshness in the evidence-access layer;
do not make generic reasoning scan `raw/`.

The planned implementation and initial acceptance are offline. PLC changes,
deployment, runtime writes, actuation, and real-time control are outside this plan.
Later Stage-2 live validation remains a separate operation under existing safety
and evidence rules. This plan does not mark Stage 2 complete.
