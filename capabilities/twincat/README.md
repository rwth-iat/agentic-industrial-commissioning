# TwinCAT capabilities

This directory indexes technical interaction patterns for TwinCAT environments.

## Available interfaces

- [`ads/`](ads/README.md): runtime and TwinCAT system access through ADS.

The read-only ADS catalog can be listed or invoked through the human-facing
selector documented under [`scripts/capabilities/twincat/`](../../scripts/capabilities/twincat/README.md).

Future engineering access through TwinCAT XAE or the Automation Interface
belongs in a separate `xae/` area once it has been explored and verified. ADS
runtime access and XAE engineering access must not be treated as equivalent
capabilities.
