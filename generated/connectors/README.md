# Generated connectors

Environment-specific discovery and extraction code belongs in one isolated
subdirectory per environment:

```text
generated/connectors/<environment-id>/
```

A connector may use vendor-specific APIs or file formats, but its output must
be one or more canonical-shaped fragments accepted by the generic processing
path. A connector must discover what evidence is actually available; it must
not require a predefined `raw/` directory taxonomy. Do not add vendor branches
to `src/commissioning_core/` merely to accommodate a source format.

A connector may compose reusable technical patterns from `capabilities/`, but
it owns all environment-specific adaptation and configuration. Capability
recipes must not be copied into the generic core, and raw connector output must
be preserved as case evidence before canonical normalization.
