"""Electrical compatibility and candidate generation for canonical models."""

from __future__ import annotations

from collections import defaultdict
from copy import deepcopy


def _ports(model: dict):
    for asset in model["assets"]:
        for port in asset.get("ports", []):
            yield asset, port


def _range_contains(provider: dict, consumer: dict) -> bool:
    provided = provider["interface"].get("signal_range")
    accepted = consumer["interface"].get("signal_range")
    if provided is None or accepted is None:
        return True
    if provided["unit"]["symbol"] != accepted["unit"]["symbol"]:
        return False
    return accepted["min"] <= provided["min"] and provided["max"] <= accepted["max"]


def _property_value(port: dict, property_id: str):
    for item in port["interface"].get("properties", []):
        if item["id"] == property_id:
            return item["value"]
    return None


def electrical_compatibility(provider: dict, consumer: dict) -> tuple[bool, str]:
    """Compare generic electrical interface attributes only.

    The asset role, manufacturer, module identifier, and source format never
    influence this decision.
    """
    if provider["direction"] not in {"output", "bidirectional"}:
        return False, "source port does not provide a signal"
    if consumer["direction"] not in {"input", "bidirectional"}:
        return False, "target port does not accept a signal"
    source_kind = provider["interface"]["kind"]
    target_kind = consumer["interface"]["kind"]
    if source_kind == "unknown" or target_kind == "unknown":
        return False, "interface kind is unknown"
    if source_kind != target_kind:
        return False, f"interface kinds differ ({source_kind} vs {target_kind})"
    if not _range_contains(provider, consumer):
        return False, "signal range is outside the target acceptance range"
    required_switching = _property_value(consumer, "requires_switching_capability")
    if required_switching and _property_value(provider, "switching_capability") != required_switching:
        return False, f"target does not declare required switching capability '{required_switching}'"
    return True, "interface kind, direction, and signal range are compatible"


def _connection_check(connection: dict, assets_by_id: dict) -> dict:
    """Check one asserted connection without changing its epistemic status."""
    base = {
        "connection_id": connection["id"],
        "assertion_status": connection["status"],
    }
    if connection.get("kind") != "signal":
        return {**base, "result": "not_applicable", "reason": "only signal connections are electrically checked"}

    resolved = []
    for endpoint in connection.get("endpoints", []):
        asset = assets_by_id.get(endpoint["asset_id"])
        if asset is None:
            return {**base, "result": "unverifiable", "reason": f"unknown asset '{endpoint['asset_id']}'"}
        port = next((item for item in asset.get("ports", []) if item["id"] == endpoint["port_id"]), None)
        if port is None:
            return {
                **base,
                "result": "unverifiable",
                "reason": f"unknown port '{endpoint['port_id']}' on asset '{endpoint['asset_id']}'",
            }
        resolved.append((asset, port, endpoint))

    if len(resolved) != 2:
        return {**base, "result": "unverifiable", "reason": "a connection must have exactly two endpoints"}
    io_endpoints = [item for item in resolved if item[0].get("role") == "io_module"]
    if len(io_endpoints) != 1:
        return {
            **base,
            "result": "unverifiable",
            "reason": "electrical reconciliation requires one field endpoint and one I/O endpoint",
        }

    first_port, second_port = resolved[0][1], resolved[1][1]
    compatible, reason = electrical_compatibility(first_port, second_port)
    if not compatible:
        compatible, reverse_reason = electrical_compatibility(second_port, first_port)
        reason = reverse_reason
    if not compatible:
        return {**base, "result": "conflicting", "reason": reason}

    result = "validated" if connection["status"] == "validated" else "compatible_unvalidated"
    return {**base, "result": result, "reason": reason}


def build_matching_result(model: dict) -> tuple[dict, dict]:
    """Create candidates and reconcile assertions without promoting their status."""
    assets_by_id = {asset["id"]: asset for asset in model["assets"]}
    providers = [(asset, port) for asset, port in _ports(model)
                 if port["direction"] in {"output", "bidirectional"} and port.get("role") == "signal"]
    consumers = [(asset, port) for asset, port in _ports(model)
                 if port["direction"] in {"input", "bidirectional"} and port.get("role") == "signal"]
    matrix, candidates_by_provider = [], defaultdict(list)
    for source_asset, source_port in providers:
        for target_asset, target_port in consumers:
            # A candidate always joins field equipment to an I/O module.  This
            # avoids treating each I/O channel as an independent question and
            # makes the ambiguity question about the physical device wiring.
            source_is_io = source_asset.get("role") == "io_module"
            target_is_io = target_asset.get("role") == "io_module"
            if source_is_io == target_is_io:
                continue
            compatible, reason = electrical_compatibility(source_port, target_port)
            row = {
                "source": {"asset_id": source_asset["id"], "port_id": source_port["id"]},
                "target": {"asset_id": target_asset["id"], "port_id": target_port["id"]},
                "compatible": compatible,
                "reason": reason,
            }
            matrix.append(row)
            if compatible:
                field_endpoint = row["target"] if source_is_io else row["source"]
                candidates_by_provider[(field_endpoint["asset_id"], field_endpoint["port_id"])].append(row)

    asserted_connections = [
        connection for connection in model.get("physical_connections", [])
        if connection["status"] in {"declared", "observed", "validated"}
    ]
    connection_checks = [_connection_check(connection, assets_by_id) for connection in asserted_connections]
    checks_by_id = {check["connection_id"]: check for check in connection_checks}
    validated_connection_ids = {
        check["connection_id"] for check in connection_checks if check["result"] == "validated"
    }

    # A compatible asserted connection is enough to resolve candidate
    # generation, but it retains its original epistemic status.  Multiple
    # independent assertions of the same endpoint pair corroborate one target;
    # assertions naming different targets remain an explicit conflict.
    assertions_by_field_port = defaultdict(list)
    for connection in asserted_connections:
        check = checks_by_id[connection["id"]]
        if check["result"] not in {"validated", "compatible_unvalidated"}:
            continue
        resolved_endpoints = [
            (assets_by_id[endpoint["asset_id"]], endpoint)
            for endpoint in connection["endpoints"]
        ]
        field_endpoints = [item for item in resolved_endpoints if item[0].get("role") != "io_module"]
        io_endpoints = [item for item in resolved_endpoints if item[0].get("role") == "io_module"]
        if len(field_endpoints) != 1 or len(io_endpoints) != 1:
            continue
        field_endpoint = field_endpoints[0][1]
        io_endpoint = io_endpoints[0][1]
        assertions_by_field_port[(field_endpoint["asset_id"], field_endpoint["port_id"])].append({
            "connection_id": connection["id"],
            "io_endpoint": {"asset_id": io_endpoint["asset_id"], "port_id": io_endpoint["port_id"]},
        })

    resolved_field_ports = set()
    supported_connection_ids = set()
    conflicting_field_claims = []
    for field_key, assertions in assertions_by_field_port.items():
        targets = {
            (assertion["io_endpoint"]["asset_id"], assertion["io_endpoint"]["port_id"])
            for assertion in assertions
        }
        if len(targets) == 1:
            resolved_field_ports.add(field_key)
            supported_connection_ids.update(assertion["connection_id"] for assertion in assertions)
            continue
        conflicting_field_claims.append({
            "field_endpoint": {"asset_id": field_key[0], "port_id": field_key[1]},
            "asserted_targets": [
                {"asset_id": asset_id, "port_id": port_id}
                for asset_id, port_id in sorted(targets)
            ],
            "connection_ids": sorted(assertion["connection_id"] for assertion in assertions),
            "reason": "multiple compatible asserted connections name different I/O targets",
        })
    matching_source = {
        "id": "src-electrical-matching",
        "type": "inference",
        "title": "Deterministic electrical compatibility matching",
        "locator": "commissioning_core.matching.electrical_compatibility",
    }
    result_model = deepcopy(model)
    result_model.setdefault("sources", []).append(matching_source)
    connections, questions = [], []
    conflicted_field_ports = {
        (claim["field_endpoint"]["asset_id"], claim["field_endpoint"]["port_id"])
        for claim in conflicting_field_claims
    }
    field_ports = [(asset, port) for asset, port in _ports(model)
                   if asset.get("role") != "io_module" and port.get("role") == "signal"
                   and port["direction"] in {"output", "input", "bidirectional"}]
    for source_asset, source_port in field_ports:
        key = (source_asset["id"], source_port["id"])
        if key in resolved_field_ports:
            continue
        if key in conflicted_field_ports:
            continue
        matches = candidates_by_provider[key]
        if not matches:
            questions.append({
                "id": f"question-no-compatible-target-{source_asset['id']}-{source_port['id']}",
                "priority": "blocking",
                "question": f"Which compatible I/O capability is available for {source_asset['id']}/{source_port['id']}?",
                "reason": "No electrically compatible target was found in the supplied topology.",
                "related_port": {"asset_id": source_asset["id"], "port_id": source_port["id"]},
            })
            continue
        confidence = round(1 / len(matches), 4)
        for index, match in enumerate(matches, start=1):
            target = match["target"]
            io_endpoint = target if target["asset_id"] != source_asset["id"] else match["source"]
            connections.append({
                "id": f"candidate-{source_asset['id']}-{source_port['id']}-{io_endpoint['asset_id']}-{io_endpoint['port_id']}",
                "kind": "signal",
                "endpoints": [{"asset_id": source_asset["id"], "port_id": source_port["id"]}, io_endpoint],
                "status": "candidate",
                "confidence": confidence,
                "evidence": [
                    {"source_ref": "src-electrical-matching", "detail": match["reason"]},
                    {"source_ref": source_port["source_refs"][0], "detail": "Source port metadata."},
                    {"source_ref": next(port for asset, port in _ports(model) if asset["id"] == io_endpoint["asset_id"] and port["id"] == io_endpoint["port_id"])["source_refs"][0], "detail": "I/O port metadata."},
                ],
            })
        if len(matches) > 1:
            questions.append({
                "id": f"question-select-target-{source_asset['id']}-{source_port['id']}",
                "priority": "blocking",
                "question": f"Which physical channel is wired to {source_asset['id']}/{source_port['id']}?",
                "reason": f"{len(matches)} electrically compatible channels remain; electrical data alone cannot select one safely.",
                "candidate_targets": [match["target"] if match["target"]["asset_id"] != source_asset["id"] else match["source"] for match in matches],
            })
    io_claims = defaultdict(list)
    for connection in asserted_connections:
        field_endpoints = [
            endpoint for endpoint in connection.get("endpoints", [])
            if endpoint["asset_id"] in assets_by_id
            and assets_by_id[endpoint["asset_id"]].get("role") != "io_module"
        ]
        for endpoint in connection.get("endpoints", []):
            asset = assets_by_id.get(endpoint["asset_id"])
            if asset and asset.get("role") == "io_module":
                io_claims[(endpoint["asset_id"], endpoint["port_id"])].append({
                    "connection_id": connection["id"],
                    "field_endpoints": {
                        (item["asset_id"], item["port_id"]) for item in field_endpoints
                    },
                })
    duplicate_claims = [
        {
            "io_endpoint": {"asset_id": key[0], "port_id": key[1]},
            "connection_ids": sorted(item["connection_id"] for item in claims),
            "reason": "multiple asserted connections claim the same I/O channel",
        }
        for key, claims in io_claims.items()
        if len({endpoint for claim in claims for endpoint in claim["field_endpoints"]}) > 1
    ]

    for check in connection_checks:
        if check["result"] in {"conflicting", "unverifiable"}:
            questions.append({
                "id": f"question-reconcile-connection-{check['connection_id']}",
                "priority": "blocking",
                "question": f"How should asserted connection {check['connection_id']} be reconciled?",
                "reason": check["reason"],
            })
    for claim in conflicting_field_claims:
        endpoint = claim["field_endpoint"]
        questions.append({
            "id": f"question-conflicting-targets-{endpoint['asset_id']}-{endpoint['port_id']}",
            "priority": "blocking",
            "question": f"Which asserted I/O target is correct for {endpoint['asset_id']}/{endpoint['port_id']}?",
            "reason": claim["reason"],
            "connection_ids": claim["connection_ids"],
            "asserted_targets": claim["asserted_targets"],
        })
    for claim in duplicate_claims:
        endpoint = claim["io_endpoint"]
        questions.append({
            "id": f"question-duplicate-channel-{endpoint['asset_id']}-{endpoint['port_id']}",
            "priority": "blocking",
            "question": f"Which asserted connection actually occupies {endpoint['asset_id']}/{endpoint['port_id']}?",
            "reason": claim["reason"],
            "connection_ids": claim["connection_ids"],
        })

    result_model["physical_connections"] = asserted_connections + connections
    report = {
        "schema_version": "mvp-result-1.0",
        "compatibility_matrix": matrix,
        "candidate_connection_ids": [connection["id"] for connection in connections],
        "supported_connection_ids": sorted(supported_connection_ids),
        "validated_connection_ids": sorted(validated_connection_ids),
        "connection_checks": connection_checks,
        "conflicting_field_claims": conflicting_field_claims,
        "duplicate_channel_claims": duplicate_claims,
        "human_questions": questions,
    }
    extensions = model.get("extensions", {})
    unresolved_references = extensions.get(
        "commissioning_core:unresolved_references",
        extensions.get(
            "commissioning_core:unresolved_wiring_references",
            extensions.get("commissioning_mvp:unresolved_wiring_references", []),
        ),
    )
    for item in unresolved_references:
        report["human_questions"].append({
            "id": f"question-reconcile-reference-{item['reference']}",
            "priority": "blocking",
            "question": f"How should unresolved reference {item['reference']} be reconciled?",
            "reason": item["reason"],
        })
    return result_model, report
