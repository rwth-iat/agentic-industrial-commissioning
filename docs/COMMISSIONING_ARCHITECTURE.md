# Commissioning architecture

## Decision

The active development focus is agentic commissioning of a brownfield system
with an existing PLC application. Static reconstruction remains the completed
upstream foundation. Greenfield project generation and continuous process
control remain future concerns.

The commissioning agent receives trusted, versioned offline knowledge and uses
live access to verify, correct, and operationalize one requested component
interaction at a time.

## Input contracts

There are four contract types, not four monolithic files:

1. The hardware model describes the case or system and its physical structure.
2. A software model describes the controller-facing semantics of one component.
3. Implementation links trace that component between hardware and software.
4. Runtime bindings locate that component's relevant runtime interfaces.

Software models, implementation links, and runtime bindings therefore occur
once or more per component in the component's case-specific package. A
commissioning run resolves the relevant component package and the corresponding
slice of the system-wide hardware model.

The offline documents are the run's initial knowledge baseline. They are not
immutable truth: live evidence may contradict them. Corrections create a new
version of the affected component artifact and preserve provenance; unrelated
contracts are not rewritten.

## Runtime flow

```text
High-level component objective
              |
              v
System hardware model + component package
              |
              v
Read-only runtime preflight
              |
              v
Interaction-scoped assessment
  hard_blocked | ready_for_supervised_probe | validated_interface
              |
              v
Exact human approval when a state change is required
              |
              v
Bounded probe: act -> observe -> abort or restore
              |
              v
Evidence + targeted model correction
              |
              v
Generated deterministic component adapter
              |
              v
Reuse; reassess after relevant change or failure
```

The assessment belongs to the tuple of component, requested interaction, input
revisions, and current runtime context. It is computed from evidence rather
than stored as a permanent component property.

- `hard_blocked` means that harm cannot currently be bounded sufficiently. The
  result must name the blocker, required evidence or mitigation, and a concrete
  reevaluation condition.
- `ready_for_supervised_probe` means that remaining uncertainty can be learned
  through a reversible, time-bounded, explicitly approved interaction.
- `validated_interface` means that runtime resolution, semantics, observed
  effect, restoration, and the generated deterministic interface are evidenced
  for the recorded revisions and context.

## Responsibility boundaries

- The PLC or another deterministic controller retains hard real-time control,
  interlocks, and safety functions.
- A connector owns transport, session handling, and environment-specific
  access. It does not assign plant semantics.
- Capabilities provide reusable low-level technical reads and guarded writes.
- The agent combines available knowledge and capabilities during exploration.
- A generated component adapter exposes the validated semantic interface, for
  example `GetState`, `Open`, `Close`, or `OpenFor`, using binding identifiers
  instead of duplicating concrete runtime locators.
- A deterministic multi-component procedure is generated only when a recurring
  sequence is actually required. It composes component adapters.

The component adapter is the durable result of successful exploration. The
exploratory sequence itself need not become another static knowledge contract.

## Safety and evidence

Removing a separate operation-plan contract does not remove its safety
properties. Any state-changing probe still requires:

- exact, current human approval;
- verified scope, limits, timeout, abort, and restore behavior;
- observation during execution;
- a retained execution record with input revisions and outcomes;
- invalidation when relevant project, binding, configuration, hardware, or
  observed behavior changes.

The target architecture retains concise run artifacts such as a run manifest,
preflight result, and execution record. It does not require a separate
persistent operation-plan contract or a permanent readiness document before the
agent may perform a probe. Their compact technical contract is documented in
[COMMISSIONING_RECORDS.md](COMMISSIONING_RECORDS.md).

Historical MVP evidence remains historical evidence. Reorienting the active
architecture does not rewrite what earlier proof points demonstrated.

## Relation to MHS

An MHS-like driver can be an output facade over validated component adapters.
This repository's distinct brownfield role is to reconstruct and validate that
facade from hardware, controller software, implementation traceability, runtime
bindings, and live evidence. MHS compatibility does not move hard real-time or
safety behavior out of the PLC.

## Immediate acceptance target

The first vertical slice is complete when one component can be selected from a
high-level request, pass read-only preflight, undergo an approved bounded probe,
retain sufficient evidence, and produce a deterministic reusable component
adapter without requiring a separate persistent operation plan.
