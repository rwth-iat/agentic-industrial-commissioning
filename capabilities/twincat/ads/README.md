# TwinCAT ADS capability set v0.1

This capability set contains minimal PowerShell recipes for the TwinCAT ADS
.NET API. The patterns were practically explored with `TwinCAT.Ads` 4.0.9.0;
compatibility with other API generations is not implied.

## Contents

```text
ads/
├── README.md
├── catalog.psd1
├── config.example.psd1
├── recipes/
│   ├── read-only/
│   └── state-changing/
└── verification/
```

Local endpoints and installation paths are deliberately absent. Supply them as
explicit recipe parameters or copy `config.example.psd1` to an ignored local
configuration under `creds/`.

For direct human use, the catalog is presented by
`scripts/capabilities/twincat/Invoke-AdsCapability.ps1`. Running that command
without parameters opens a read-only selection menu; `-List` prints the same
choices without contacting a remote system.

State-changing entries are exposed only through
`scripts/capabilities/twincat/Invoke-AdsControlledAction.ps1`. Its default mode
prepares and hashes the exact operation without contacting the bridge.
Execution requires a separate `-Execute` call with the matching approval
phrase.

## Capability index

| Recipe | Typical ADS port | API pattern | Safety | Verification |
|---|---:|---|---|---|
| `read-system-state.ps1` | 10000 | `ReadState()` | `READ_ONLY` | verified |
| `read-plc-state.ps1` | 851 | `ReadState()` | `READ_ONLY` | verified |
| `list-symbols.ps1` | 851 | `GetSymbols($false)` | `READ_ONLY` | verified |
| `search-symbols.ps1` | 851 | symbol-table filter | `READ_ONLY` | verified |
| `read-symbol.ps1` | 851 | `ReadSymbol()` | `READ_ONLY` | verified in one supervised environment |
| `wait-symbol-condition.ps1` | 851 | poll `ReadSymbol()` | `READ_ONLY` | verified in one supervised environment |
| `system-config-to-run.ps1` | 10000 | `WriteControl(Reset)` | `STATE_CHANGING` | verified |
| `system-run-to-config.ps1` | 10000 | `WriteControl(Reconfig)` | `STATE_CHANGING` | experimental; final readback pending |
| `write-symbol-guarded.ps1` | 851 | compare + `WriteSymbol()` + readback | `STATE_CHANGING` | experimental |
| `pulse-boolean-request.ps1` | 851 | Boolean request pulse + separate acknowledgement | `STATE_CHANGING` | verified in one supervised environment |
| `bounded-boolean-request-actuation.ps1` | 851 | four request/acknowledgement transitions + monitored hold + restore | `STATE_CHANGING` | experimental wrapper; composed pattern verified |

Ports 10000 and 851 are technical TwinCAT conventions. The target AMS NetId,
remote host, DLL location, and PLC symbol names are local configuration and are
not defaults in the recipes.

## Observed ADS semantics

For the tested legacy API and setup:

```text
Config -> Run: WriteControl(AdsState.Reset) on port 10000
Run -> Config: WriteControl(AdsState.Reconfig) on port 10000
```

Sending `AdsState.Config` directly was not supported by the tested system
service. PLC runtime port 851 was unavailable while the system was in Config
mode and became available after the system reached Run. These are observed
results, not universal guarantees; see [`verification/`](verification/).

## Recipe use

The recipes contain no remote-transport logic. For normal human use, start the
bridge and use the selector, which loads the local configuration and supplies
the correct port and recipe parameters automatically:

```powershell
.\creds\Start-AgentRemoteBridge.ps1
```

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1
```

For low-level agent use, transmit a recipe and its arguments separately:

```powershell
$adsConfig = Import-PowerShellDataFile '.\creds\twincat-ads.local.psd1'

.\scripts\remote\Invoke-AgentRemote.ps1 `
    -ScriptPath '.\capabilities\twincat\ads\recipes\read-only\read-system-state.ps1' `
    -Arguments @{
        NetId = $adsConfig.NetId
        Port   = $adsConfig.SystemPort
        AdsDll = $adsConfig.AdsDll
    }
```

The bridge serializes the argument map separately and invokes the transmitted
recipe with named parameters on the engineering host.

Never infer plant semantics from a symbol name alone: inspect its name,
comment, type, size, surrounding symbols, canonical evidence, and provenance.

State-changing recipes require both explicit user authorization for the exact
operation and verification of the applicable plant safety conditions. The
`-HumanApproved` switch prevents accidental direct invocation but does not
satisfy either requirement by itself.

An `experimental` recipe must not be represented as verified merely because its
underlying API mechanism has been identified.

`write-symbol-guarded.ps1` checks the PLC runtime state, symbol existence,
runtime datatype, writability, expected current value, and mandatory bounds for
numeric writes before writing once. It polls for the requested readback value
and stops on any mismatch.

`pulse-boolean-request.ps1` requires a Boolean request symbol and a separate
primitive acknowledgement symbol. It verifies the initial acknowledgement,
pulses the request, clears it, and waits for the expected acknowledgement. This
supports cyclic request/active handshakes without treating the request bit
itself as persistent state. Exact and nested TwinCAT symbols are resolved with
`FindSymbol()` before the datatype and writability checks are applied.

`bounded-boolean-request-actuation.ps1` is the preferred high-level recipe when
an actuator exposes separate requests for entering a controllable mode,
activation, deactivation, and leaving that mode. It verifies inactive initial
state, monitors the active acknowledgement throughout the approved hold, and
attempts deactivation followed by mode restoration from `finally`. It does not
write a mapped hardware output directly. The wrapper remains experimental
until it has completed its own supervised repository-path run.

The repository path was live-verified on 2026-09-04 with a supervised,
time-bounded binary-actuator sequence. The agent performed read-only prechecks,
requested an operating mode, requested actuation, waited for runtime feedback,
held the approved state for five seconds, restored the initial command and mode,
and verified the final logical state. A human independently confirmed the
physical movement. This verifies the technical recipe in one environment; it
does not establish that PLC feedback is independent physical feedback or that
the same operation is safe elsewhere.

## Output and evidence

Recipes return PowerShell objects so callers can serialize the result. A case
run should preserve relevant raw output under the local, Git-ignored
`cases/<case-id>/raw/` area, then derive canonical fragments with explicit
source, evidence, status, and confidence. Raw ADS output must not bypass the
canonical model on its way into matching or generation logic.
