# Canonical Hardware Model

## Purpose

The Canonical Hardware Model is the vendor-independent contract between discovery and downstream commissioning reasoning. Connectors may return different vendor- or environment-specific data, but normalization must translate that data into this common representation before matching or artifact generation.

The model is a lean Commissioning Intermediate Representation (IR). It is not intended to replace an Asset Administration Shell (AAS), AutomationML, ECLASS, OPC UA information models, or a complete digital twin.

## Active schema proposal

The active schema is [`../spec/hardware-model.schema.v0.2-proposal.json`](../spec/hardware-model.schema.v0.2-proposal.json). The earlier [`../spec/hardware-model.schema.json`](../spec/hardware-model.schema.json) remains available as the original baseline while the proposal is evaluated.

Version 0.2 uses three central abstractions:

- `assets` represent physical or logical components without introducing vendor-specific component classes;
- `ports` represent signal, communication, power, and process interfaces owned by assets;
- `physical_connections` represent observed, declared, inferred, candidate, validated, rejected, or unknown relations between two ports.

## Validated baseline profile

The first completed proof point depends only on:

- stable asset and port IDs;
- source-backed identification where available, while permitting explicitly partial asset identities;
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

These fields may be populated only from reliable sources. The validated
baseline does not require them and must never invent external identifiers.

The `identification` object is deliberately a small subset rather than an implementation of the complete IDTA Digital Nameplate. At least one identification `source_ref` is mandatory so that a human can cross-check the identity claim. `manufacturer_name` and `manufacturer_product_code` must be preserved when a cited source provides them, but may be omitted for partially identified brownfield assets. Their absence means unknown, not absent, and must never be filled with invented placeholders. Product designation, serial number, global asset ID, and specific asset IDs remain optional.

The public matching examples use visibly synthetic `EXAMPLE-*` product codes.
Real normalized models must copy actual OEM product or order codes from their
cited BOM, datasheet, nameplate, or engineering source and must never invent a
plausible code.

## Evidence reconciliation

Evidence is interpreted with an open-world assumption: if an asset, property, or connection is not mentioned by one source, that omission is not evidence that it does not exist. Only incompatible positive assertions within a comparable scope constitute a conflict.

Different sources may support different parts of the same conclusion. For example, an inventory may identify a field device, an engineering snapshot may observe an I/O module and its position, a wiring document may declare a channel assignment, and product documentation may establish electrical compatibility. Agreeing evidence should be retained together. A bill of materials is useful evidence but is not a prerequisite for retaining an asset found in another source.

A `declared`, `observed`, or `validated` connection must cite its supporting evidence. A single electrically compatible `declared` or `observed` connection resolves that field port for candidate generation when no competing compatible assertion names a different target. This does not promote the connection to `validated`; physical or functional validation remains a separate state. Competing asserted targets remain explicit and require reconciliation. Electrical candidates are generated only where no usable asserted target exists.

## Logical signals and terminals

Ports with role `signal` represent independently matchable logical interfaces. Conductor, pin, and terminal labels such as `+`, `-`, or terminal numbers are connection details, not automatically separate logical signals. Preserve such details in names, properties, evidence, or namespaced extensions. Model them as separate signal ports only when the evidence establishes independently usable signals; otherwise the matching core would create artificial alternatives.

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
./tests/schema/test-hardware-model.ps1
```

## Examples

- [`../examples/hardware-models/process-cell-ambiguous.synthetic.v0.2.json`](../examples/hardware-models/process-cell-ambiguous.synthetic.v0.2.json): two electrically compatible candidates remain ambiguous;
- [`../examples/hardware-models/process-cell-unambiguous.synthetic.v0.2.json`](../examples/hardware-models/process-cell-unambiguous.synthetic.v0.2.json): exactly one electrically compatible candidate remains;
- [`../examples/hardware-models/process-cell-incompatible.synthetic.v0.2.json`](../examples/hardware-models/process-cell-incompatible.synthetic.v0.2.json): no compatible candidate remains.
