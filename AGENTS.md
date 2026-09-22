# AGENTS.md

## Purpose and active focus

This repository investigates the smallest useful agentic core for industrial
commissioning. The active brownfield MVP assumes an existing PLC application
and an already reconstructed offline knowledge baseline.

The active architecture is deliberately limited to:

```text
four models + LLM + READ + WRITE
```

Static reconstruction, project modification, greenfield generation, and
broader operation remain long-term research topics. They must not add
complexity to this commissioning path.

## User interaction and agent responsibility

The user states a domain goal in natural language, for example "Open Y20" or
"What is the current flow?" The user does not need to know a binding ID, PLC
symbol, datatype, or action sequence.

The agent must:

1. interpret the goal from the four models;
2. identify the relevant physical component and controller semantics;
3. follow implementation links to plausible runtime bindings;
4. choose the required binding itself;
5. read relevant state before and after a change when needed;
6. expose ambiguity instead of choosing arbitrarily; and
7. evaluate whether the observed result satisfies the goal.

There is no deterministic planner, binding selector, runner, component adapter,
or fixed commissioning workflow between the user goal and READ or WRITE. Do
not add one. New abstractions require a concrete, experimentally demonstrated
technical need.

## The four knowledge contracts

Keep the contracts separate:

1. The hardware model describes physical systems, devices, interfaces,
   signals, connections, uncertainty, and provenance. It is normally
   case- or system-scoped.
2. Software models describe component-facing controller elements and
   semantics.
3. Implementation links trace physical identities to software semantics.
4. Runtime bindings describe concrete runtime locators, access, datatypes,
   technical write constraints, and optional technical write semantics.

Software models, implementation links, and runtime bindings are normally
component-scoped and may occur repeatedly below component-specific case
directories. The models describe the world; they do not prescribe an action
sequence. Passing a schema proves structure, not runtime truth, semantic
correctness, authorization, or plant safety.

## Runtime boundary

The agent has exactly two runtime capabilities: READ and WRITE.

The LLM owns goal interpretation, semantic binding selection, action choice,
sequencing, and result evaluation. The deterministic runtime layer only:

- resolves the exact binding ID selected by the LLM;
- checks access, datatype, conversion, technical limits, allowed values, and
  whether the explicitly selected level or pulse execution is technically
  valid;
- loads private connection configuration;
- performs the remote TwinCAT ADS operation; and
- returns actual values and technical errors without semantic reinterpretation.

Runtime code must never choose a binding from the user's goal or encode
component-specific plant behavior. Technical protection limits constrain what
may be executed; they do not constrain or replace the agent's reasoning.
The LLM selects WRITE mode and pulse duration explicitly. Optional
`write_semantics` metadata may inform that choice but its absence must not
block an otherwise valid explicit WRITE.

Remote transport, authentication, session handling, and ADS invocation are
internal infrastructure. The human starts and authenticates the remote bridge.
The agent does not manage bridge lifecycle and does not receive passwords.

## Safety and authorization

Safety takes priority over autonomy. Unless the exact state change is approved,
remain read-only. Do not activate physical outputs, change controller state,
activate configuration, deploy PLC code, start machinery, or bypass interlocks
or safety functions.

Every WRITE must be covered by concrete human approval for the current
component, intended effect, value or bounds, runtime context, relevant
observation, abort condition, and restoration path where applicable. One
approval may cover a finite sequence of explicitly described WRITEs as one
bounded operation. It remains valid across the expected intermediate states
of that operation. Recheck the conditions relevant to each step, but do not
request repeated approval for steps already covered by the bounded approval.

Approval becomes invalid when an action falls outside the approved sequence,
a value exceeds the approved bounds, an abort condition occurs, an observation
contradicts the expected intermediate state, or relevant external context
changes unexpectedly. Within a valid bounded approval, continue autonomously
until the goal is satisfied, restoration is complete, or an abort condition is
reached. Approval does not carry over to a different operation or run. A
technical `HumanApproved` flag is not proof of authorization or plant safety.

Prefer a controller-managed functional request over direct writes to mapped
outputs or internal variables. Never silently substitute a primitive write for
a requested semantic action. The PLC or another deterministic controller
retains hard real-time control, interlocks, and safety functions.

## Evidence and uncertainty

Never turn an inference into a fact silently. Preserve status, confidence,
evidence, provenance, contradictions, and rejected candidates. If multiple
identities or bindings remain plausible, present the candidates or stop.

Treat operator-provided plant or controller knowledge as attributed evidence,
not as automatically proven fact and not as something to dismiss merely
because the static models are incomplete. When operator evidence contradicts
the current interpretation, formulate the smallest testable hypothesis.
Prefer a bounded, reversible experiment through a functional controller
request and live observations. If the experiment is covered by the current
approval, perform it without another confirmation.

Uncertainty is not automatically a stop condition. Stop when ambiguity
prevents selection of a bounded safe action or when an observation crosses an
approved abort condition. Re-read only volatile conditions relevant to the
next action, abort decision, or outcome evaluation; do not repeatedly read
unchanged constants or unrelated diagnostics.

A request for a current value requires a new READ after that request; otherwise
label a reused observation as last known with its timestamp. Actual READ and
WRITE results may be retained unchanged under
`cases/<case-id>/raw/runtime/<timestamp>/`, minimally as `events.jsonl`. These
events are evidence, not a commissioning record, manifest, workflow, or run
state machine.

Do not overwrite the offline input baseline. Update only the contract whose
claim changed, preserve prior evidence and revisions, and do not use a runtime
read alone to rewrite a physical hardware claim.

## Private data and repository boundaries

Concrete plant knowledge belongs under `cases/<case-id>/derived/private/`.
Runtime observations belong under `cases/<case-id>/raw/runtime/`. Connection
profiles and optional RDP files belong under ignored `creds/`. Do not store
passwords in the repository or runtime bindings. Public examples and fixtures
must be synthetic or explicitly sanitized.

The generic models and reasoning remain vendor-independent. Vendor- and
environment-specific technical access belongs in the minimal runtime
capability, not in the models or agent reasoning.

Historical proof points remain in `docs/MVP.md`, `docs/archive/`, and Git
history. Historical artifacts are not active architectural requirements.

## Development rules

- Prefer the smallest testable change that serves the active acceptance target.
- Keep failures and uncertainty explicit.
- Keep generic behavior testable offline.
- Do not add planners, runners, adapters, workflow DSLs, registries, transport
  frameworks, or compatibility layers without demonstrated need.
- Preserve unrelated worktree changes.
- Before implementation work, consult `docs/VISION.md`, `docs/ROADMAP.md`, and
  `docs/MVP.md`.
