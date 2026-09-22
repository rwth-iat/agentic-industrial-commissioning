# Agentic Industrial Commissioning

A research prototype for vendor-independent, agentic commissioning of
industrial automation systems.

> [!CAUTION]
> This is research software, not a certified safety or real-time control
> system. Read access does not authorize writes. Every state change requires a
> current, concrete human approval and valid plant-side safety measures.

## Active research question

Can an LLM agent derive the correct industrial runtime interactions from a
natural-language goal and four structured models without a predefined planner,
workflow, runner, or component adapter?

The active MVP is intentionally small:

```text
Hardware Model
Software Model
Implementation Links
Runtime Bindings
        +
       LLM
        +
   READ / WRITE
```

A user says, for example:

```text
"Open Y20."
"What is the current flow?"
"Set the flow to 400 l/h."
"Find out why the valve does not respond."
```

The user does not provide binding IDs, PLC symbols, datatypes, or a technical
action sequence. The agent relates the four models, selects relevant bindings,
decides what to read, requests approval before a write, observes the result,
and revises its hypothesis when evidence contradicts it.

## Architecture boundary

```text
NATURAL-LANGUAGE GOAL
          |
          v
      LLM AGENT
   reads four models
   selects bindings
   decides sequence
          |
          v
      READ / WRITE
          |
          v
deterministic TwinCAT runtime
          |
          v
          PLC
```

Reasoning, semantic binding selection, and result evaluation belong to the LLM.
The deterministic runtime resolves only the exact selected binding, enforces
technical access and value constraints, performs ADS communication, and
returns actual values or explicit technical errors. The PLC retains real-time
control, interlocks, and safety functions.

The runtime does not infer intent and does not choose among semantic bindings.
The active architecture has no deterministic planner, generic runner,
supervised-probe workflow, readiness state, commissioning-record contract, or
generated component adapter.

## The four models

- The hardware model states what exists physically.
- Software models state which controller elements and semantics exist.
- Implementation links connect physical identities to software semantics.
- Runtime bindings state how a software element can be reached technically,
  including access, datatype, locator, and technical write limits.

The hardware model is normally case- or system-scoped. The other three
contracts are normally component-scoped and may occur repeatedly in a case.
The models describe the world; they do not encode a workflow.

See [Hardware Model](docs/HARDWARE_MODEL.md),
[Software Model](docs/SOFTWARE_MODEL.md),
[Implementation Links](docs/IMPLEMENTATION_LINKS.md), and
[Runtime Bindings](docs/RUNTIME_BINDINGS.md).

## READ and WRITE

READ loads a runtime-binding document, resolves the binding ID chosen by the
agent, verifies read access, performs the technical read, and returns the
observed value with its timestamp and any technical error.

WRITE resolves the chosen binding and enforces only hard technical constraints:
write access, datatype conversion, limits, allowed values, technical validity
of the explicitly selected level or pulse mode, and safe pulse reset. The LLM
selects the mode and pulse duration. Optional binding metadata may inform that
choice but is not a required runtime default. WRITE does not decide whether the
action is meaningful or safe for the process. That decision and the concrete
approval boundary remain between the human and the agent.

Remote transport is private infrastructure. A human starts and authenticates
the bridge; the agent sees only READ and WRITE and never receives the password.

## Safety and evidence

The default is read-only. A real state change requires explicit approval for
the exact component, effect, bounds, context, observation, abort condition, and
restoration path where applicable. Technical writability is never evidence of
authorization or physical safety.

Ambiguity, conflicting evidence, and rejected candidates remain explicit.
Structured runtime results may be retained unchanged under
`cases/<case-id>/raw/runtime/<timestamp>/`. They are technical evidence, not a
new orchestration contract.

Serialize each returned READ or WRITE object as one compact JSON line and append
it with:

```powershell
$eventJson = $result | ConvertTo-Json -Depth 10 -Compress
./scripts/append-runtime-evidence.ps1 `
    -CaseId <case-id> `
    -Timestamp <UTC-filesystem-timestamp> `
    -EventJson $eventJson
```

Reuse the same timestamp to append related observations to `events.jsonl`.
The writer preserves each supplied JSON line and adds no manifest, preflight,
execution record, completion record, validation state, or run-state machine.

Real plant knowledge stays under `cases/<case-id>/derived/private/`, runtime
observations under ignored `raw/` paths, and local connection profiles under
ignored `creds/`. Public examples must be synthetic. See
[Publication and private data](docs/PUBLICATION.md).

## Reset status and planning

The controlled reduction to this minimal architecture is complete. Phase 18
closed the reset after the architecture, Runtime, privacy, agentic behavior,
and reduced repository passed their applicable checks. The intentionally
unperformed Phase-14 hardcoding variant remains an explicit evidence gap.

- [Vision](docs/VISION.md) defines the research hypothesis and boundaries.
- [Roadmap](docs/ROADMAP.md) identifies the active reset and its proof points.
- [MVP milestones](docs/MVP.md) preserves completed historical results.
- [Radical reset plan](docs/AIC_RADICAL_RESET_PLAN_0-18.md) is the detailed
  migration plan.
- Superseded commissioning documentation is retained under `docs/archive/`.

Historical records and Git history preserve earlier pipelines; the active path
does not maintain compatibility wrappers for them.

## Offline verification

The active offline checks mirror the minimal architecture:

```powershell
./tests/models.tests.ps1
./tests/twincat-runtime.tests.ps1
./tests/privacy.tests.ps1
```

Run all three through `./tests/test-mvp.ps1`. The separate
`./tests/test-runtime-evidence.ps1` check verifies unchanged JSONL evidence
retention without adding a run-state contract.

## License

Licensed under the [Apache License 2.0](LICENSE).
