# Canonical Hardware Model

## Purpose

The Canonical Hardware Model is the vendor-independent contract between discovery and downstream commissioning reasoning. Connectors may return different vendor- or environment-specific data, but normalization must translate that data into this common representation before matching or artifact generation.

The model is a lean Commissioning Intermediate Representation (IR). It is not intended to replace an Asset Administration Shell (AAS), AutomationML, ECLASS, OPC UA information models, or a complete digital twin.

## Active MVP proposal

The active schema for MVP development is [`../spec/hardware-model.schema.v0.2-proposal.json`](../spec/hardware-model.schema.v0.2-proposal.json). The earlier [`../spec/hardware-model.schema.json`](../spec/hardware-model.schema.json) remains available as the original baseline while the proposal is evaluated.

Version 0.2 uses three central abstractions:

- `assets` represent physical or logical components without introducing vendor-specific component classes;
- `ports` represent signal, communication, power, and process interfaces owned by assets;
- `physical_connections` represent observed, declared, inferred, candidate, validated, rejected, or unknown relations between two ports.

## MVP profile

The first MVP depends only on:

- stable asset and port IDs;
- port direction;
- a coarse, controlled interface kind;
- electrical signal ranges and units where applicable;
- candidate connections with explicit status, confidence, evidence, and provenance.

The matching algorithm must not depend on optional external semantic references.

## Deferred but structurally supported

The schema already provides optional fields for:

- AAS-, IDTA-, ECLASS-, or IEC-based semantic references;
- classifications and semantic properties;
- IEC 81346 reference designations;
- namespaced vendor extensions;
- structured identification inspired by the Digital Nameplate.

These fields may be populated only from reliable sources. The MVP does not require them and must never invent external identifiers.

The `identification` object is deliberately a small subset rather than an implementation of the complete IDTA Digital Nameplate. Product designation and product code describe product/type information; serial number, global asset ID, and specific asset IDs identify an instance where available.

## Static model and uncertainty

Runtime values are outside the static hardware model. Runtime observations may be referenced as provenance, but live values require a separate representation.

Potentially inferred assets, ports, properties, and connections retain an epistemic `status`. Candidate and inferred objects must also include `confidence` and `evidence`. Unknown information is omitted or explicitly marked as unknown rather than guessed.

## Validation

JSON Schema validates document structure. Cross-object constraints require the semantic validator in [`../scripts/validate-hardware-model.ps1`](../scripts/validate-hardware-model.ps1), including:

- uniqueness of source, asset, port, and connection IDs;
- resolution of source, parent-asset, asset, and port references;
- acyclic asset hierarchies;
- ordered numeric ranges (`min <= max`);
- distinct connection endpoints;
- rejection of type assets as physical connection endpoints;
- rejection of signal connections between two known inputs or two known outputs.

Run all schema and semantic validation tests with:

```powershell
./tests/test-hardware-model.ps1
```

## Examples

- [`../examples/hc10/hc10-mvp-example.v0.2.json`](../examples/hc10/hc10-mvp-example.v0.2.json): two electrically compatible candidates remain ambiguous;
- [`../examples/hc10/hc10-mvp-unambiguous.v0.2.json`](../examples/hc10/hc10-mvp-unambiguous.v0.2.json): exactly one electrically compatible candidate remains;
- [`../examples/hc10/hc10-mvp-incompatible.v0.2.json`](../examples/hc10/hc10-mvp-incompatible.v0.2.json): no compatible candidate remains.
