"""Deterministic component knowledge retrieval and runtime-candidate support."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Iterable


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_json(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _normalize(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.casefold())


def _asset_aliases(asset: dict, selector: str) -> list[str]:
    aliases = {selector, asset.get("id", ""), asset.get("name", "")}
    aliases.update(item.get("value", "") for item in asset.get("reference_designations", []))
    return sorted(alias for alias in aliases if alias)


def resolve_asset(assets: list[dict], selector: str) -> tuple[dict | None, list[dict]]:
    wanted = _normalize(selector)
    exact, suffix = [], []
    for asset in assets:
        candidates = [asset.get("id", ""), asset.get("name", "")]
        candidates.extend(item.get("value", "") for item in asset.get("reference_designations", []))
        normalized = {_normalize(value) for value in candidates if value}
        if wanted in normalized:
            exact.append(asset)
        elif wanted and any(value.endswith(wanted) for value in normalized):
            suffix.append(asset)
    matches = exact or suffix
    return (matches[0], matches) if len(matches) == 1 else (None, matches)


def _ids(items: Iterable[dict]) -> set[str]:
    return {item.get("id", "") for item in items}


def _fact_matches(fact: dict, aliases: list[str]) -> bool:
    haystack = json.dumps(fact, ensure_ascii=False)
    identifiers = re.findall(r"[A-Za-z][A-Za-z0-9_]*", haystack)
    for alias in aliases:
        if len(alias) < 2:
            continue
        if re.search(rf"(?<![A-Za-z0-9]){re.escape(alias)}(?![A-Za-z0-9])", haystack, re.I):
            return True
        normalized_alias = _normalize(alias)
        if len(normalized_alias) >= 3 and any(_normalize(identifier).endswith(normalized_alias) for identifier in identifiers):
            return True
    return False


def _matching_facts(facts: dict | None, aliases: list[str]) -> dict:
    matches: dict[str, list[dict]] = {}
    if facts:
        for section in ("objects", "variables", "assignments", "calls", "io_links", "inactive_fragments"):
            section_matches = [item for item in facts.get(section, []) if _fact_matches(item, aliases)]
            if section_matches:
                matches[section] = section_matches
    return matches


def _runtime_assessment(asset_id: str, signals: list[dict], bindings: list[dict]) -> tuple[list[dict], list[dict]]:
    signal_by_id = {signal["id"]: signal for signal in signals}
    checks = []
    disagreements = []
    for binding in bindings:
        signal_id = binding.get("extensions", {}).get("software.signal_id")
        signal = signal_by_id.get(signal_id)
        if signal is None:
            candidates = [item for item in signals if item.get("role") == binding.get("role")]
            signal = candidates[0] if len(candidates) == 1 else None
        if signal is None:
            continue
        expected = {
            "asset_id": asset_id,
            "role": signal.get("role"),
            "datatype": signal.get("datatype"),
            "interaction_semantics": ROLE_INTERACTION.get(signal.get("role"), "state"),
            "unit": signal.get("engineering_range", {}).get("unit"),
            "feedback_kind": signal.get("feedback_kind"),
        }
        observed = {
            "asset_id": binding.get("asset_id"),
            "role": binding.get("role"),
            "datatype": binding.get("datatype"),
            "interaction_semantics": binding.get("interaction", {}).get("semantics"),
            "unit": binding.get("unit", {}).get("symbol"),
            "feedback_kind": binding.get("feedback_kind"),
            "access": binding.get("access"),
        }
        check = {
            "binding_id": binding.get("id"),
            "signal_id": signal.get("id"),
            "expected": expected,
            "observed": observed,
            "access_assessment": "not_established_by_static_model",
        }
        check["consistent"] = True
        for field in ("asset_id", "role", "datatype", "interaction_semantics", "unit", "feedback_kind"):
            static_value = expected.get(field)
            runtime_value = observed.get(field)
            if static_value is not None and runtime_value is not None and static_value != runtime_value:
                check["consistent"] = False
                disagreements.append({
                    "binding_id": binding.get("id"),
                    "signal_id": signal.get("id"),
                    "field": field,
                    "static_value": static_value,
                    "runtime_value": runtime_value,
                })
        checks.append(check)
    return checks, disagreements


def query_component(
    hardware: dict,
    software: dict,
    implementation_links: dict,
    selector: str,
    *,
    facts: dict | None = None,
    runtime_documents: list[dict] | None = None,
    freshness_issues: list[dict] | None = None,
) -> dict:
    freshness_issues = list(freshness_issues or [])
    runtime_documents = runtime_documents or []
    asset, matches = resolve_asset(hardware.get("assets", []), selector)
    if asset is None:
        state = "ambiguous" if matches else "missing"
        matching_facts = _matching_facts(facts, [selector])
        return {
            "query_version": "0.1.0",
            "selector": selector,
            "knowledge_state": "stale" if freshness_issues else state,
            "reuse_decision": "targeted_reconstruction",
            "freshness": {"current": not freshness_issues, "issues": freshness_issues},
            "candidate_assets": [{"id": item.get("id"), "name": item.get("name")} for item in matches],
            "reconstruction_scope": {"selector": selector, "reason": state, "matching_facts": matching_facts},
            "safety": {"read_only": True, "executable_authorization": False},
        }

    asset_id = asset["id"]
    interfaces = [item for item in software.get("component_interfaces", []) if item.get("asset_id") == asset_id]
    interface_ids = _ids(interfaces)
    signals = [signal for interface in interfaces for signal in interface.get("signals", [])]
    signal_ids = _ids(signals)
    object_ids = {signal.get("software_object_ref") for signal in signals}
    objects = [item for item in software.get("software_objects", []) if item.get("id") in object_ids]
    links = [
        item for item in implementation_links.get("links", [])
        if item.get("hardware", {}).get("component_asset_id") == asset_id
        or item.get("software", {}).get("component_interface_id") in interface_ids
        or item.get("software", {}).get("signal_id") in signal_ids
    ]
    endpoint_refs = {
        (item.get("hardware", {}).get("endpoint", {}).get("asset_id"), item.get("hardware", {}).get("endpoint", {}).get("port_id"))
        for item in links if item.get("hardware", {}).get("endpoint")
    }
    related_hardware = [item for item in hardware.get("assets", []) if item.get("id") in {ref[0] for ref in endpoint_refs}]
    physical_connections = [
        connection for connection in hardware.get("physical_connections", [])
        if any(endpoint.get("asset_id") == asset_id for endpoint in connection.get("endpoints", []))
        or any((endpoint.get("asset_id"), endpoint.get("port_id")) in endpoint_refs for endpoint in connection.get("endpoints", []))
    ]
    gaps = [
        item for item in software.get("gaps", [])
        if item.get("scope_ref") in interface_ids or item.get("scope_ref") in signal_ids or item.get("scope_ref") in object_ids
    ]
    gaps.extend(
        item for item in implementation_links.get("gaps", [])
        if item.get("asset_id") == asset_id or item.get("signal_id") in signal_ids
    )
    bindings = [
        binding for document in runtime_documents for binding in document.get("bindings", [])
        if binding.get("asset_id") == asset_id
        or binding.get("extensions", {}).get("software.signal_id") in signal_ids
        or binding.get("extensions", {}).get("software.component_interface_id") in interface_ids
    ]
    runtime_checks, disagreements = _runtime_assessment(asset_id, signals, bindings)
    aliases = _asset_aliases(asset, selector)
    matching_facts = _matching_facts(facts, aliases)

    coverage = {item.get("coverage_status") for item in interfaces}
    conflicting = disagreements or any(item.get("category") == "conflicting_evidence" for item in gaps)
    rejected = links and all(item.get("status") == "rejected" for item in links)
    if freshness_issues:
        state = "stale"
    elif conflicting:
        state = "conflicting"
    elif rejected:
        state = "rejected"
    elif not interfaces:
        state = "missing"
    elif "ambiguous" in coverage:
        state = "ambiguous"
    elif coverage == {"unresolved"}:
        state = "missing"
    elif coverage & {"partial", "unresolved"}:
        state = "partial"
    else:
        state = "available"
    decision = "reuse" if state in {"available", "partial"} else "targeted_reconstruction"
    return {
        "query_version": "0.1.0",
        "selector": selector,
        "asset": asset,
        "knowledge_state": state,
        "reuse_decision": decision,
        "freshness": {"current": not freshness_issues, "issues": freshness_issues},
        "component_interfaces": interfaces,
        "software_objects": objects,
        "implementation_links": links,
        "related_hardware_assets": related_hardware,
        "physical_connections": physical_connections,
        "runtime_bindings": bindings,
        "runtime_checks": runtime_checks,
        "runtime_disagreements": disagreements,
        "gaps": gaps,
        "reconstruction_scope": {
            "asset_id": asset_id,
            "aliases": aliases,
            "reason": state if decision == "targeted_reconstruction" else "not_required",
            "matching_facts": matching_facts,
        },
        "safety": {
            "read_only": True,
            "executable_authorization": False,
            "runtime_validation_established": any(binding.get("status") == "validated" for binding in bindings),
        },
    }


def verify_manifest(case_root: Path, manifest: dict, facts: dict | None = None) -> list[dict]:
    """Verify retained source/artifact revisions without changing any file."""
    issues: list[dict] = []
    case_root = case_root.resolve()
    if facts is not None:
        expected = manifest.get("software_facts_revision", {}).get("value")
        actual = facts.get("facts_revision", {}).get("value")
        if expected != actual:
            issues.append({"kind": "facts_revision_mismatch", "expected": expected, "actual": actual})
    for entry in manifest.get("source_revisions", []) + manifest.get("derived_artifacts", []):
        locator = entry.get("locator")
        algorithm = entry.get("algorithm")
        expected = entry.get("value")
        if not locator:
            continue
        path = (case_root / locator).resolve()
        if path != case_root and case_root not in path.parents:
            issues.append({"kind": "unsafe_locator", "locator": locator})
            continue
        if not path.exists():
            issues.append({"kind": "missing_evidence", "locator": locator})
            continue
        if algorithm == "sha256" and path.is_file():
            actual = _sha256(path)
        elif algorithm == "sha256-manifest" and path.is_dir() and facts is not None:
            suffixes = set(facts.get("extraction_scope", {}).get("suffixes", []))
            files = sorted(item for item in path.rglob("*") if item.is_file() and item.suffix.lower() in suffixes)
            file_manifest = [{"path": item.relative_to(path).as_posix(), "size": item.stat().st_size, "sha256": _sha256(item)} for item in files]
            actual = hashlib.sha256(_canonical_json(file_manifest)).hexdigest()
        else:
            issues.append({"kind": "unsupported_revision_check", "locator": locator, "algorithm": algorithm})
            continue
        if actual.casefold() != str(expected).casefold():
            issues.append({"kind": "revision_mismatch", "locator": locator, "expected": expected, "actual": actual})
    return issues


ROLE_INTERACTION = {
    "process_value": "measurement",
    "dynamic_process_value": "measurement",
    "operation_mode_request": "request",
    "operation_mode_active": "state",
    "source_mode_request": "request",
    "source_mode_active": "state",
    "command_request": "request",
    "command_state": "state",
    "manual_setpoint": "setpoint",
    "effective_setpoint": "setpoint",
    "feedback": "feedback",
    "permit": "state",
    "interlock": "state",
    "protection": "state",
    "fault": "state",
    "safe_state": "state",
    "conversion_factor": "constant",
    "other": "state",
}


def generate_runtime_candidates(
    software: dict,
    asset_ids: set[str],
    *,
    environment_id: str,
    platform: str,
    connection_profile: str,
    model_ref: str,
) -> dict:
    objects = {item["id"]: item for item in software.get("software_objects", [])}
    bindings = []
    for interface in software.get("component_interfaces", []):
        if interface.get("asset_id") not in asset_ids:
            continue
        for signal in interface.get("signals", []):
            obj = objects.get(signal.get("software_object_ref"), {})
            qualified_name = obj.get("qualified_name")
            if not qualified_name:
                continue
            role = signal.get("role", "other")
            # Static source code can suggest a symbol and role, but it cannot
            # establish deployed access rights.  Offline candidates therefore
            # remain read-only until runtime observation proves otherwise.
            access = "read"
            candidate = {
                "id": f"candidate-{interface['asset_id']}-{signal['id']}",
                "asset_id": interface["asset_id"],
                "role": role,
                "access": access,
                "locator": {"kind": "ads_symbol", "value": qualified_name},
                "datatype": signal.get("datatype") or obj.get("datatype") or "unknown",
                "interaction": {"semantics": ROLE_INTERACTION.get(role, "state")},
                "status": "inferred",
                "confidence": min(float(signal.get("confidence", 0.5)), 0.85),
                "source_refs": ["static-software-model"],
                "limitations": [
                    "Locator existence, deployed datatype, access, and runtime behavior have not been observed.",
                    "This candidate is not executable authorization and does not establish plant safety.",
                ],
                "extensions": {
                    "software.signal_id": signal["id"],
                    "software.component_interface_id": interface["id"],
                },
            }
            if signal.get("feedback_kind"):
                candidate["feedback_kind"] = signal["feedback_kind"]
            engineering_range = signal.get("engineering_range", {})
            if engineering_range.get("unit"):
                candidate["unit"] = {"symbol": engineering_range["unit"]}
            bindings.append(candidate)
    if not bindings:
        raise ValueError("no software signals with qualified runtime candidates were found")
    return {
        "schema_version": "0.1.0",
        "environment": {
            "id": environment_id,
            "platform": platform,
            "connection_profile": connection_profile,
        },
        "canonical_model": {"system_id": software["system_id"], "model_ref": model_ref},
        "data_classification": "private",
        "sources": [{
            "id": "static-software-model",
            "type": "engineering_project",
            "locator": model_ref,
            "description": "Static software model used to infer unvalidated runtime locator candidates.",
        }],
        "bindings": bindings,
        "extensions": {"safety.executable_authorization": False},
    }
