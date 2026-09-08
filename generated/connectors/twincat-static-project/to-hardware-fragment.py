#!/usr/bin/env python3
"""Translate extracted configured hardware nodes into a canonical fragment."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def safe_id(value: str) -> str:
    return "configured-" + hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--facts", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--system-id", required=True)
    parser.add_argument("--system-name", required=True)
    parser.add_argument("--source-id", default="configured-hardware")
    parser.add_argument("--source-title", default="Configured engineering-project hardware")
    args = parser.parse_args()
    facts = json.loads(args.facts.read_text(encoding="utf-8"))
    id_map = {node["id"]: safe_id(node["id"]) for node in facts.get("hardware_nodes", [])}
    assets = []
    for node in facts.get("hardware_nodes", []):
        designation = node.get("description") or node.get("type") or node.get("name")
        asset = {
            "id": id_map[node["id"]],
            "name": node.get("name", designation),
            "description": node.get("type", designation),
            "asset_kind": "instance",
            "role": "bus_coupler" if not node.get("parent_ref") else "io_module",
            "identification": {
                "manufacturer_product_designation": designation,
                "source_refs": [args.source_id],
            },
            "source_refs": [args.source_id],
            "status": "declared",
            "extensions": {
                "twincat.configured_id": node.get("configured_id"),
                "twincat.product_code": node.get("product_code"),
                "twincat.vendor_id": node.get("vendor_id"),
            },
        }
        if node.get("parent_ref") in id_map:
            asset["parent_asset_id"] = id_map[node["parent_ref"]]
        assets.append(asset)
    output = {
        "schema_version": "0.2.0",
        "system": {"id": args.system_id, "name": args.system_name},
        "sources": [{
            "id": args.source_id,
            "type": "engineering_project",
            "title": args.source_title,
            "content_hash": facts["source_revision"]["value"],
            "locator": "Static project hardware configuration",
        }],
        "assets": assets,
        "physical_connections": [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(assets)} configured hardware assets to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
