# TwinCAT ADS verification — 2026-09-02

## Scope

This note records the reusable technical findings from an exploratory remote
engineering session in the IAT laboratory. Local hostnames, addresses, AMS
NetIds, account names, symbol names, and installation paths are intentionally
omitted. The complete private session notes remain in the ignored local
`creds/` area.

## Environment

| Property | Observed value |
|---|---|
| Remote transport | PowerShell Remoting / WinRM through an engineering host |
| Runtime interface | TwinCAT ADS .NET |
| Assembly version | 4.0.9.0 |
| TwinCAT system service | ADS port 10000 |
| PLC runtime | ADS port 851 |

This is a record of one tested environment, not a general compatibility claim.

## Results

| Capability | Status | Evidence summary |
|---|---|---|
| Establish remote PowerShell session | verified | A human-authenticated persistent session executed commands and returned output. |
| Read TwinCAT system state | verified | `ReadState()` on port 10000 returned the observed Config and Run states. |
| Reach PLC runtime in Config mode | observed unavailable | Port 851 returned ADS error `0x6` while the system was in Config mode. |
| Request Config to Run | verified | `WriteControl(AdsState.Reset)` initiated the transition; Run was subsequently read from ports 10000 and 851 and observed independently. |
| Load PLC symbol table | verified | `CreateSymbolInfoLoader().GetSymbols($false)` returned the runtime symbol table and its metadata. |
| Search symbol metadata | verified | Names, comments, types, sizes, index groups, and offsets were inspected. |
| Read a concrete process value | prepared, not verified | The suitable `ReadSymbol()` pattern and primitive type mapping were prepared, but no returned process value was preserved in the source record. |
| Request Run to Config | mechanism identified, not fully verified | `AdsState.Config` was rejected with ADS error `0x701`; `AdsState.Reconfig` was identified as the system-service command, but the source record contains no final successful readback. |

## Derived technical findings

- A direct ADS route from the originating workstation was not required because
  the engineering host could act as the execution point for ADS communication.
- RDP was useful for independent human observation but was not part of the
  programmatic WinRM-to-ADS communication path.
- The remote bridge provides execution transport only. It does not provide
  plant semantics and is not an operation-level safety authorization system.
- Symbol names and comments provide evidence, but they are insufficient by
  themselves to establish physical meaning or authorize an action.

## Remaining verification work

- Preserve and validate an actual primitive process-value read.
- Repeat Run-to-Config with before/after state evidence under an explicitly
  approved safe test condition.
- Verify behavior with additional TwinCAT ADS API versions before broadening
  the compatibility statement.
- Add controlled negative tests for unavailable routes, incorrect datatypes,
  and failed state transitions.

## Repository integration check — 2026-09-03

The versioned bridge implementation was exercised end to end against the same
class of engineering path using ignored local configuration:

- `remote.local.psd1` was imported successfully;
- a human credential source established the WinRM session;
- the loopback bridge accepted a generic read-only shell probe;
- `Invoke-AgentRemote.ps1` transmitted the system-state recipe and its named
  arguments separately;
- the remote ADS recipe returned a TwinCAT system state;
- the bounded test bridge exited normally and removed its transient state file.
- the human-facing ADS selector resolved `ReadSystemState` through the catalog,
  loaded the ignored local ADS configuration, and returned a system state;
- the selector's offline checks confirmed that state-changing catalog entries
  are excluded from its list and rejected on direct invocation.

No controller-state change, symbol write, output actuation, deployment, or
configuration activation was performed during this integration check.
