# Vision

## North star

A user states an industrial objective in natural language. A generic LLM agent
uses structured plant knowledge to determine the relevant technical actions,
executes only authorized actions through a minimal deterministic runtime, and
evaluates the observed result.

For the active brownfield MVP, examples are deliberately direct:

```text
"Open Y20."
"What is the current flow?"
"Set the flow to 400 l/h."
"Find out why the valve does not respond."
```

The user should not need to provide a binding ID, PLC symbol, datatype, adapter,
recipe, or action sequence.

## Active hypothesis

The central research question is whether the smallest useful agentic core is
sufficient:

```text
four models + READ + WRITE + LLM
```

The four models provide the world description:

- the hardware model describes physical systems, components, interfaces,
  signals, connections, uncertainty, and provenance;
- software models describe component-facing controller elements and semantics;
- implementation links connect physical identities with software semantics;
- runtime bindings describe concrete technical access, datatypes, locators,
  access rights, and hard write constraints.

The agent combines these models to identify the requested component, select
plausible runtime bindings, choose what to read or write, detect ambiguity,
observe feedback, and decide whether the objective was achieved.

This hypothesis is weakened, not strengthened, when those decisions are moved
into a deterministic planner, binding resolver, workflow, runner, or component
adapter. Such layers are therefore outside the active architecture unless a
concrete experiment demonstrates a technical need that READ or WRITE cannot
meet.

## Responsibility split

```text
Natural-language goal
         |
         v
     LLM agent
  semantic reasoning
  binding selection
  action sequencing
  result evaluation
         |
         v
     READ / WRITE
  technical validation
  transport and ADS
  exact observations
         |
         v
        PLC
  deterministic control
  interlocks and safety
```

The LLM decides what an action means and which declared binding represents it.
For WRITE, it also selects level or pulse execution and the pulse duration.
The runtime performs that explicit selection mechanically. It enforces
datatype, access, range, allowed-value, technically valid execution, and safe
pulse reset, but it must not infer the user's intent, choose a binding, mode,
or duration semantically, or require optional metadata as a hidden default.

Remote transport and authentication are internal infrastructure. A human owns
the authenticated bridge session. The agent does not manage that lifecycle and
does not receive credentials.

The PLC remains the deterministic real-time controller. The agent does not
reimplement interlocks, safety functions, or continuous control beside it.

## Knowledge and uncertainty

The four models are separate because they answer separate questions. A
structurally valid document is not automatically true, current, authorized, or
safe. Inference, confidence, provenance, contradictions, and alternative
candidates must remain visible.

The hardware model is normally system-scoped. Software models, implementation
links, and runtime bindings are normally component-scoped and can occur
repeatedly. A task uses the relevant model instances; it does not require a
merged project-wide software, link, or binding document.

Runtime observations can strengthen or contradict a claim, but a read does not
silently rewrite physical truth. Actual READ and WRITE outputs may be preserved
as private evidence without becoming a fifth knowledge model or an
orchestration contract.

## Human authority and safety

Minimal human interaction does not mean missing human authority. Read-only
inspection is the default. Every state-changing action needs current, concrete
human approval for the intended component and effect, bounded value or duration,
runtime context, relevant observation, abort condition, and restoration path
where applicable.

The agent must not guess through unresolved ambiguity, treat technical
writability as permission, bypass independent safety measures, or silently
replace a controller-managed request with a primitive output write. One
approval may cover a finite, explicitly described sequence as a bounded
operation, including its checks, abort conditions, and restoration. It does
not authorize actions outside that sequence or continuation after an
unexpected context change.

## Active success criterion

The active MVP succeeds when a fresh agent can receive only a natural-language
goal and the four model types, then:

1. identify the relevant component and semantics;
2. select the correct binding without a user-supplied ID;
3. use READ to acquire the state it needs;
4. expose ambiguity rather than guess;
5. explain and obtain approval for an exact state change;
6. use WRITE within declared technical constraints;
7. read the relevant feedback and evaluate the result; and
8. repeat the reasoning with changed IDs, symbols, ordering, and irrelevant
   bindings rather than relying on hardcoding.

The technical READ and WRITE path must also preserve actual values, explicit
errors, write bounds, and guaranteed reset of pulse writes.

The initial fresh-agent proof established items 1 through 7. The changed-ID
and changed-symbol robustness experiment in item 8 was intentionally not
performed during the reset closeout. That robustness claim therefore remains
an explicit evidence gap and is not treated as passed.

## Longer-term direction

Static reconstruction, modification of existing PLC projects, greenfield
generation, and broader goal-driven operation remain legitimate research
directions. They are intentionally not allowed to complicate the active MVP.
Future expansion must follow observed evidence: if the minimal agent fails,
identify the missing information or technical mechanism and add only that.

The method remains vendor-independent at the model and reasoning layers. The
first runtime proof uses the needed remote TwinCAT ADS path; support for other
vendors, transports, or standards is added only after the core hypothesis has
been tested.

## Planning and history

The active implementation order is maintained in [ROADMAP.md](ROADMAP.md).
Completed historical proof points remain in [MVP.md](MVP.md), and the detailed
reset is specified in
[AIC_RADICAL_RESET_PLAN_0-18.md](AIC_RADICAL_RESET_PLAN_0-18.md).
