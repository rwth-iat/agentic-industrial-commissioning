# Hardware Software Implementation Links

## Purpose

Implementation links are the vendor-neutral contract joining canonical
hardware identities to component-facing static software signals. The active
schema is
[`spec/implementation-link.schema.json`](../spec/implementation-link.schema.json),
version `0.1.0`.

The link document is separate because a hardware asset may be known before its
software implementation is reconstructed, multiple software candidates may
remain compatible, and software evidence must not silently modify the
canonical hardware model.

## References

Each document identifies the hardware model and software model it links. Every
link contains:

- a canonical component asset ID;
- a component-interface ID and semantic signal ID from the software model;
- for an `io_signal`, the canonical asset and port representing the evidenced
  physical endpoint;
- link kind, status, confidence, and source-backed evidence.

The component asset and physical endpoint are separate fields. This permits a
component-facing semantic signal to be traced through an I/O asset when that
path is evidenced without pretending that the I/O port is owned by the field
component.

`candidate_mapping` preserves alternatives. Unresolved hardware or software,
ambiguous mappings, and conflicting evidence belong in `gaps`; validators do
not accept dangling IDs as a representation of uncertainty.

## Semantic validation

Validate links together with both referenced models:

```powershell
./scripts/validate-implementation-links.ps1 `
    -LinkPath <implementation-links.json> `
    -SoftwareModelPath <software-model.json> `
    -HardwareModelPath <hardware-model.json>
```

The validator checks:

- model and system identity;
- canonical asset existence;
- actual port ownership;
- component-interface ownership by the canonical asset;
- signal ownership by the referenced interface;
- basic component/port signal direction consistency;
- duplicate IDs and unresolved evidence references;
- evidence rules for corroborated and validated states;
- private placement and prohibited public references to case `raw/` evidence.

Schema and semantic success establish structural consistency, not the truth of
the underlying mapping. Independent agent acceptance remains necessary.

## Runtime and execution boundary

Implementation links contain no ADS symbols, OPC UA NodeIds, hosts, accounts,
credentials, write handshakes, or executable steps. Runtime locators belong in
runtime bindings; bounded execution belongs in the commissioning run and its
generated adapter. A static link neither grants runtime access nor authorizes a
state change.

Concrete plant link documents are ignored private case artifacts. The public
synthetic example is
[`examples/implementation-links/process-cell.synthetic.v0.1.json`](../examples/implementation-links/process-cell.synthetic.v0.1.json).

## Live feedback and versioning

Preserve the implementation-link revision used as a commissioning input. Create a new
version only when retained evidence strengthens, rejects, or changes the trace
between the canonical component and its software signal or I/O endpoint. Live
symbol existence alone validates a runtime locator, not the physical endpoint.

When a link changes, update its software- and hardware-model references and
hashes together, then run the cross-document validator. See
[COMMISSIONING_RUNBOOK.md](COMMISSIONING_RUNBOOK.md) for
the complete component loop.

