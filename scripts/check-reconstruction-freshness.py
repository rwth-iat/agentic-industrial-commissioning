#!/usr/bin/env python3
"""Check whether an agent-derived reconstruction cites the current fact revision."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def is_current(facts: dict, manifest: dict) -> bool:
    return bool(
        facts.get("facts_revision", {}).get("value")
        and facts.get("facts_revision", {}).get("value")
        == manifest.get("software_facts_revision", {}).get("value")
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--facts", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    facts = json.loads(args.facts.read_text(encoding="utf-8"))
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    actual = facts.get("facts_revision", {}).get("value")
    expected = manifest.get("software_facts_revision", {}).get("value")
    if not actual or not expected:
        print("STALE: missing facts revision or derivation revision", file=sys.stderr)
        return 2
    if not is_current(facts, manifest):
        print(f"STALE: derivation={expected} current={actual}", file=sys.stderr)
        return 1
    print(f"CURRENT: {actual}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
