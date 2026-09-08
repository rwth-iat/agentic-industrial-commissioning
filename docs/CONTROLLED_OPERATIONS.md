# Controlled operations

## Purpose

A controlled-operation document describes a bounded sequence over runtime
binding IDs. It records preconditions, state-changing and observational steps,
restore behavior, approval scope, evidence, and verification status without
embedding concrete PLC symbols or connection endpoints.

The active contract is `spec/controlled-operation.schema.json` at version
`0.1.0`.

```text
Canonical asset identity
        v
Runtime binding ID
        v
Controlled operation step
        v
Generic capability recipe
        v
Explicit approval and execution
        v
Observed result and evidence
```

An operation document is not proof of current plant safety and is not an
authorization token.

## Step model

The contract supports:

- `write_binding_guarded`: compare the current value, write once, and verify;
- `pulse_request`: pulse a request binding and verify a separate
  acknowledgement binding;
- `wait_condition`: wait for a binding condition;
- `observe`: record or verify an expected observation;
- `delay`: preserve a validated staging interval.

Steps reference binding IDs only. Runtime locators, datatypes, units, access
direction, and request semantics are resolved through the referenced runtime
binding document.

## Restore and failure behavior

A state-changing operation cannot claim that restoration is not applicable. It
must either provide an explicit restore sequence or declare `manual_only` with
a rationale.

Restore is part of the reviewed operation, but it must not be assumed to be
universally safe. Current plant state still has to be inspected before any
restore step is executed. `restore_then_stop` expresses the intended failure
policy; it does not authorize blind cleanup after preconditions have changed.

## Status and evidence

- `draft`: proposed but not reported as executed;
- `reported_success`: a credible source reports success, but direct runtime
  evidence has not been preserved;
- `validated`: preserved runtime-observation evidence supports the operation;
- `stale`: previously useful but no longer current;
- `rejected`: disproven or unsafe for the documented context.

The validator requires a `validated` operation to reference a
`runtime_observation` source. A narrative exploration summary remains
`reported_success` until a reproducible run preserves direct evidence.

## Validation

Validate a standalone operation:

```powershell
./scripts/validate-controlled-operation.ps1 `
    -OperationPath <operation.json>
```

Cross-check its binding references and access directions:

```powershell
./scripts/validate-controlled-operation.ps1 `
    -OperationPath <operation.json> `
    -RuntimeBindingPath <runtime-bindings.json>
```

The public example under `examples/controlled-operations/` is synthetic. Real
plant operation documents belong to an ignored case `private/` subdirectory
unless they have been explicitly sanitized for publication.

## Execution boundary

Schema validation does not execute an operation. The implementation provides
generic recipes and an approval-oriented dispatcher, but no general automatic
runner for arbitrary controlled-operation documents. One narrowly bounded
multi-step request/acknowledgement actuation is available as an experimental
recipe; it does not turn an arbitrary structurally valid plan into executable
authorization.

Before a state-changing recipe is invoked, the agent must present the exact
operation, current preconditions, expected effect, verification method, and
remaining uncertainty to the human. The human must explicitly approve that
operation in the current context.
