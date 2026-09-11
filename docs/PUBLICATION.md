# Publication and privacy boundary

## Public release scope

This repository publishes the Agentic Industrial Commissioning method: its
architecture, schemas, generic core, reusable technical capabilities, public
configuration templates, synthetic examples, tests, and sanitized verification
summaries.

It does not publish a real automation environment. A clone must be usable for
offline validation without access to the original test system, credentials, or
private helper files.

## Data classification

Keep these categories distinct:

| Category | Examples | Public repository |
|---|---|---|
| Generic method | schemas, validators, generic recipes, tests | yes |
| Synthetic or reviewed sanitized example | placeholder endpoints, invented assets and locators | yes |
| Secret or local configuration | credentials, keys, connection profiles, hostnames, private addresses | no |
| Plant knowledge | real assets, runtime locators, software mappings, network topology | no by default |
| Operational knowledge | validated plant-specific procedures and limits | no by default |
| Private evidence | raw projects, exports, observations, logs, transcripts, customer documents | no |

A file is not safe merely because it contains no password. Plant structure,
runtime bindings, and operating procedures can still be sensitive.

## Local layout

Use the ignored paths below for operational work:

```text
creds/
cases/<case-id>/raw/
cases/<case-id>/derived/private/
cases/<case-id>/results/private/
cases/<case-id>/validation/private/
docs/private/
```

Create local connection configuration from the committed templates:

```powershell
New-Item -ItemType Directory -Force .\creds | Out-Null
Copy-Item .\scripts\remote\config.example.psd1 .\creds\remote.local.psd1
Copy-Item .\capabilities\twincat\ads\config.example.psd1 .\creds\twincat-ads.local.psd1
```

Do not place passwords in those data files. The remote bridge uses interactive
human authentication by default.

## Before publishing a fork or release

1. Run `git status --ignored` and confirm that private paths are ignored.
2. Run `git ls-files -ci --exclude-standard`; it must return no tracked ignored
   files.
3. Review every branch and tag, not only the checked-out branch.
4. Scan the complete Git object history for secrets, private endpoints, raw
   engineering artifacts, private evidence, and large binary files.
5. Remove sensitive objects from history and force-update every published ref
   that can reach them.
6. Rotate any credential that was ever committed. History rewriting does not
   make an exposed credential trustworthy again.
7. Run the offline, capability, connector, and privacy test suites.

After a history rewrite, existing clones and forks still retain the old
objects. Collaborators must discard or carefully rebase old clones, and the
hosting provider may require a support request to purge cached or referenced
objects completely.

## Safety boundary

Publishing a connector or capability does not authorize its use against a
controller or plant. Read-only preflight, exact approval, bounded execution,
observation, abort, and restoration requirements remain in force for every
live run. See [COMMISSIONING_RUNBOOK.md](COMMISSIONING_RUNBOOK.md).
