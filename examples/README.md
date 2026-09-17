# Synthetic TwinCAT example

The `examples/` tree contains one compact synthetic process-cell case expressed
through the four active knowledge contracts:

- `hardware-models/process-cell.synthetic.v0.2.json`;
- `software-models/process-cell.synthetic.v0.1.json`;
- `implementation-links/process-cell.synthetic.v0.1.json`;
- `runtime-bindings/twincat-ads.synthetic.v0.1.json`.

Together they describe multiple physical and software components,
implementation links, readable and writable bindings, one level-write hint,
one pulse-write hint, and an unrelated diagnostic binding. They provide
context only. They do not prescribe a binding choice, action sequence,
approval decision, or expected agent response.

Hardcoding variants belong under `tests/fixtures/` when Phase 14 defines them;
they are test inputs, not additional public architecture examples.
