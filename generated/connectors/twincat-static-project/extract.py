#!/usr/bin/env python3
"""Read-only static fact extraction for TwinCAT PLC project files.

The adapter intentionally emits syntactic facts, not plant semantics.  It uses
only the Python standard library and never opens or changes an engineering
environment.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path


SUPPORTED_SUFFIXES = {
    ".plcproj", ".tsproj", ".tcpou", ".tcgvl", ".tcdut", ".tctto"
}
VAR_BLOCK_RE = re.compile(r"\bVAR(?:_(?:INPUT|OUTPUT|IN_OUT|GLOBAL|TEMP|STAT|EXTERNAL))?\b(.*?)\bEND_VAR\b", re.I | re.S)
VAR_HEAD_RE = re.compile(r"^\s*([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_][\w]*)*)\s*(?:AT\s+[^:]+)?\s*:\s*(.+)$", re.I | re.S)
ASSIGN_RE = re.compile(r"(?m)^\s*([A-Za-z_][\w.\[\]^]*)\s*:=\s*(.+?);\s*$")
CALL_RE = re.compile(r"(?<![\w.])([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)\s*\(")
DECL_KIND_RE = re.compile(r"\b(PROGRAM|FUNCTION_BLOCK|FUNCTION|METHOD|PROPERTY|ACTION|TYPE)\s+([A-Za-z_][\w]*)", re.I)
CALL_KEYWORDS = {"if", "elsif", "while", "case", "for", "return", "sizeof"}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_id(prefix: str, *parts: str) -> str:
    raw = "\0".join(parts).encode("utf-8")
    return f"{prefix}:{hashlib.sha256(raw).hexdigest()[:16]}"


def strip_comments(text: str) -> tuple[str, list[dict]]:
    """Remove IEC comments while preserving newlines and report their content."""
    comments: list[dict] = []
    chars = list(text)
    patterns = [(re.compile(r"\(\*.*?\*\)", re.S), "block"), (re.compile(r"//[^\r\n]*"), "line")]
    for pattern, kind in patterns:
        current = "".join(chars)
        for match in pattern.finditer(current):
            value = match.group(0)
            code_candidate = re.sub(r"^(?://|\(\*)|(?:\*\))$", "", value.strip()).strip()
            comments.append({
                "kind": kind,
                "line": current.count("\n", 0, match.start()) + 1,
                "text": value,
                "contains_code_like_text": bool(ASSIGN_RE.search(code_candidate) or CALL_RE.search(code_candidate)),
            })
            for index in range(match.start(), match.end()):
                if chars[index] not in "\r\n":
                    chars[index] = " "
    return "".join(chars), comments


def evidence_location(relative_path: str, section: str, line: int | None = None) -> str:
    suffix = f":{line}" if line is not None else ""
    return f"{relative_path}#{section}{suffix}"


def extract_code_file(path: Path, relative_path: str) -> dict:
    root = ET.parse(path).getroot()
    objects, variables, assignments, calls, inactive = [], [], [], [], []
    for element in root.iter():
        tag = local_name(element.tag)
        if tag not in {"POU", "GVL", "DUT", "Method", "Property", "Action"}:
            continue
        name = element.attrib.get("Name")
        if not name:
            continue
        declaration = next((child.text or "" for child in element if local_name(child.tag) == "Declaration"), "")
        implementation = ""
        for child in element.iter():
            if local_name(child.tag) in {"ST", "IL"} and child.text:
                implementation += child.text + "\n"
        declared = DECL_KIND_RE.search(declaration)
        kind = (declared.group(1).lower() if declared else tag.lower())
        object_id = stable_id("object", relative_path, tag, name)
        objects.append({"id": object_id, "kind": kind, "name": name, "location": evidence_location(relative_path, tag)})

        for block in VAR_BLOCK_RE.finditer(declaration):
            block_line = declaration.count("\n", 0, block.start()) + 1
            block_text, _ = strip_comments(block.group(1))
            for statement_match in re.finditer(r"(?s)(.*?);", block_text):
                statement = statement_match.group(1).strip()
                match = VAR_HEAD_RE.match(statement)
                if not match:
                    continue
                type_and_initializer = match.group(2).strip()
                if ":=" in type_and_initializer:
                    datatype, initializer = (part.strip() for part in type_and_initializer.split(":=", 1))
                else:
                    datatype, initializer = type_and_initializer, None
                statement_line = block_line + block_text.count("\n", 0, statement_match.start()) + 1
                for var_name in [item.strip() for item in match.group(1).split(",")]:
                    variables.append({
                        "id": stable_id("variable", relative_path, name, var_name),
                        "owner_ref": object_id,
                        "name": var_name,
                        "datatype": datatype,
                        "initializer": initializer,
                        "location": evidence_location(relative_path, "declaration", statement_line),
                    })

        active, comments = strip_comments(implementation)
        for comment in comments:
            if comment["contains_code_like_text"]:
                inactive.append({**comment, "owner_ref": object_id, "location": evidence_location(relative_path, "implementation", comment["line"])})
        for match in ASSIGN_RE.finditer(active):
            assignments.append({
                "id": stable_id("assignment", relative_path, name, str(match.start()), match.group(0)),
                "owner_ref": object_id,
                "target": match.group(1),
                "expression": match.group(2).strip(),
                "line": active.count("\n", 0, match.start()) + 1,
                "location": evidence_location(relative_path, "implementation", active.count("\n", 0, match.start()) + 1),
            })
        for match in CALL_RE.finditer(active):
            target = match.group(1)
            if target.lower() in CALL_KEYWORDS:
                continue
            calls.append({
                "id": stable_id("call", relative_path, name, str(match.start()), target),
                "owner_ref": object_id,
                "target": target,
                "line": active.count("\n", 0, match.start()) + 1,
                "location": evidence_location(relative_path, "implementation", active.count("\n", 0, match.start()) + 1),
            })
    return {"objects": objects, "variables": variables, "assignments": assignments, "calls": calls, "inactive_fragments": inactive}


def extract_plc_project(path: Path, relative_path: str) -> dict:
    root = ET.parse(path).getroot()
    compile_items, libraries = [], []
    for element in root.iter():
        tag = local_name(element.tag)
        if tag == "Compile" and element.attrib.get("Include"):
            compile_items.append(element.attrib["Include"].replace("\\", "/"))
        elif tag in {"PlaceholderReference", "LibraryReference"} and element.attrib.get("Include"):
            libraries.append(element.attrib["Include"])
    return {"path": relative_path, "compile_items": sorted(compile_items), "libraries": sorted(libraries)}


def extract_mappings(path: Path, relative_path: str) -> list[dict]:
    root = ET.parse(path).getroot()
    links: list[dict] = []
    owner_a = None
    owner_b = None
    for event, element in ET.iterparse(path, events=("start", "end")):
        tag = local_name(element.tag)
        if event == "start" and tag == "OwnerA":
            owner_a = element.attrib.get("Name")
        elif event == "start" and tag == "OwnerB":
            owner_b = element.attrib.get("Name")
        elif event == "end" and tag == "Link":
            var_a, var_b = element.attrib.get("VarA"), element.attrib.get("VarB")
            if var_a and var_b:
                links.append({
                    "id": stable_id("io-link", relative_path, owner_a or "", owner_b or "", var_a, var_b),
                    "owner_a": owner_a,
                    "owner_b": owner_b,
                    "variable_a": var_a,
                    "variable_b": var_b,
                    "location": evidence_location(relative_path, "Mappings"),
                })
        elif event == "end" and tag == "OwnerB":
            owner_b = None
        elif event == "end" and tag == "OwnerA":
            owner_a = None
        if event == "end":
            element.clear()
    return links


def extract_hardware_nodes(path: Path, relative_path: str) -> list[dict]:
    root = ET.parse(path).getroot()
    nodes: list[dict] = []

    def walk(element: ET.Element, parent_ref: str | None, path_names: list[str]) -> None:
        for child in element:
            if local_name(child.tag) != "Box":
                walk(child, parent_ref, path_names)
                continue
            name = next((grandchild.text for grandchild in child if local_name(grandchild.tag) == "Name"), None)
            ethercat = next((grandchild for grandchild in child if local_name(grandchild.tag) == "EtherCAT"), None)
            identity = name or child.attrib.get("Id", "unknown")
            node_ref = stable_id("hardware-node", relative_path, *(path_names + [identity]))
            node = {
                "id": node_ref,
                "parent_ref": parent_ref,
                "name": name,
                "configured_id": child.attrib.get("Id"),
                "box_type": child.attrib.get("BoxType"),
                "location": evidence_location(relative_path, "Io"),
            }
            if ethercat is not None:
                node["type"] = ethercat.attrib.get("Type")
                node["description"] = ethercat.attrib.get("Desc")
                node["vendor_id"] = ethercat.attrib.get("VendorId")
                node["product_code"] = ethercat.attrib.get("ProductCode")
            nodes.append({key: value for key, value in node.items() if value is not None})
            walk(child, node_ref, path_names + [identity])

    walk(root, None, [])
    return nodes


def canonical_json(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def extract(root: Path) -> dict:
    root = root.resolve()
    files = sorted(path for path in root.rglob("*") if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES)
    manifest, plc_projects, objects, variables, assignments, calls, inactive, io_links, hardware_nodes = [], [], [], [], [], [], [], [], []
    limits: list[str] = []
    for path in files:
        relative_path = path.relative_to(root).as_posix()
        digest = sha256(path)
        manifest.append({"path": relative_path, "size": path.stat().st_size, "sha256": digest})
        try:
            suffix = path.suffix.lower()
            if suffix == ".plcproj":
                plc_projects.append(extract_plc_project(path, relative_path))
            elif suffix == ".tsproj":
                io_links.extend(extract_mappings(path, relative_path))
                hardware_nodes.extend(extract_hardware_nodes(path, relative_path))
            elif suffix in {".tcpou", ".tcgvl", ".tcdut"}:
                facts = extract_code_file(path, relative_path)
                objects.extend(facts["objects"])
                variables.extend(facts["variables"])
                assignments.extend(facts["assignments"])
                calls.extend(facts["calls"])
                inactive.extend(facts["inactive_fragments"])
        except (ET.ParseError, UnicodeError, OSError) as exc:
            limits.append(f"Could not parse {relative_path}: {type(exc).__name__}: {exc}")
    source_revision = hashlib.sha256(canonical_json(manifest)).hexdigest()
    facts = {
        "format_version": "0.1.0",
        "generator": "twincat-static-project/extract.py",
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source_revision": {"algorithm": "sha256", "value": source_revision},
        "extraction_scope": {
            "recursive": True,
            "suffixes": sorted(SUPPORTED_SUFFIXES),
        },
        "files": manifest,
        "plc_projects": plc_projects,
        "objects": objects,
        "variables": variables,
        "assignments": assignments,
        "calls": calls,
        "io_links": io_links,
        "hardware_nodes": hardware_nodes,
        "inactive_fragments": inactive,
        "limitations": sorted(set(limits + [
            "Static syntax extraction does not establish runtime validity or plant semantics.",
            "Library internals, graphical languages, preprocessor effects, and expression semantics are not resolved.",
            "Commented code is reported only as inactive code-like text and is never treated as active behavior.",
        ])),
    }
    facts_revision_basis = {key: value for key, value in facts.items() if key not in {"generated_at", "facts_revision"}}
    facts["facts_revision"] = {"algorithm": "sha256", "value": hashlib.sha256(canonical_json(facts_revision_basis)).hexdigest()}
    return facts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.source_root.is_dir():
        parser.error("source_root must be an existing directory")
    facts = extract(args.source_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(facts, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.output),
        "source_revision": facts["source_revision"]["value"],
        "files": len(facts["files"]),
        "objects": len(facts["objects"]),
        "variables": len(facts["variables"]),
        "assignments": len(facts["assignments"]),
        "calls": len(facts["calls"]),
        "io_links": len(facts["io_links"]),
        "hardware_nodes": len(facts["hardware_nodes"]),
        "inactive_fragments": len(facts["inactive_fragments"]),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
