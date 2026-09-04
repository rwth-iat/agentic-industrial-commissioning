# Technical Capability Library

This directory contains reusable, vendor- or interface-specific technical
recipes that an engineering agent can inspect and adapt.

A capability describes **how a technical interaction can be performed**. It
does not assign plant semantics and it is not a replacement for the canonical
hardware model.

## Architectural boundary

```text
Canonical Hardware Model
        | identifies assets, channels, semantics, and evidence
        v
Capability recipe
        | provides a reusable technical access pattern
        v
Environment-specific connector or agent adaptation
        | supplies local configuration and produces case evidence
        v
Remote transport, engineering system, or runtime
```

- `capabilities/` contains curated, reusable technical patterns.
- `generated/connectors/<environment-id>/` contains environment-specific
  adaptations and extraction code.
- `cases/<case-id>/` contains evidence and results for a concrete system.
- `scripts/remote/` contains generic remote-execution transport tooling.
- `scripts/capabilities/` contains human-facing selectors that resolve catalog
  entries and invoke recipes without duplicating their implementation.
- `creds/` contains ignored local credentials, endpoints, profiles, and
  transient state. Capability recipes must not depend on files in this folder
  being present in another checkout.

Vendor-specific implementations are allowed here. Vendor-specific assumptions
must not enter `src/commissioning_core/` or the canonical schema.

## Lifecycle

```text
exploration -> working procedure -> verification -> curated recipe
```

A procedure should only be promoted into this library when it has either been
practically verified or is clearly marked as experimental. Verification notes
record the tested versions, preconditions, observed result, limitations, and
remaining uncertainty without publishing local endpoints or credentials.

## Safety classes

- `READ_ONLY`: does not intentionally alter controller, runtime, configuration,
  outputs, or plant state.
- `STATE_CHANGING`: can alter an engineering system, controller, runtime, or
  physical process and requires a separate explicit human approval and a
  verified safe plant state.

A command-line flag is only a defensive check. It is not itself proof of human
approval or plant safety.

Repository-wide agent rules, including the rules for using and extending this
library, are defined in the root `AGENTS.md`.

## Human and agent use

Agents may inspect the catalog and invoke an appropriate recipe with explicit
parameters. Humans should normally use a selector under `scripts/capabilities/`
rather than assemble low-level recipe arguments manually. A read-only selector
must not expose state-changing entries; state changes require a separate,
approval-oriented workflow.

The controlled selector prepares an exact operation and derives an
operation-bound approval phrase before it can invoke a state-changing recipe.
That phrase is a defensive guard only: it does not prove that a human approved
the operation or that the plant is safe.

For controlled actuator behavior, prefer a discovered functional interface
with request and acknowledgement semantics over a direct hardware-output
write. A time-bounded request must be represented as one complete operation,
including feedback observation and restoration, so the implementation matches
the operation shown for approval.
