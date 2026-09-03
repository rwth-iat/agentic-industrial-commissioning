# TwinCAT capability selector

`Invoke-AdsCapability.ps1` is the human-facing command-line interface for the
read-only TwinCAT ADS recipes.

## Prerequisites

- `creds/remote.local.psd1` contains the local engineering-host configuration.
- `creds/twincat-ads.local.psd1` contains the local ADS target and assembly
  configuration.
- The human has connected the required trusted network or VPN.

Tracked templates are available at `scripts/remote/config.example.psd1` and
`capabilities/twincat/ads/config.example.psd1`. Never commit the populated local
files.

Start the remote bridge in one terminal:

```powershell
.\creds\Start-AgentRemoteBridge.ps1
```

List the available read-only capabilities:

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1 -List
```

Open the interactive menu:

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1
```

Or invoke a capability directly:

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1 `
    -Capability ReadSystemState
```

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1 `
    -Capability SearchSymbols `
    -Pattern 'temperature|flow'
```

The selector loads `creds/twincat-ads.local.psd1` by default, resolves the
correct recipe and ADS port through `capabilities/twincat/ads/catalog.psd1`, and
passes configuration values as separate named arguments through the bridge.

State-changing catalog entries are intentionally excluded from the menu and
rejected by this command. They require a separate approval-oriented workflow.
