"""Assemble canonical-shaped fragments into one canonical hardware model."""

from __future__ import annotations

from copy import deepcopy


def _merge_system(target: dict, incoming: dict) -> None:
    if target and target.get("id") != incoming.get("id"):
        raise ValueError("input fragments describe different systems")
    for key, value in incoming.items():
        if key in target and target[key] != value:
            raise ValueError(f"input fragments disagree on system field '{key}'")
        target[key] = deepcopy(value)


def _merge_extensions(target: dict, incoming: dict) -> None:
    for key, value in incoming.items():
        if key not in target:
            target[key] = deepcopy(value)
        elif target[key] == value:
            continue
        elif isinstance(target[key], list) and isinstance(value, list):
            target[key].extend(deepcopy(value))
        else:
            raise ValueError(f"input fragments disagree on extension '{key}'")


def assemble_canonical_model(documents: list[dict]) -> dict:
    """Combine any number of structured fragments without knowing their origin.

    Raw evidence is intentionally outside this function. Agents or generated
    connectors may derive fragments from arbitrary files, APIs, exports, or
    observations. A fragment may contribute system fields, provenance sources,
    assets, physical connections, or extensions in any combination.
    """
    if not documents:
        raise ValueError("at least one structured input fragment is required")

    model = {
        "schema_version": "0.2.0",
        "system": {},
        "sources": [],
        "assets": [],
        "physical_connections": [],
    }
    sources_by_id: dict[str, dict] = {}

    for document in documents:
        schema_version = document.get("schema_version", "0.2.0")
        if schema_version != model["schema_version"]:
            raise ValueError(f"unsupported input fragment schema version '{schema_version}'")
        if "system" not in document:
            raise ValueError("each input fragment must identify its system")
        _merge_system(model["system"], document["system"])

        for source in document.get("sources", []):
            existing = sources_by_id.get(source["id"])
            if existing is not None and existing != source:
                raise ValueError(f"input fragments disagree on source '{source['id']}'")
            if existing is None:
                copied_source = deepcopy(source)
                model["sources"].append(copied_source)
                sources_by_id[source["id"]] = copied_source

        model["assets"].extend(deepcopy(document.get("assets", [])))
        model["physical_connections"].extend(
            deepcopy(document.get("physical_connections", []))
        )
        if document.get("extensions"):
            model.setdefault("extensions", {})
            _merge_extensions(model["extensions"], document["extensions"])

    return model
