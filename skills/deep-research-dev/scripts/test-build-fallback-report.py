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
                "publisher_title": "Secondary Analysis",
                "source_type": "secondary",
                "accessed": "2026-08-13",
                "record": "https://example.test/summary",
            },
        ],
        "evidence_gap_reason": "synthesis/report-format failure: model output was empty or malformed; emitting deterministic pre-synthesis fallback checkpoint.",
    }


def invoke_builder(src: Path, dest: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HELPER), str(src), "--output", str(dest)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def invoke_lint(path: Path, cutoff: str | None = None) -> dict:
    args = [sys.executable, str(LINTER), str(path)]
    if cutoff:
        args.extend(["--cutoff", cutoff])
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

        # 1. Valid input produces lint-clean Partial report
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
        assert "## 1. Findings" in content
        assert "## Freshness & Verification Status" in content
        assert "## Verification Methods" in content
        assert "## Sources" in content
        assert "## Coverage and uncertainty" in content
        assert "Evidence gap:" in content or "Evidence gap —" in content or "Evidence gap -" in content

        lint_res = invoke_lint(output_path, cutoff="2026-08-12")
        assert lint_res["ok"] is True, f"fallback report failed linting: {lint_res}"
        assert lint_res["status"] == "Partial"

        # 2. Reject missing required fields: title, cutoff, scope, claims, ledger_rows
        for req_field in ["title", "evidence_cutoff", "scope", "claims", "ledger_rows"]:
            bad_data = valid_input_payload()
            del bad_data[req_field]
            input_path.write_text(json.dumps(bad_data), encoding="utf-8")
            res = invoke_builder(input_path, output_path)
            assert res.returncode != 0, f"expected failure when missing {req_field}"

        # 3. Reject unresolved claim ref
        bad_data = valid_input_payload()
        bad_data["claims"].append({"text": "Unresolved claim.", "refs": ["S99"]})
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on unresolved ref S99"

        # 4. Reject duplicate ref in claim
        bad_data = valid_input_payload()
        bad_data["claims"][0]["refs"] = ["S1", "S1"]
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on duplicate ref in claim"

        # 5. Reject attempt to supply or request Verified status
        bad_data = valid_input_payload()
        bad_data["status"] = "Verified"
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure when status is supplied (cannot request Verified)"

        # 6. Reject empty ledger cells
        bad_data = valid_input_payload()
        bad_data["ledger_rows"][0]["publisher_title"] = ""
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on empty ledger cell"

        # 7. Reject malformed record / URL
        bad_data = valid_input_payload()
        bad_data["ledger_rows"][0]["record"] = "not-a-url-or-local"
        input_path.write_text(json.dumps(bad_data), encoding="utf-8")
        res = invoke_builder(input_path, output_path)
        assert res.returncode != 0, "expected failure on malformed record/url"

    return 0


if __name__ == "__main__":
    sys.exit(main())
