#!/usr/bin/env python3
"""Tests for select-report-candidate.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
HELPER = SCRIPTS / "select-report-candidate.py"
BUILDER = SCRIPTS / "build-fallback-report.py"
LINTER = SCRIPTS / "lint-report.py"

LEDGER_HEADER = (
    "| Ref | Role / retained use | Publisher / title | Source type | Accessed | "
    "Exact URL or local record |"
)
LEDGER_DIVIDER = "| --- | --- | --- | --- | --- | --- |"


def valid_report_text(title: str = "Valid Report") -> str:
    return (
        "**Status: Verified**\n\n"
        f"# {title}\n\n"
        "> Evidence cutoff: 2026-08-12 · Verification date: 2026-08-13 · Scope: test scope\n\n"
        "**This report covers**\n1. Topic A\n2. Topic B\n3. Topic C\n\n"
        "## 1. Decision summary\n\n"
        "Claim one is verified [S1].\n\n"
        "## Freshness & Verification Status\n\n"
        "| Claim | Status | Source route | Notes |\n"
        "| --- | --- | --- | --- |\n"
        "| Claim one | externally verified | direct-fetch → primary | [S1] |\n\n"
        "## Verification Methods\n\n"
        "Check the source at https://example.test/source.\n\n"
        "## Sources\n\n"
        f"{LEDGER_HEADER}\n"
        f"{LEDGER_DIVIDER}\n"
        "| S1 | direct-fetch; primary evidence | Example Publisher | primary | 2026-08-13 | https://example.test/source |\n\n"
        "## Coverage and uncertainty\n\n"
        "- All planned questions returned usable structured research.\n"
    )


def repairable_report_text() -> str:
    """Report with repairable defects (missing H1 after status, unadorned role)."""
    return (
        "**Status: Verified**\n\n"
        "A note before H1 that is not an H1.\n\n"
        "## 1. Decision summary\n\n"
        "Claim one is verified [S1].\n\n"
        "## Freshness & Verification Status\n\n"
        "| Claim | Status | Source route | Notes |\n"
        "| --- | --- | --- | --- |\n"
        "| Claim one | externally verified | direct-fetch → primary | [S1] |\n\n"
        "## Verification Methods\n\n"
        "Check the source at https://example.test/source.\n\n"
        "## Sources\n\n"
        f"{LEDGER_HEADER}\n"
        f"{LEDGER_DIVIDER}\n"
        "| S1 | primary evidence | Example Publisher | primary | 2026-08-13 | https://example.test/source |\n\n"
        "## Coverage and uncertainty\n\n"
        "- All planned questions returned usable structured research.\n"
    )


def q3_malformed_report_text() -> str:
    """Q3-shaped malformed report missing Status, H1, and audit headings."""
    return (
        "Here is the research summary without required report contract headers.\n\n"
        "## Overview\n\n"
        "Some unstructured findings that fail linter completely.\n"
    )


def valid_fallback_text() -> str:
    return (
        "**Status: Partial**\n\n"
        "# Fallback Report\n\n"
        "> Evidence cutoff: 2026-08-12 · Verification date: 2026-08-13 · Scope: fallback scope\n\n"
        "**This report covers**\n1. Topic A\n2. Topic B\n3. Topic C\n\n"
        "## 1. Findings\n\n"
        "- Retained claim [S1]\n\n"
        "## Freshness & Verification Status\n\n"
        "| Claim | Status | Source route | Notes |\n"
        "| --- | --- | --- | --- |\n"
        "| Fallback claim | externally verified | direct-fetch → primary | [S1] |\n\n"
        "## Verification Methods\n\n"
        "Check the fallback source.\n\n"
        "## Sources\n\n"
        f"{LEDGER_HEADER}\n"
        f"{LEDGER_DIVIDER}\n"
        "| S1 | direct-fetch; fallback evidence | Fallback Pub | primary | 2026-08-13 | https://example.test/source |\n\n"
        "## Coverage and uncertainty\n\n"
        "- **Evidence gap:** synthesis failure; fallback emitted.\n"
    )


def invoke_selector(
    candidate: Path,
    fallback: Path,
    output: Path,
    lint_json: Path,
    selection_json: Path,
    *extra_args: str,
) -> subprocess.CompletedProcess[str]:
    cmd = [
        sys.executable,
        str(HELPER),
        "--candidate",
        str(candidate),
        "--fallback",
        str(fallback),
        "--output",
        str(output),
        "--lint-json",
        str(lint_json),
        "--selection-json",
        str(selection_json),
        *extra_args,
    ]
    return subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def main() -> int:
    if not HELPER.is_file():
        print(f"RED: missing {HELPER}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="test-select-report-") as temp:
        root = Path(temp)
        cand_path = root / "candidate.md"
        fall_path = root / "fallback.md"
        out_path = root / "cell.md"
        lint_path = root / "lint.json"
        sel_path = root / "selection.json"

        # Case 1: Valid candidate selected unchanged ("normal")
        cand_text = valid_report_text("Candidate Clean")
        cand_path.write_text(cand_text, encoding="utf-8")
        fall_path.write_text(valid_fallback_text(), encoding="utf-8")
        res = invoke_selector(cand_path, fall_path, out_path, lint_path, sel_path)
        assert res.returncode == 0, f"case 1 failed: {res.stderr}"
        sel = json.loads(sel_path.read_text(encoding="utf-8"))
        assert sel["selected"] == "normal"
        assert sel["final_lint_ok"] is True
        assert sel["final_lint_errors"] == []
        assert sel["candidate_lint"]["ok"] is True
        assert sel["repair_attempted"] is False
        assert out_path.read_text(encoding="utf-8") == cand_text
        lint_data = json.loads(lint_path.read_text(encoding="utf-8"))
        assert lint_data["ok"] is True

        # Case 2: Repairable candidate selected as "repaired"
        cand_path.write_text(repairable_report_text(), encoding="utf-8")
        res = invoke_selector(cand_path, fall_path, out_path, lint_path, sel_path)
        assert res.returncode == 0, f"case 2 failed: {res.stderr}"
        sel = json.loads(sel_path.read_text(encoding="utf-8"))
        assert sel["selected"] == "repaired"
        assert sel["repair_attempted"] is True
        assert sel.get("repair_result") is not None, "repair_result must be persisted in selection.json"
        assert sel["repair_result"]["ok"] is True
        assert sel["repair_result"]["_returncode"] == 0
        assert len(sel["repair_result"]["repairs"]) > 0
        assert sel["candidate_lint"]["ok"] is False
        assert len(sel["candidate_lint"]["errors"]) > 0
        assert sel["repaired_lint"]["ok"] is True
        assert sel["final_lint_ok"] is True
        assert sel["final_lint_errors"] == []
        lint_data = json.loads(lint_path.read_text(encoding="utf-8"))
        assert lint_data["ok"] is True
        out_content = out_path.read_text(encoding="utf-8")
        assert "direct-fetch; primary evidence" in out_content

        # Case 2b: Repair attempted but repairer failed / produced invalid repaired report -> fallback selected
        repair_fail_cand = (
            "**Status: Verified**\n\n"
            "A note before H1 that is not an H1.\n\n"
            "## 1. Decision summary\n\n"
            "Claim without required audit sections.\n"
        )
        cand_path.write_text(repair_fail_cand, encoding="utf-8")
        fall_path.write_text(valid_fallback_text(), encoding="utf-8")
        res = invoke_selector(cand_path, fall_path, out_path, lint_path, sel_path)
        assert res.returncode == 0, f"case 2b failed: {res.stderr}"
        sel = json.loads(sel_path.read_text(encoding="utf-8"))
        assert sel["selected"] == "fallback"
        assert sel["repair_attempted"] is True
        assert sel.get("repair_result") is not None
        assert sel["repaired_lint"]["ok"] is False
        assert sel["fallback_lint"]["ok"] is True
        assert sel["final_lint_ok"] is True
        assert out_path.read_text(encoding="utf-8") == fall_path.read_text(encoding="utf-8")

        # Case 3: Q3-shaped malformed candidate selects valid prebuilt fallback ("fallback")
        cand_path.write_text(q3_malformed_report_text(), encoding="utf-8")
        fall_path.write_text(valid_fallback_text(), encoding="utf-8")
        res = invoke_selector(cand_path, fall_path, out_path, lint_path, sel_path)
        assert res.returncode == 0, f"case 3 failed: {res.stderr}"
        sel = json.loads(sel_path.read_text(encoding="utf-8"))
        assert sel["selected"] == "fallback"
        assert sel["candidate_lint"]["ok"] is False
        assert len(sel["candidate_lint"]["errors"]) > 0
        assert sel["fallback_lint"]["ok"] is True
        assert sel["final_lint_ok"] is True
        assert sel["final_lint_errors"] == []
        assert out_path.read_text(encoding="utf-8") == fall_path.read_text(encoding="utf-8")
        lint_data = json.loads(lint_path.read_text(encoding="utf-8"))
        assert lint_data["ok"] is True
        assert lint_data["status"] == "Partial"

        # Case 4: Invalid candidate + missing/invalid fallback exits nonzero without overwriting candidate evidence
        orig_q3_content = q3_malformed_report_text()
        cand_path.write_text(orig_q3_content, encoding="utf-8")
        fall_path.write_text("invalid fallback content", encoding="utf-8")
        res = invoke_selector(cand_path, fall_path, cand_path, lint_path, sel_path)
        assert res.returncode != 0, "case 4 should have failed with nonzero exit code"
        assert cand_path.read_text(encoding="utf-8") == orig_q3_content, "candidate file must remain unchanged on failure"
        sel = json.loads(sel_path.read_text(encoding="utf-8"))
        assert sel["selected"] == "failed"
        assert sel["final_lint_ok"] is False
        assert sel["candidate_lint"]["ok"] is False
        assert len(sel["candidate_lint"]["errors"]) > 0
        assert sel["fallback_lint"]["ok"] is False
        assert len(sel["fallback_lint"]["errors"]) > 0
        assert sel["final_lint_errors"] == sel["candidate_lint"]["errors"]

    return 0


if __name__ == "__main__":
    sys.exit(main())
