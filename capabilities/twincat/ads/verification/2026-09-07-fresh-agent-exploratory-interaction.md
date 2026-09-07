# Fresh-agent exploratory TwinCAT ADS interaction — 2026-09-07

## Scope

This note records the reported outcome of isolated fresh-agent tests against an
existing operational TwinCAT project. The test worktree contained the tracked
repository and only the minimal ignored local configuration required for the
remote connection. It did not contain private runtime bindings, earlier chat
transcripts, or private exploration notes.

Concrete endpoints, credentials, asset identifiers, PLC symbols, generated
scripts, and plant-specific procedures remain outside this public record.

## Reported result

**Evidence status:** `reported_success`

The operator reports that fresh-agent sessions using Terra at medium and low
reasoning effort were able to:

- orient themselves in the repository and establish the intended remote ADS
  access path;
- discover functional control and observation interfaces for the selected
  components;
- perform explicitly approved, time-bounded interactions;
- observe logical state changes and return the components to their initial
  logical states; and
- obtain independent operator confirmation of the physical responses.

One run stopped an actuator earlier than requested because an unqualified
project-specific signal was used as a hard postcondition. The physical
observation disproved that interpretation. The agent revised the signal's role,
retained it as unresolved observational evidence rather than a control guard,
and completed a corrected bounded interaction with restoration.

## Codification limitation

The agents did not reliably turn their exploratory findings into correctly
placed reusable artifacts. The final clean test worktree contained no
agent-generated connector, runtime binding, operation record, or validation
artifact. The operator also reported a separate attempt that placed exploratory
material under `creds/`; that location is reserved for local credentials,
endpoints, profiles, and transient state rather than derived engineering
knowledge.

Correct classification and placement of agent-generated exploration artifacts
is therefore a separate unresolved issue. It does not negate the reported live
interaction result.

## Evidence boundary

This result is not marked `validated`: no complete structured runtime log or
exact generated execution script was preserved in the repository. It is based
on the retained session history and independent operator report. It does not
certify plant safety, feedback independence, portability to another project, or
correct behavior outside the explicitly supervised test conditions.
