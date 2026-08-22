#!/usr/bin/env python3
"""Tests for build-fallback-report.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
HELPER = SCRIPTS / "build-fallback-report.py"
LINTER = SCRIPTS / "lint-report.py"


def valid_input_payload() -> dict:
    return {
        "title": "HSTECH consultation report",
        "evidence_cutoff": "2026-08-12",
        "verification_date": "2026-08-13",
        "scope": "official methodology",
        "navigation": ["Proposal", "Timeline", "Undecided items"],
        "claims": [
            {
                "text": "The consultation remains open through September 2026.",
                "refs": ["S1"],
            },
            {
                "text": "The proposed list includes 10 candidate constituents.",
                "refs": ["S1", "S2"],
            },
        ],
        "freshness_rows": [
            [
                "Consultation status",
                "externally verified",
                "direct-fetch → primary",
                "[S1]",
            ]
        ],
        "verification_methods": [
            "Open the official notice at https://example.test/official."
        ],
        "ledger_rows": [
            {
                "ref": "S1",
                "role": "direct-fetch; retained official consultation notice",
                "publisher_title": "Publisher / official notice",
                "source_type": "primary",
                "accessed": "2026-08-13",
                "record": "https://example.test/official",
            },
            {
                "ref": "S2",
                "role": "search-summary only; candidate constituent overview",
                "publisher_title": "Secondary Analysis Org",
                "source_type": "secondary",
                "accessed": "2026-08-13",
                "record": "https://example.test/summary",
            },
        ],
        "evidence_gap_reason": "synthesis/report-format failure: model output was empty or malformed; emitting deterministic pre-synthesis fallback checkpoint.",
    }


def invoke_builder(src: Path, dest: Path, *extra_args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HELPER), str(src), "--output", str(dest), *extra_args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def invoke_lint(path: Path, cutoff: str | None = None, artifact_root: Path | None = None) -> dict:
    args = [sys.executable, str(LINTER), str(path)]
    if cutoff:
        args.extend(["--cutoff", cutoff])
    if artifact_root:
        args.extend(["--artifact-root", str(artifact_root)])
    completed = subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return json.loads(completed.stdout)


def main() -> int:
    if not HELPER.is_file():
        print(f"RED: missing {HELPER}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="test-build-fallback-") as temp:
        root = Path(temp)
        input_path = root / "input.json"
        output_path = root / "fallback.md"

        # 1. Valid input produces lint-clean Partial report and preserves 6 ledger cell values
        data = valid_input_payload()
        input_path.write_text(json.dumps(data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode == 0, f"expected exit 0, got {res.returncode}: {res.stderr}"
        stdout_json = json.loads(res.stdout)
        assert stdout_json.get("ok") is True
        assert output_path.is_file()

        content = output_path.read_text(encoding="utf-8")
        lines = [line for line in content.splitlines() if line.strip()]
        assert lines[0] == "**Status: Partial**", f"expected **Status: Partial**, got {lines[0]!r}"
        assert lines[1] == "# HSTECH consultation report", f"expected H1, got {lines[1]!r}"
        assert lines[2] == "> Evidence cutoff: 2026-08-12 · Verification date: 2026-08-13 · Scope: official methodology"
        assert lines[3] == "**This report covers**"
        assert lines[4] == "1. Proposal"
        assert lines[5] == "2. Timeline"
        assert lines[6] == "3. Undecided items"

        # Audit headings in exact order
        h2_indices = {
            "## 1. Findings": content.index("## 1. Findings"),
            "## Freshness & Verification Status": content.index("## Freshness & Verification Status"),
            "## Verification Methods": content.index("## Verification Methods"),
            "## Sources": content.index("## Sources"),
            "## Coverage and uncertainty": content.index("## Coverage and uncertainty"),
        }
        assert (
            h2_indices["## 1. Findings"]
            < h2_indices["## Freshness & Verification Status"]
            < h2_indices["## Verification Methods"]
            < h2_indices["## Sources"]
            < h2_indices["## Coverage and uncertainty"]
        ), f"audit headings out of order: {h2_indices}"

        # Check preserved ledger cells
        assert "| S2 | search-summary only; candidate constituent overview | Secondary Analysis Org | secondary | 2026-08-13 | https://example.test/summary |" in content

        lint_res = invoke_lint(output_path, cutoff="2026-08-12")
        assert lint_res["ok"] is True, f"fallback report failed linting: {lint_res}"
        assert lint_res["status"] == "Partial"

        # 2. Strict required fields: title, cutoff, scope, navigation, claims, verification_methods, ledger_rows, evidence_gap_reason
        required_fields = [
            "title",
            "evidence_cutoff",
            "verification_date",
            "scope",
            "navigation",
            "claims",
            "verification_methods",
            "ledger_rows",
            "evidence_gap_reason",
        ]
        for req_field in required_fields:
            bad_data = valid_input_payload()
            del bad_data[req_field]
            input_path.write_text(json.dumps(bad_data), encoding="utf-8")
            res = invoke_builder(input_path, output_path)
            assert res.returncode != 0, f"expected failure when missing {req_field}"

            # Also test empty value for each required field
            bad_empty = valid_input_payload()
            if isinstance(bad_empty[req_field], list):
                bad_empty[req_field] = []
            else:
                bad_empty[req_field] = ""
            input_path.write_text(json.dumps(bad_empty), encoding="utf-8")
            res = invoke_builder(input_path, output_path)
            assert res.returncode != 0, f"expected failure when {req_field} is empty"

        # Navigation length must be 1-4
        bad_nav = valid_input_payload()
        bad_nav["navigation"] = ["1", "2", "3", "4", "5"]
        input_path.write_text(json.dumps(bad_nav), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure for navigation length > 4"

        # 3. Optional freshness_rows: when omitted, default must NOT invent 'externally verified' or source route
        no_freshness_data = valid_input_payload()
        del no_freshness_data["freshness_rows"]
        input_path.write_text(json.dumps(no_freshness_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode == 0, f"expected exit 0 when freshness_rows is omitted, got {res.returncode}: {res.stderr}"
        no_fresh_content = output_path.read_text(encoding="utf-8")
        assert "externally verified" not in no_fresh_content
        assert "direct-fetch → primary" not in no_fresh_content
        lint_no_fresh = invoke_lint(output_path, cutoff="2026-08-12")
        assert lint_no_fresh["ok"] is True, f"no-freshness fallback report failed linting: {lint_no_fresh}"

        # 4. Local-record validations: empty local-record, malformed sha256, valid sha256, artifact-root containment
        # Empty local record path
        bad_local_empty = valid_input_payload()
        bad_local_empty["ledger_rows"][0]["record"] = "local-record: "
        input_path.write_text(json.dumps(bad_local_empty), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure for empty local-record"

        # Malformed sha256
        bad_sha = valid_input_payload()
        bad_sha["ledger_rows"][0]["record"] = "local-record: /tmp/artifact.txt sha256=1234bad"
        input_path.write_text(json.dumps(bad_sha), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure for malformed sha256"

        # Valid sha256 (64 hex characters)
        valid_sha = valid_input_payload()
        valid_sha["ledger_rows"][0]["record"] = "local-record: /tmp/artifact.txt sha256=" + ("a" * 64)
        input_path.write_text(json.dumps(valid_sha), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode == 0, f"expected success for valid sha256, got {res.returncode}: {res.stderr}"
        lint_sha = invoke_lint(output_path, cutoff="2026-08-12")
        assert lint_sha["ok"] is True, f"valid sha256 fallback report failed linting: {lint_sha}"

        # Local record inside artifact root without sha256
        artifact_dir = root / "artifacts"
        artifact_dir.mkdir(parents=True, exist_ok=True)
        local_file = artifact_dir / "data.json"
        local_file.write_text("{}", encoding="utf-8")
        valid_artifact = valid_input_payload()
        valid_artifact["ledger_rows"][0]["record"] = f"local-record: {local_file}"
        input_path.write_text(json.dumps(valid_artifact), encoding="utf-8")
        # Fails without artifact-root
        res_no_root = invoke_builder(input_path, output_path)
        assert res_no_root.returncode != 0, "expected failure for local record without sha256 and without artifact root"
        # Succeeds with --artifact-root
        res_with_root = invoke_builder(input_path, output_path, "--artifact-root", str(artifact_dir))
        assert res_with_root.returncode == 0, f"expected success with --artifact-root: {res_with_root.stderr}"
        lint_art = invoke_lint(output_path, cutoff="2026-08-12", artifact_root=artifact_dir)
        assert lint_art["ok"] is True, f"artifact-root fallback report failed linting: {lint_art}"

        # Important 2: Builder durable unhashed local records test cases
        # Nonexistent local record
        nonexistent_artifact = valid_input_payload()
        nonexistent_artifact["ledger_rows"][0]["record"] = f"local-record: {artifact_dir / 'nonexistent.json'}"
        input_path.write_text(json.dumps(nonexistent_artifact), encoding="utf-8")
        res_nonexistent = invoke_builder(input_path, output_path, "--artifact-root", str(artifact_dir))
        assert res_nonexistent.returncode != 0, "expected failure for nonexistent local-record in builder"

        # Directory local record
        dir_artifact = valid_input_payload()
        sub_dir = artifact_dir / "sub_dir"
        sub_dir.mkdir(parents=True, exist_ok=True)
        dir_artifact["ledger_rows"][0]["record"] = f"local-record: {sub_dir}"
        input_path.write_text(json.dumps(dir_artifact), encoding="utf-8")
        res_dir = invoke_builder(input_path, output_path, "--artifact-root", str(artifact_dir))
        assert res_dir.returncode != 0, "expected failure for directory local-record in builder"

        # Symlink escape local record
        outside_file = root / "outside_builder.txt"
        outside_file.write_text("builder secret", encoding="utf-8")
        escape_symlink = artifact_dir / "escape_link.json"
        if not escape_symlink.exists():
            escape_symlink.symlink_to(outside_file)
        escape_artifact = valid_input_payload()
        escape_artifact["ledger_rows"][0]["record"] = f"local-record: {escape_symlink}"
        input_path.write_text(json.dumps(escape_artifact), encoding="utf-8")
        res_escape = invoke_builder(input_path, output_path, "--artifact-root", str(artifact_dir))
        assert res_escape.returncode != 0, "expected failure for symlink escape local-record in builder"


        # 5. Reject unresolved claim ref
        bad_data = valid_input_payload()
        bad_data["claims"].append({"text": "Unresolved claim.", "refs": ["S99"]})
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on unresolved ref S99"

        # 6. Reject duplicate ref in claim
        bad_data = valid_input_payload()
        bad_data["claims"][0]["refs"] = ["S1", "S1"]
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on duplicate ref in claim"

        # 7. Reject attempt to supply or request Verified status
        bad_data = valid_input_payload()
        bad_data["status"] = "Verified"
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure when status is supplied (cannot request Verified)"

        # 8. Reject empty ledger cells
        bad_data = valid_input_payload()
        bad_data["ledger_rows"][0]["publisher_title"] = ""
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on empty ledger cell"

        # 9. Reject malformed record / URL
        bad_data = valid_input_payload()
        bad_data["ledger_rows"][0]["record"] = "not-a-url-or-local"
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on malformed record/url"

        # 10. Strict schema: reject unknown top-level keys, unknown claim keys, unknown ledger keys
        bad_top = valid_input_payload()
        bad_top["extra_key"] = "unexpected"
        input_path.write_text(json.dumps(bad_top), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure for unknown top-level key"

        bad_claim = valid_input_payload()
        bad_claim["claims"][0]["extra_claim_key"] = "unexpected"
        input_path.write_text(json.dumps(bad_claim), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure for unknown claim key"

        bad_row = valid_input_payload()
        bad_row["ledger_rows"][0]["extra_row_key"] = "unexpected"
        input_path.write_text(json.dumps(bad_row), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure for unknown ledger_rows key"

    return 0


if __name__ == "__main__":
    sys.exit(main())
