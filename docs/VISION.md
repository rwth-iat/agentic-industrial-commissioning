# Vision

## Working title

**Agentic Industrial Commissioning**

## Problem

Initial commissioning and reconstruction of industrial automation systems still require substantial manual engineering.

An engineer often has to determine and reconcile:

- which automation components are installed,
- which I/O modules and channels are available,
- which sensors and actuators are connected,
- which electrical interfaces are compatible,
- how signals are scaled,
- which PLC variables correspond to which physical devices,
- which information already exists in datasheets, engineering projects, documentation, or digital representations,
- and which information is missing or contradictory.

This effort reappears during new commissioning, brownfield reconstruction, and later system extensions.

## Hypothesis

A generic coding/engineering agent can reduce this effort substantially if it is given:

- controlled access to the engineering environment,
- device documentation and/or a bill of materials,
- access to available system interfaces,
- and a vendor-independent target schema.

Instead of requiring manually written integrations for every vendor, the agent should discover a usable access path and generate or adapt the required integration layer itself.

## Target architecture

```text
       Engineering environment
                +
       BOM / device documentation
                +
       Existing project artifacts
                +
       Physical or simulated system
                │
                ▼
        Generic engineering agent
                │
                ├─ inspect environment
                ├─ discover interfaces
                ├─ read documentation
                ├─ generate connector
                └─ validate connector
                │
                ▼
       Raw discovered information
                │
                ▼
             Normalize
                │
                ▼
     Canonical Hardware Model
                │
          ┌─────┴─────┐
          ▼           ▼
       Matching    Validation
          │           │
          └─────┬─────┘
                ▼
       Commissioning Model
                │
                ▼
   Engineering artifacts / queries
```

## What is standardized

The project does **not** standardize the internal API of every automation vendor.

It standardizes the **result of discovery** and the contract that downstream reasoning can rely on.

A concrete environment may expose itself through completely different mechanisms:

```text
Environment A → engineering API
Environment B → OPC UA
Environment C → CLI / SDK
Environment D → project files
Environment E → generated bridge
```

All of them should ultimately produce the same canonical representation.

## Agent-generated connectors

A central research idea is that vendor-specific connectors do not necessarily have to be manually implemented in advance.

The agent may:

1. identify the installed engineering platform,
2. inspect locally available APIs, SDKs, tools, and documentation,
3. determine a suitable programmatic access path,
4. generate a small connector,
5. execute it in a controlled environment,
6. test the returned information,
7. normalize the result.

The generated connector is therefore a temporary or reusable bridge between a specific engineering environment and the generic model.

## Commissioning as a matching problem

A useful first abstraction is to model commissioning as constrained matching.

Example:

```text
Known devices                         Discovered I/O

Flow sensor                          AI channel 1
output: 4–20 mA                      input: 4–20 mA

Pressure sensor        ?             AI channel 2
output: 4–20 mA                      input: 4–20 mA

Valve                                  AO channel 1
command: 0–10 V                        output: 0–10 V
```

Electrical compatibility can eliminate impossible assignments immediately.

Additional evidence may come from:

- channel configuration,
- runtime values,
- device ranges,
- existing PLC mappings,
- naming,
- documentation,
- topology,
- observed process behavior,
- controlled tests,
- human confirmation.

The system should progressively reduce uncertainty rather than pretending that identical electrical interfaces are uniquely identifiable.

## Human interaction

The objective is not zero human involvement at any cost.

The objective is **minimal-interaction commissioning**:

> Infer everything that can be inferred reliably; ask the engineer only for the information that cannot be determined safely or uniquely.

Example:

```text
Agent:
Two 4–20 mA sensors remain compatible with AI1 and AI2.
No available evidence distinguishes them.

Question:
Which channel is connected to the flow sensor?
```

One answer can resolve the remaining ambiguity without requiring the engineer to construct the complete mapping manually.

## Safety

Exploration must be staged.

### Level 1 — passive discovery

- inspect engineering environment,
- read configuration,
- read hardware topology,
- parse documentation,
- read runtime values.

### Level 2 — controlled diagnostic interaction

Possible only behind explicit safeguards and approval.

Examples:

- observe signal changes during a human action,
- use test/simulation environments,
- perform narrowly bounded diagnostic operations.

### Level 3 — configuration and actuation

Requires explicit validation, safety policy, and human approval.

The agent must never infer that a technically writable output is safe to actuate.

## Project planning

The authoritative definition of the current project scope is maintained in [MVP.md](MVP.md). Potential future development stages are maintained separately in [ROADMAP.md](ROADMAP.md).

## Relation to MHS and industrial standards

The project should remain independent of any single external standard or automation vendor.

However, the canonical model should be designed so that adapters/exporters can later map it to relevant ecosystems such as:

- Model Hardware Standard (MHS),
- Asset Administration Shell (AAS),
- OPC UA information models,
- other industrial interoperability approaches.

The research contribution is not merely another device API.

The intended contribution is an **agentic method for transforming heterogeneous, partially documented industrial automation environments into a common, machine-actionable representation suitable for commissioning and engineering workflows**.
