# TwinCAT ADS supervised bounded actuation — 2026-09-04

## Scope

This note records a state-changing repository-path verification performed after
the human confirmed the current plant safety conditions and approved the exact
operation. Concrete endpoints, credentials, asset identifiers, and PLC symbols
remain in ignored private case evidence.

This is evidence from one TwinCAT ADS environment. It is not a general claim
about other controller versions, projects, plants, or safety conditions.

## Fail-closed discovery and correction

The initial attempt stopped before writing because the guarded recipe searched
for a nested member only in the top-level symbol collection. A final read-only
snapshot confirmed that the asset remained in its initial inactive state.

The implementation was corrected to resolve exact symbols through
`FindSymbol()` while retaining runtime-state, datatype, writability,
initial-value, acknowledgement, timeout, and request-cleanup checks. Offline
regression tests passed before the supervised rerun.

## Successful supervised rerun

The agent composed the approved operation from the generic read, wait, and
request-pulse capabilities. The run:

- verified the initial controller, PLC, mode, request, command, and feedback
  states read-only;
- completed four approved Boolean request/acknowledgement transitions;
- observed the requested active feedback before starting a five-second hold;
- requested return to the inactive state and verified the corresponding
  feedback;
- restored the initial operating mode and confirmed that all request signals
  were cleared;
- preserved a final read-only snapshot; and
- received independent human confirmation of the physical movement.

## Verification result

| Capability | Result |
|---|---|
| Exact nested symbol resolution | verified through `FindSymbol()` |
| `ReadSymbol` | verified in the recorded environment |
| `WaitSymbolCondition` | verified in the recorded environment |
| `PulseBooleanRequest` | verified in the recorded environment |
| `WriteSymbolGuarded` | not exercised; remains experimental |
| Run-to-Config transition | not exercised; remains experimental |

The PLC feedback tracked the human-observed movement, but its independence from
calculated controller logic was not established. The public verification status
therefore describes the technical capability only; it does not certify plant
safety or physical-feedback architecture.
