#!/usr/bin/env python3
"""Query reusable component knowledge and optionally emit runtime candidates."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from commissioning_core.component_knowledge import generate_runtime_candidates, query_component, verify_manifest


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_or_print(document: dict, output: Path | None) -> None:
    text = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    if output is None:
        print(text, end="")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")


def revision(path: Path) -> dict:
    return {
        "path": str(path),
        "algorithm": "sha256",
        "value": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hardware-model", type=Path, required=True)
    parser.add_argument("--software-model", type=Path, required=True)
    parser.add_argument("--implementation-links", type=Path, required=True)
    parser.add_argument("--selector", required=True)
    parser.add_argument("--facts", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--case-root", type=Path)
    parser.add_argument("--runtime-bindings", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--runtime-candidates-out", type=Path)
    parser.add_argument("--environment-id", default="offline-candidate-environment")
    parser.add_argument("--platform", default="unknown-static-platform")
    parser.add_argument("--connection-profile", default="offline-candidate-profile")
    args = parser.parse_args()

    hardware, software, links = read(args.hardware_model), read(args.software_model), read(args.implementation_links)
    facts = read(args.facts) if args.facts else None
    runtime_documents = [read(path) for path in args.runtime_bindings]
    freshness_issues = []
    if any(value is not None for value in (args.manifest, args.case_root)):
        if args.manifest is None or args.case_root is None:
            parser.error("--manifest and --case-root must be supplied together")
        freshness_issues = verify_manifest(args.case_root, read(args.manifest), facts)
    result = query_component(
        hardware, software, links, args.selector,
        facts=facts, runtime_documents=runtime_documents, freshness_issues=freshness_issues,
    )
    result["input_revisions"] = {
        "hardware_model": revision(args.hardware_model),
        "software_model": revision(args.software_model),
        "implementation_links": revision(args.implementation_links),
    }
    if args.facts:
        result["input_revisions"]["facts"] = revision(args.facts)
    if args.manifest:
        result["input_revisions"]["manifest"] = revision(args.manifest)
    write_or_print(result, args.output)
    if args.runtime_candidates_out and result.get("asset"):
        candidates = generate_runtime_candidates(
            software, {result["asset"]["id"]}, environment_id=args.environment_id,
            platform=args.platform, connection_profile=args.connection_profile,
            model_ref=os.path.relpath(args.software_model.resolve(), args.case_root.resolve()).replace("\\", "/") if args.case_root else str(args.software_model),
        )
        write_or_print(candidates, args.runtime_candidates_out)
    return 0 if result["knowledge_state"] in {"available", "partial"} else 3


if __name__ == "__main__":
    raise SystemExit(main())
