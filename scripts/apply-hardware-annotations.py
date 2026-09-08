#!/usr/bin/env python3
"""Apply agent-reviewed ports, assets, sources, and connections to a base model."""

from __future__ import annotations

import argparse
import json
from copy import deepcopy
from pathlib import Path


def apply_annotations(base: dict, annotations: dict) -> dict:
    result = deepcopy(base)
    sources = {item["id"] for item in result.get("sources", [])}
    for source in annotations.get("sources", []):
        if source["id"] in sources:
            raise ValueError(f"duplicate source id: {source['id']}")
        result.setdefault("sources", []).append(deepcopy(source))
        sources.add(source["id"])
    assets = {item["id"]: item for item in result.get("assets", [])}
    for update in annotations.get("asset_updates", []):
        asset_id = update["asset_id"]
        if asset_id not in assets:
            raise ValueError(f"unknown asset update target: {asset_id}")
        for key, value in update.items():
            if key == "asset_id":
                continue
            if key in assets[asset_id]:
                raise ValueError(f"annotation would overwrite {asset_id}.{key}")
            assets[asset_id][key] = deepcopy(value)
    for asset in annotations.get("assets", []):
        if asset["id"] in assets:
            raise ValueError(f"duplicate asset id: {asset['id']}")
        result["assets"].append(deepcopy(asset))
        assets[asset["id"]] = result["assets"][-1]
    existing_connections = {item["id"] for item in result.get("physical_connections", [])}
    for connection in annotations.get("physical_connections", []):
        if connection["id"] in existing_connections:
            raise ValueError(f"duplicate connection id: {connection['id']}")
        result.setdefault("physical_connections", []).append(deepcopy(connection))
        existing_connections.add(connection["id"])
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--annotations", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = apply_annotations(
        json.loads(args.base.read_text(encoding="utf-8")),
        json.loads(args.annotations.read_text(encoding="utf-8")),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(result['assets'])} assets and {len(result.get('physical_connections', []))} connections")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
