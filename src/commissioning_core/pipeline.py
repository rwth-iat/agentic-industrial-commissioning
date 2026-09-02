"""CLI for the reproducible, offline MVP pipeline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .assemble import assemble_canonical_model
from .matching import build_matching_result


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the offline commissioning MVP")
    parser.add_argument(
        "--input",
        dest="inputs",
        action="append",
        type=Path,
        required=True,
        help="Canonical-shaped structured fragment; repeat for multiple inputs",
    )
    parser.add_argument("--model-out", type=Path, required=True)
    parser.add_argument("--report-out", type=Path, required=True)
    args = parser.parse_args()
    model = assemble_canonical_model([_read(path) for path in args.inputs])
    model, report = build_matching_result(model)
    for path, document in ((args.model_out, model), (args.report_out, report)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
