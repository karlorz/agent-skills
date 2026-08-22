#!/usr/bin/env python3
"""build-fallback-report.py — deterministic report fallback builder.

Builds a structurally valid Partial report from structured evidence:
retained claims, complete source ledger, navigation labels, and identity
metadata (title, cutoff, verification date, scope, and evidence-gap reason).

Interface:
    python3 build-fallback-report.py INPUT.json --output FALLBACK.md [--artifact-root DIR]

Output: exactly one JSON object on stdout ({"ok": bool, "output": str, "claims": int, "ledger_rows": int});
nothing on stderr. Exit 0 = valid, 1 = validation/build errors.
Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
REF_RE = re.compile(r"^S([0-9]+)$")
SHA256_RE = re.compile(r"sha256=([0-9a-fA-F]{64})(?![0-9a-fA-F])")
SOURCE_TYPES = ("primary", "secondary", "repository", "other")

LEDGER_HEADER = (
    "| Ref | Role / retained use | Publisher / title | Source type | Accessed | "
    "Exact URL or local record |"
)
LEDGER_DIVIDER = "| --- | --- | --- | --- | --- | --- |"


def validate_date(value: str, field_name: str) -> None:
    if not isinstance(value, str) or not DATE_RE.match(value):
        raise ValueError(f"{field_name} must be YYYY-MM-DD string, got {value!r}")
    try:
        datetime.strptime(value, "%Y-%m-%d")
    except ValueError as exc:
        raise ValueError(f"{field_name} is not a valid calendar date: {value!r}") from exc


def escape_markdown_cell(text: str) -> str:
    # Escape pipe characters that are not already escaped
    # Replace unescaped '|' with '\|'
    return re.sub(r"(?<!\\)\|", r"\|", text).strip()


def local_record_inside_artifact_root(record: str, artifact_root: str | None) -> bool:
    if not artifact_root:
        return False
    try:
        root_path = Path(artifact_root).resolve()
        if not root_path.is_dir():
            return False
        rec_path = Path(record.strip())
        if not rec_path.is_absolute():
            rec_path = (root_path / rec_path).resolve()
        else:
            rec_path = rec_path.resolve()
        if not rec_path.is_file():
            return False
        return rec_path.is_relative_to(root_path)
    except (OSError, ValueError, RuntimeError):
        return False


def validate_input(data: dict, artifact_root: str | None = None) -> dict:
    if not isinstance(data, dict):
        raise ValueError("Input JSON must be an object")

    # The builder always emits Partial; reject any input providing or requesting a status field
    if "status" in data:
        raise ValueError("status field is not allowed; fallback report is always Partial")

    # Enforce exact allowed top-level keys
    allowed_top_keys = {
        "title",
        "evidence_cutoff",
        "verification_date",
        "scope",
        "navigation",
        "claims",
        "verification_methods",
        "ledger_rows",
        "evidence_gap_reason",
        "freshness_rows",
    }
    unknown_top = set(data.keys()) - allowed_top_keys
    if unknown_top:
        raise ValueError(f"Unknown top-level keys: {sorted(unknown_top)}")

    # Required string fields
    for field in ("title", "evidence_cutoff", "verification_date", "scope", "evidence_gap_reason"):
        val = data.get(field)
        if not isinstance(val, str) or not val.strip():
            raise ValueError(f"Field {field!r} must be a nonempty string")

    validate_date(data["evidence_cutoff"], "evidence_cutoff")
    validate_date(data["verification_date"], "verification_date")

    # Navigation: 1-4 nonempty strings (strictly required)
    nav = data.get("navigation")
    if not isinstance(nav, list) or not (1 <= len(nav) <= 4) or not all(isinstance(x, str) and x.strip() for x in nav):
        raise ValueError("navigation must be a list of 1 to 4 nonempty strings")

    # Verification methods: strictly required nonempty list of strings
    vmethods = data.get("verification_methods")
    if not isinstance(vmethods, list) or not vmethods or not all(isinstance(vm, str) and vm.strip() for vm in vmethods):
        raise ValueError("verification_methods must be a nonempty list of strings")

    # Ledger rows: nonempty array of dicts
    ledger_rows = data.get("ledger_rows")
    if not isinstance(ledger_rows, list) or not ledger_rows:
        raise ValueError("ledger_rows must be a nonempty list")

    ledger_keys = ("ref", "role", "publisher_title", "source_type", "accessed", "record")
    exact_ledger_key_set = set(ledger_keys)
    seen_refs = set()
    validated_ledger = []
    for idx, row in enumerate(ledger_rows):
        if not isinstance(row, dict):
            raise ValueError(f"ledger_rows[{idx}] must be an object")
        unknown_row_keys = set(row.keys()) - exact_ledger_key_set
        if unknown_row_keys:
            raise ValueError(f"ledger_rows[{idx}] contains unknown keys: {sorted(unknown_row_keys)}")
        for key in ledger_keys:
            val = row.get(key)
            if not isinstance(val, str) or not val.strip():
                raise ValueError(f"ledger_rows[{idx}][{key!r}] must be a nonempty string")
        ref = row["ref"].strip()
        if not REF_RE.match(ref):
            raise ValueError(f"ledger_rows[{idx}] ref must match S<n>, got {ref!r}")
        if ref in seen_refs:
            raise ValueError(f"duplicate ledger ref {ref!r}")
        seen_refs.add(ref)

        validate_date(row["accessed"], f"ledger_rows[{idx}].accessed")

        role = row["role"].strip()
        role_low = role.lower()
        record = row["record"].strip()
        rec_low = record.lower()

        # Check record and role rules matching linter
        if rec_low.startswith("http://") or rec_low.startswith("https://"):
            if not ("direct-fetch" in role_low or "search-summary only" in role_low or "retained-without-citation" in role_low):
                raise ValueError(f"ledger external row {ref} role must contain 'direct-fetch' or 'search-summary only', got {role!r}")
        elif rec_low.startswith("local-record:"):
            local_body = record[len("local-record:"):].strip()
            if not local_body:
                raise ValueError(f"local record {ref} has no path")
            if SHA256_RE.search(local_body) is None:
                if not local_record_inside_artifact_root(local_body, artifact_root):
                    if "sha256=" in local_body:
                        raise ValueError(f"local record {ref} has a malformed sha256= hash (expected exactly 64 hex characters)")
                    else:
                        raise ValueError(f"local record {ref} is outside the artifact root or does not exist as a regular file without sha256 (expected a 'sha256=' + 64-hex hash): {record!r}")
        else:
            raise ValueError(f"ledger row {ref} record must be http(s):// or start with 'local-record:', got {record!r}")

        stype = row["source_type"].strip()
        if stype not in SOURCE_TYPES:
            raise ValueError(f"ledger row {ref} source_type must be one of {SOURCE_TYPES}, got {stype!r}")

        validated_ledger.append({
            "ref": ref,
            "role": role,
            "publisher_title": row["publisher_title"].strip(),
            "source_type": stype,
            "accessed": row["accessed"].strip(),
            "record": record,
        })

    # Claims: nonempty array of {text, refs}
    claims = data.get("claims")
    if not isinstance(claims, list) or not claims:
        raise ValueError("claims must be a nonempty list")

    exact_claim_key_set = {"text", "refs"}
    validated_claims = []
    cited_refs = set()
    for idx, claim in enumerate(claims):
        if not isinstance(claim, dict):
            raise ValueError(f"claims[{idx}] must be an object")
        unknown_claim_keys = set(claim.keys()) - exact_claim_key_set
        if unknown_claim_keys:
            raise ValueError(f"claims[{idx}] contains unknown keys: {sorted(unknown_claim_keys)}")
        text = claim.get("text")
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f"claims[{idx}].text must be a nonempty string")
        refs = claim.get("refs")
        if not isinstance(refs, list) or not refs:
            raise ValueError(f"claims[{idx}].refs must be a nonempty list of strings")
        if len(refs) != len(set(refs)):
            raise ValueError(f"claims[{idx}].refs contains duplicate refs: {refs}")
        for ref in refs:
            if not isinstance(ref, str) or ref not in seen_refs:
                raise ValueError(f"claims[{idx}].refs contains unresolved ref {ref!r}")
            cited_refs.add(ref)
        validated_claims.append({
            "text": text.strip(),
            "refs": refs,
        })

    # Ensure every ledger row is cited or has retained-without-citation
    for row in validated_ledger:
        if row["ref"] not in cited_refs and "retained-without-citation" not in row["role"].lower():
            raise ValueError(f"ledger row {row['ref']} is not cited in claims")

    # Freshness rows: optional list of 4-cell rows
    freshness_rows = data.get("freshness_rows")
    if freshness_rows is not None:
        if not isinstance(freshness_rows, list):
            raise ValueError("freshness_rows must be a list of 4-cell lists")
        for idx, frow in enumerate(freshness_rows):
            if not isinstance(frow, list) or len(frow) != 4 or not all(isinstance(c, str) and c.strip() for c in frow):
                raise ValueError(f"freshness_rows[{idx}] must have 4 nonempty string cells")

    return {
        "title": data["title"].strip(),
        "evidence_cutoff": data["evidence_cutoff"].strip(),
        "verification_date": data["verification_date"].strip(),
        "scope": data["scope"].strip(),
        "navigation": [x.strip() for x in nav],
        "claims": validated_claims,
        "freshness_rows": freshness_rows,
        "verification_methods": [vm.strip() for vm in vmethods],
        "ledger_rows": validated_ledger,
        "evidence_gap_reason": data["evidence_gap_reason"].strip(),
    }


def render_fallback_report(data: dict) -> str:
    title = data["title"]
    cutoff = data["evidence_cutoff"]
    verif_date = data["verification_date"]
    scope = data["scope"]
    nav = data["navigation"]
    claims = data["claims"]
    ledger_rows = data["ledger_rows"]
    freshness_rows = data.get("freshness_rows")
    vmethods = data["verification_methods"]
    gap_reason = data["evidence_gap_reason"]

    # Header and navigation
    lines = [
        "**Status: Partial**",
        "",
        f"# {title}",
        "",
        f"> Evidence cutoff: {cutoff} · Verification date: {verif_date} · Scope: {scope}",
        "",
        "**This report covers**",
    ]
    for idx, item in enumerate(nav, start=1):
        lines.append(f"{idx}. {item}")
    lines.append("")

    # 1. Findings
    lines.extend([
        "## 1. Findings",
        "",
    ])
    for claim in claims:
        ref_markers = "".join(f"[{ref}]" for ref in claim["refs"])
        lines.append(f"- {claim['text']} {ref_markers}")
    lines.append("")

    # Freshness & Verification Status
    lines.extend([
        "## Freshness & Verification Status",
        "",
        "| Claim | Status | Source route | Notes |",
        "| --- | --- | --- | --- |",
    ])
    if freshness_rows:
        for frow in freshness_rows:
            escaped = [escape_markdown_cell(c) for c in frow]
            lines.append(f"| {' | '.join(escaped)} |")
    else:
        # Neutral fallback summary row derived only from input/ledger identity without inventing source facts/route
        first_ref = ledger_rows[0]["ref"]
        lines.append(f"| Pre-synthesis fallback evidence checkpoint | unverified | fallback-checkpoint | [{first_ref}] |")
    lines.append("")

    # Verification Methods
    lines.extend([
        "## Verification Methods",
        "",
    ])
    for vm in vmethods:
        lines.append(vm)
    lines.append("")

    # Sources
    lines.extend([
        "## Sources",
        "",
        LEDGER_HEADER,
        LEDGER_DIVIDER,
    ])
    for row in ledger_rows:
        escaped_cells = [
            row["ref"],
            escape_markdown_cell(row["role"]),
            escape_markdown_cell(row["publisher_title"]),
            row["source_type"],
            row["accessed"],
            escape_markdown_cell(row["record"]),
        ]
        lines.append(f"| {' | '.join(escaped_cells)} |")
    lines.append("")

    # Coverage and uncertainty
    # If any ledger row is search-summary only, disclose it
    search_summary_rows = [r["ref"] for r in ledger_rows if "search-summary only" in r["role"].lower()]
    lines.extend([
        "## Coverage and uncertainty",
        "",
        f"- **Evidence gap:** {gap_reason}",
    ])
    for sref in search_summary_rows:
        lines.append(f"- **search-summary only:** {sref} was retained from search snippets without direct page fetch.")
    lines.append("")

    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="build-fallback-report.py", description="Build fallback research report.")
    parser.add_argument("input_json", help="Path to input JSON file")
    parser.add_argument("--output", required=True, help="Path to output markdown report file")
    parser.add_argument("--artifact-root", default=None, help="Optional artifact root directory for local-record validation")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        input_path = Path(args.input_json)
        output_path = Path(args.output)
        raw_text = input_path.read_text(encoding="utf-8")
        raw_data = json.loads(raw_text)
        validated = validate_input(raw_data, artifact_root=args.artifact_root)
        report_md = render_fallback_report(validated)

        output_path.parent.mkdir(parents=True, exist_ok=True)
        # Atomic write
        temp_output = output_path.with_suffix(output_path.suffix + ".tmp")
        temp_output.write_text(report_md, encoding="utf-8")
        temp_output.replace(output_path)

        result = {
            "ok": True,
            "output": str(output_path),
            "claims": len(validated["claims"]),
            "ledger_rows": len(validated["ledger_rows"]),
        }
        print(json.dumps(result, sort_keys=True))
        return 0
    except Exception as exc:
        result = {
            "ok": False,
            "error": str(exc),
        }
        print(json.dumps(result, sort_keys=True))
        return 1


if __name__ == "__main__":
    sys.exit(main())
