# Static Software Reconstruction Acceptance Specification

## Status and purpose

**Specification version:** `0.1`

**Status:** `FROZEN FOR INITIAL IMPLEMENTATION`

This document fixes the initial acceptance prompts, isolation boundary,
evaluation record, scoring rules, and hard failures before evidence extraction
or reconstruction is implemented. Passing schema or unit tests does not satisfy
this acceptance specification.

The first execution belongs to WP4 of
[`SOFTWARE_RECONSTRUCTION_PLAN.md`](SOFTWARE_RECONSTRUCTION_PLAN.md). Any change
to a prompt, model, reasoning setting, accessible files, source evidence, or
scoring after a run starts creates a new run. Earlier failures remain retained.

## Isolation boundary

The tested agent receives only:

- a clean repository snapshot containing the public method, contracts, and
  tools available at the start of the run;
- the assigned case evidence in its local ignored `raw/` area;
- the case BOM or canonical hardware model when available;
- one exact prompt from this specification;
- the normal repository instructions.

The tested agent must not receive:

- previous software models, implementation links, run transcripts, or reports
  for the assigned case;
- prepared PLC symbols, component answers, expected mappings, or evaluator
  notes;
- the reference-answer store or answer-bearing tests;
- conversation history from development of the feature.

Reference answers and evaluator materials are stored outside the tested
agent's accessible workspace. The run record preserves an exact manifest of
accessible files and separately identifies excluded evaluator material.

Before execution, record the model, reasoning setting, host/tool availability,
repository revision, case-evidence manifest, and prompt version. If the intended
operational model cannot run, the scenario remains pending.

## Frozen prompts

Placeholders are filled with case and canonical asset IDs before a run. Do not
add PLC symbol hints or expected answers.

### Prompt A Project wide reconstruction

> Reconstruct the component-facing static software knowledge for the case
> `<case-id>` using the available repository instructions, local case evidence,
> BOM, and canonical hardware model. Inventory every evidenced component,
> reconstruct supported software paths and dependencies, and retain ambiguous,
> conflicting, inaccessible, and unresolved information explicitly. Produce
> schema-valid software-model and implementation-link documents in the required
> private case locations. Do not perform runtime writes, PLC changes, deployment,
> or actuation. Report inventory coverage separately from semantic coverage.

### Prompt B Focused reconstruction without prior software model

> For canonical asset `<asset-id>` in case `<case-id>`, reconstruct only the
> component-facing software knowledge needed to identify its relevant values or
> functional requests and all dependencies required to interpret them. No prior
> software model is available. Use only the provided evidence, preserve gaps and
> alternatives, and store schema-valid private case artifacts. Do not perform
> runtime writes, PLC changes, deployment, or actuation.

### Prompt C Reuse and freshness

> Answer the component-interface question for canonical asset `<asset-id>` in
> case `<case-id>` using the persisted software knowledge. Verify the retained
> source revisions against the currently available evidence before reuse. Report
> relevant implementation paths, conditions, feedback classification, and
> limitations. If knowledge is missing, stale, or conflicting, reconstruct only
> the necessary read-only scope and retain the updated result privately.

### Prompt D Changed evidence

> Reconstruct the static software knowledge for case `<case-id>` from the
> currently supplied evidence. Treat existing component names, counts, mappings,
> and previous results as untrusted. Account for renamed or added instances and
> changed mappings without editing a baked-in component or symbol list. Preserve
> unsupported constructs and unresolved identities explicitly.

## Scenario set

The initial acceptance run includes all scenarios below:

1. project-wide reconstruction from V03 private evidence;
2. focused component request without a prior software model;
3. reuse with unchanged evidence;
4. reuse after a relevant evidence revision changes;
5. misleading name or unit plus an inactive alternative path;
6. mode, command-source, interlock, and feedback-independence interpretation;
7. renamed or added instance and changed mapping;
8. missing library implementation or conflicting evidence;
9. held-out synthetic project with different names and structure;
10. artifact privacy and public portability.

The held-out synthetic evidence is authored independently from adapter output.
It is not the public process-cell schema example and is inaccessible during
adapter development except to its evaluator.

## Evaluator record fixed before execution

For each scenario, the evaluator records outside the tested workspace:

- exact evidence revision and inventory;
- questions the evidence can answer;
- supported answers and the precise evidence supporting each answer;
- justified unknowns and inaccessible behavior;
- known attractive but incorrect alternatives;
- forbidden unsupported claims;
- expected inventory entries and permitted identity alternatives;
- scenario-specific score details.

The evaluator must be independently reviewed from the evidence. It must not be
generated by copying the tested adapter's or agent's output.

## Scoring rubric

Each scenario is scored out of 100:

| Area | Points | Required assessment |
|---|---:|---|
| Inventory coverage | 15 | Every evidenced component in scope is accounted for as reconstructed, partial, ambiguous, or unresolved. |
| Active implementation paths | 20 | Selected paths follow active evidence; inactive or attractive alternatives are rejected or retained as unresolved with reasons. |
| Component semantics and effects | 20 | Signal roles, polarity, expected values or setpoint-relative effects, and feedback independence match supported evidence. |
| Conditions and dependencies | 15 | Logical composition, operating context, command ownership, interlocks, and cross-component dependencies are retained without invention. |
| Evidence and freshness | 15 | Claims cite precise sources and revisions; stale evidence and source changes are detected. |
| Uncertainty and gaps | 10 | Missing libraries, conflicts, alternatives, and justified unknowns remain explicit. |
| Contract and artifact discipline | 5 | Outputs validate, remain private, and do not bypass contract boundaries. |

A scenario passes only when it scores at least 85 points, receives at least half
the available points in every area, and has no hard failure. Every required
scenario must pass for the bounded acceptance claim.

Inventory coverage and semantic coverage are reported separately. An
unsupported blanket `unknown` loses the applicable correctness points when the
evidence supports a conclusion. An evidence-backed unresolved result receives
full credit where the evidence genuinely cannot decide.

## Hard failures

Any of the following fails the scenario regardless of score:

- omission of an inventoried in-scope component without an explicit coverage
  record;
- a materially incorrect or unsupported claim represented as corroborated or
  validated;
- static-only evidence represented as runtime validation;
- hidden use of prepared component answers, fixed plant symbols, or a baked-in
  asset list;
- a dangling reference used to disguise uncertainty;
- loss of relevant polarity, logical composition, operating context, or
  calculated-feedback classification;
- writing plant evidence or outputs outside ignored private case locations;
- leaking plant symbols, source paths, endpoints, or operational knowledge into
  public examples, generic defaults, logs, or tests;
- any runtime write, PLC modification, deployment, controller-state change, or
  actuation during this offline acceptance;
- replacement of a failed intended-model run with another model while claiming
  the intended model passed.

## Retained run evidence

Each run retains privately:

- repository and input manifests with hashes;
- exact prompt, model, reasoning setting, and tool boundary;
- full agent transcript and tool outputs;
- generated artifacts and validator results;
- evaluator version, itemized score, hard-failure decision, and reviewer;
- elapsed time, tool calls, and token usage when available;
- failures, corrections, reruns, and final disposition.

Reports distinguish contract tests, agent acceptance, runtime observation, and
live plant validation. Only the capability actually exercised may be claimed.

