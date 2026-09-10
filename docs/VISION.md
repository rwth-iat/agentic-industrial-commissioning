# Vision

## Working title

**Agentic Industrial Commissioning**

## North-star vision

A user should be able to express an industrial engineering objective at the
level of intent, while a generic engineering agent determines and performs the
technical work required to achieve it.

Examples range from reconstruction and commissioning to operational goals:

```text
"Reconstruct the installed I/O topology."
"Integrate this newly installed flow sensor."
"Create the PLC project for this plant."
"Keep the volumetric flow at the requested setpoint."
```

The agent should be able to inspect an unfamiliar environment, understand the
available engineering evidence, discover usable interfaces, create missing
integration and PLC artifacts, execute approved engineering actions, observe
the real result, and revise its approach until the objective is satisfied or a
safe human decision is required.

The current repository focus is narrower than this long-term vision: automatic
commissioning of brownfield systems whose PLC application and four offline
knowledge-contract types already exist. The concrete architecture for that
focus is defined in
[COMMISSIONING_ARCHITECTURE.md](COMMISSIONING_ARCHITECTURE.md).

## Problem

Industrial commissioning, reconstruction, modification, and operation require
substantial manual engineering across disconnected information sources and
tools. An engineer repeatedly has to determine:

- which automation components are installed;
- which I/O modules and channels are available;
- which sensors and actuators are connected;
- which electrical interfaces are compatible;
- how signals are scaled and represented;
- which PLC variables correspond to which physical devices;
- which controller code, mappings, and configurations already exist;
- which programmatic interfaces an engineering environment exposes;
- and which information is missing, contradictory, or unsafe to assume.

Existing integrations usually encode one vendor API or one predefined workflow.
They do not give an agent the freedom to discover a new environment and develop
the required access path itself.

## Core hypothesis

A coding and engineering agent can take over a large part of this work if it is
given:

- controlled access to engineering and automation environments;
- arbitrary available evidence such as project files, exports, documentation,
  observations, and runtime information;
- a vendor-independent canonical representation;
- the ability to inspect tools, APIs, SDKs, protocols, and installed software;
- and explicit safety, validation, and human-approval boundaries.

The project does not assume that every required connector, capability, PLC
program, or semantic mapping exists in advance. Discovering and creating these
artifacts is part of the agent's task.

## Explore, codify, reuse

Exploration is a first-class part of the method.

When the agent encounters an unfamiliar environment, it may, within the
applicable safety boundary:

1. inspect the environment and available evidence;
2. identify possible programmatic access paths;
3. perform passive or narrowly bounded probes;
4. generate and test candidate connectors, scripts, or engineering procedures;
5. compare observations with the canonical model and the requested objective;
6. revise unsuccessful approaches without turning guesses into facts;
7. ask for human approval or missing information where required.

Once a reliable path has been found, the agent should convert it into a small,
testable, reproducible artifact:

```text
Explore -> Validate -> Codify -> Reuse
```

That artifact may be a capability recipe, environment-specific connector,
component adapter, normalization rule, PLC function block, project-generation
script, or validation test. Future runs should prefer the validated
deterministic path while retaining the ability to explore again when the
environment changes or the known path fails.

For the active brownfield commissioning focus, the durable result is normally
a small deterministic component adapter. A separate persistent plan contract
is not required for every exploratory interaction.

## Target lifecycle

```text
High-level user objective
           |
           v
Available evidence and controlled environment access
           |
           v
Generic engineering agent
   | inspect environment and project
   | discover interfaces and capabilities
   | build or adapt connectors
   | reconstruct hardware, I/O, signals, and semantics
           |
           v
Canonical Hardware Model and explicit evidence
           |
           v
Plan engineering and commissioning actions
   | match devices, channels, and PLC symbols
   | generate configuration, mappings, and PLC code
   | build, simulate, test, and review
           |
           v
Safety and human-approval gates
           |
           v
Controlled execution in the engineering environment
           |
           v
Observe physical and logical results
           |
           +----> update evidence, model, plan, and reusable capabilities
```

The lifecycle is iterative. Discovery can reveal missing model information;
execution can invalidate an earlier inference; observation can trigger a new
engineering change. Provenance, confidence, status, and verification state must
survive every iteration.

## Canonical model as the shared world model

The project does not standardize every vendor's internal API. It standardizes
the result of discovery and the contract used by downstream reasoning and
engineering actions.

Different environments may expose themselves through different mechanisms:

```text
Environment A -> engineering API
Environment B -> OPC UA
Environment C -> CLI or SDK
Environment D -> project files
Environment E -> agent-generated remote bridge
```

All relevant findings should be translated into the canonical representation
before they enter generic matching, planning, or generation logic. Vendor-
specific implementation remains isolated in capabilities and connectors.

The active schema and its validated baseline profile are documented in
[HARDWARE_MODEL.md](HARDWARE_MODEL.md).

The hardware model is normally case- or system-scoped. Software models,
implementation links, and runtime bindings are component-scoped contract
instances and may therefore occur repeatedly below component-specific case
directories. Together they form the versioned offline baseline consumed by a
component commissioning run.

## Full engineering scope

The long-term agent is not limited to analyzing an existing complete PLC
project. Depending on the starting point, it should be able to:

- reconstruct a brownfield system from incomplete and conflicting evidence;
- discover live hardware, runtime state, PLC symbols, and mappings;
- add or modify variables, data types, function blocks, programs, tasks, and
  logical links in an existing engineering project;
- generate I/O mappings and controller logic from the canonical model;
- create an automation project when no PLC application exists yet;
- build, test, simulate, deploy, activate, and validate approved changes;
- diagnose failures and adapt the generated solution;
- and translate high-level process objectives into deterministic automation
  behavior and supervised operational actions.

Where reliable deterministic code can perform a recurring task, the agent
should generate and reuse that code rather than repeatedly improvise. Real-time
control should normally remain in the controller or another suitable
deterministic runtime; the agent operates as the exploratory engineering,
commissioning, and supervisory intelligence around it.

## Minimal human interaction, explicit human authority

The objective is not zero human involvement at any cost. It is to minimize
manual engineering while preserving human authority over safety-relevant and
consequential actions.

The agent should infer everything that can be supported reliably and ask only
for information or approval that cannot be obtained safely or uniquely. A
high-level objective authorizes analysis and planning, but it does not silently
authorize every hazardous action that might help achieve the objective.

## Safety model

Autonomy expands only through explicit safety stages:

### Level 1 — passive discovery

- inspect files, projects, configuration, topology, and documentation;
- read controller and runtime states;
- read diagnostics, symbols, and process values.

### Level 2 — controlled diagnostic interaction

- perform bounded tests in simulation or a verified safe plant state;
- observe responses to human actions;
- execute reversible diagnostic procedures with explicit limits.

### Level 3 — engineering changes

- create or modify project structure, PLC code, mappings, and configuration;
- build, simulate, and validate generated artifacts;
- deploy or activate only after the required review and approval.

### Level 4 — operational interaction and actuation

- change setpoints, modes, controller state, or physical outputs;
- perform only explicitly authorized operations within verified plant safety
  conditions and independent interlocks;
- observe the resulting state and stop or escalate when expectations are not
  met.

Technical writability is never evidence of physical safety. Safety systems and
interlocks must remain independent of agent reasoning.

## Success criterion

The vision is achieved when a user can provide a high-level industrial
objective and the agent can safely and traceably perform the required discovery,
engineering, implementation, and validation across unfamiliar environments,
while asking the human only for genuinely necessary decisions and approvals.

## Relation to standards

The method remains independent of any single external standard or automation
vendor. The canonical model should support adapters to ecosystems such as:

- Model Hardware Standard (MHS);
- Asset Administration Shell (AAS);
- OPC UA information models;
- AutomationML, ECLASS, and related interoperability approaches.

The intended contribution is not another fixed device API. It is an agentic
method for transforming heterogeneous industrial environments into a common,
machine-actionable model and using that model to carry out engineering and
commissioning objectives.

## Planning documents

Completed and active proof points are recorded cumulatively in
[MVP.md](MVP.md). The staged path toward this vision is maintained in
[ROADMAP.md](ROADMAP.md).
