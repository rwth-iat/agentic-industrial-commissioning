# TwinCAT commissioning selectors

`Invoke-AdsCapability.ps1` exposes the read-only TwinCAT ADS catalog.
Component commissioning uses the runtime-binding-aware entry points in this
directory; callers supply binding IDs, never free PLC symbols.

## Prerequisites

- `creds/remote.local.psd1` contains the ignored engineering-host settings.
- `creds/twincat-ads.local.psd1` contains the ignored ADS target and assembly
  settings.
- The remote bridge is running through `creds/Start-AgentRemoteBridge.ps1`.

Concrete endpoints, credentials, and plant locators remain private.

## Direct read-only capabilities

List or invoke read-only catalog entries with:

```powershell
.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1 -List

.\scripts\capabilities\twincat\Invoke-AdsCapability.ps1 `
    -Capability ReadSystemState
```

The selector rejects every state-changing catalog entry.

## Component preflight

`Invoke-AdsBindingPreflight.ps1` receives a persisted run manifest, one
component runtime-binding document, and a finite list of binding-ID/value
expectations selected for the requested interaction.

Without `-Execute`, it prepares a locator-free read plan. With `-Execute`, it
uses only the `READ_ONLY` binding-preflight capability, preserves raw output,
and writes `preflight.json`. Failed or unavailable checks produce
`hard_blocked`; a complete passing check produces
`ready_for_supervised_probe`.

## Supervised bounded probe

`Invoke-AdsSupervisedProbe.ps1` receives the persisted manifest and preflight,
initial and final binding expectations, and finite main and restore lists of
catalogued capability calls. Each call maps recipe parameters to read or write
runtime-binding IDs. Its default mode prepares the exact operation and returns
an operation-specific approval phrase without loading credentials or
contacting the runtime.

Execution requires all of the following:

- the preflight assessment is `ready_for_supervised_probe`;
- the runtime-binding path and SHA-256 revision match the manifest;
- the exact approval phrase is supplied with current approval provenance;
- execution and restore have explicit time bounds;
- every initial condition is re-read immediately before the first write.

The runner records capability invocations, read-only state checks, timeout,
abort, and verified restore evidence. Plans and normalized facts contain
binding IDs rather than private PLC locators. The runner accepts no arbitrary
script or free symbol; action semantics and technical guards remain in the
selected catalogued capabilities.

After human observation and adapter generation, finalize the execution record
with `scripts/complete-supervised-probe.ps1`. The finalizer consumes executor
facts instead of reconstructing events from narrative.

`validated_interface` is accepted only when `adapter_ref` points to an existing
`generated/connectors/<environment>/components/<component>/verification.json`.
That file must declare `verification_status: verified`, the requested
interface, matching input revisions, evidence references, and an existing
entrypoint inside the adapter directory.

This infrastructure is component-generic but currently uses the TwinCAT ADS
capability implementation. It does not place TwinCAT assumptions in the
vendor-independent commissioning core.
