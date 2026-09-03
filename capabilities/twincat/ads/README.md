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

## Capability index

| Recipe | Typical ADS port | API pattern | Safety | Verification |
|---|---:|---|---|---|
| `read-system-state.ps1` | 10000 | `ReadState()` | `READ_ONLY` | verified |
| `read-plc-state.ps1` | 851 | `ReadState()` | `READ_ONLY` | verified |
| `list-symbols.ps1` | 851 | `GetSymbols($false)` | `READ_ONLY` | verified |
| `search-symbols.ps1` | 851 | symbol-table filter | `READ_ONLY` | verified |
| `read-symbol.ps1` | 851 | `ReadSymbol()` | `READ_ONLY` | prepared, not verified with a preserved value |
| `system-config-to-run.ps1` | 10000 | `WriteControl(Reset)` | `STATE_CHANGING` | verified |
| `system-run-to-config.ps1` | 10000 | `WriteControl(Reconfig)` | `STATE_CHANGING` | experimental; final readback pending |

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

## Output and evidence

Recipes return PowerShell objects so callers can serialize the result. A case
run should preserve relevant raw output under `cases/<case-id>/raw/`, then
derive canonical fragments with explicit source, evidence, status, and
confidence. Raw ADS output must not bypass the canonical model on its way into
matching or generation logic.
