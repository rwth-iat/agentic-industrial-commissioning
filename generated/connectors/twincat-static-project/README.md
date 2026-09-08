# TwinCAT static project extractor

This read-only source-format adapter inventories syntactic facts from a TwinCAT
PLC project directory. It does not start TwinCAT, connect to a controller, write
project files, infer plant semantics, or create executable authorization.

```powershell
python generated/connectors/twincat-static-project/extract.py `
  <project-directory> `
  --output <private-facts.json>
```

The JSON contains a SHA-256 source manifest, declarations, variables, calls,
assignments, configured I/O links, code-like commented fragments, and explicit
parser limitations. Paths are relative to the supplied root. The adapter has no
component-name table and therefore reacts to additions and renames directly from
the project evidence.

The output is technical evidence. An engineering agent must reconcile it with
hardware evidence and preserve uncertainty before producing the canonical
software model and implementation links.

`to-hardware-fragment.py` can translate the configured hardware-node inventory
into a canonical v0.2 fragment. It deliberately does not invent channel ports,
physical wiring, manufacturers, or device semantics.
