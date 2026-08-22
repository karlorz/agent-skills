#!/usr/bin/env python3
"""Tests for structure-only report repair."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
HELPER = SCRIPTS / "repair-report-structure.py"
LINTER = SCRIPTS / "lint-report.py"

LEDGER_HEADER = (
    "| Ref | Role / retained use | Publisher / title | Source type | Accessed | "
    "Exact URL or local record |"
)
LEDGER_DIVIDER = "| --- | --- | --- | --- | --- | --- |"


def broken_identity() -> str:
    return (
        "**Status: Verified**\n"
        "\n"
        "（parenthetical note that is not an H1）\n"
        "\n"
        "## 1. Decision summary\n"
        "\n"
        "Consultation remains open [S1].\n"
        "\n"
        "## Freshness & Verification Status\n"
        "\n"
        "| Claim | Status | Source route | Notes |\n"
        "| --- | --- | --- | --- |\n"
        "| Open | externally verified | direct-fetch → primary | [S1] |\n"
        "\n"
        "## Verification Methods\n"
        "\n"
        "Open the official notice.\n"
        "\n"
        "## Sources\n"
        "\n"
        f"{LEDGER_HEADER}\n"
        f"{LEDGER_DIVIDER}\n"
        "| S1 | direct-fetch; 全部主张的主要依据 | Publisher | primary | 2026-08-13 | https://example.test/official |\n"
        "| S2 | 本地说明 | Local notes | repository | 2026-08-13 | 本地路径：/tmp/hstech_research/ |\n"
        "\n"
        "## Coverage and uncertainty\n"
        "\n"
        "- **Topic-inherent unknown:** final adoption remains undecided.\n"
    )


def invoke_repair(src: Path, dest: Path, *args: str) -> dict:
    completed = subprocess.run(
        [sys.executable, str(HELPER), str(src), "--output", str(dest), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    return json.loads(completed.stdout)


def invoke_lint(path: Path) -> dict:
    completed = subprocess.run(
        [sys.executable, str(LINTER), str(path)],
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

    helper_src = HELPER.read_text(encoding="utf-8")
    assert "ROLE_TOKENS" not in helper_src, "repairer must not define unused ROLE_TOKENS"
    assert "role_has_token" not in helper_src, "repairer must not define unused role_has_token()"

    with tempfile.TemporaryDirectory(prefix="test-repair-report-") as temp:
        root = Path(temp)
        src = root / "broken.md"
        dest = root / "repaired.md"
        original = broken_identity()
        src.write_text(original, encoding="utf-8")
        summary = invoke_repair(src, dest)
        repaired = dest.read_text(encoding="utf-8")
        assert summary["changed"] is True
        assert any("H1" in item for item in summary["repairs"])
        lines = [line for line in repaired.splitlines() if line.strip()]
        assert lines[0] == "**Status: Verified**"
        assert lines[1].startswith("# ")
        assert "（parenthetical note that is not an H1）" in repaired
        assert "Consultation remains open [S1]." in repaired
        assert "direct-fetch; 全部主张的主要依据" in repaired
        assert "local-record: 本地路径：/tmp/hstech_research/" in repaired
        assert original.splitlines()[0] == repaired.splitlines()[0]
        lint = invoke_lint(dest)
        identity_errors = [
            error
            for error in lint["errors"]
            if "H1 title" in error or "direct-fetch" in error or "must be an http" in error
        ]
        assert identity_errors == [], identity_errors
        leftover = [
            error
            for error in lint["errors"]
            if "sha256" in error or "outside the artifact root" in error or "not cited" in error
        ]
        assert leftover, lint["errors"]

        moved_src = root / "moved.md"
        moved_src.write_text(
            original.replace(
                "（parenthetical note that is not an H1）",
                "（parenthetical note that is not an H1）\n\n# Late title",
            ),
            encoding="utf-8",
        )
        moved_dest = root / "moved-out.md"
        invoke_repair(moved_src, moved_dest)
        moved = [line for line in moved_dest.read_text(encoding="utf-8").splitlines() if line.strip()]
        assert moved[0] == "**Status: Verified**"
        assert moved[1] == "# Late title"

        # Ambiguous external row without direct-fetch or search-summary only must NOT be guessed as direct-fetch
        ambiguous_external = (
            "**Status: Verified**\n\n"
            "# Valid title\n\n"
            "Consultation remains open [S1].\n\n"
            "## Freshness & Verification Status\n\n"
            "| Claim | Status | Source route | Notes |\n"
            "| --- | --- | --- | --- |\n"
            "| Open | externally verified | external route → primary | [S1] |\n\n"
            "## Verification Methods\n\n"
            "Open official notice.\n\n"
            "## Sources\n\n"
            f"{LEDGER_HEADER}\n"
            f"{LEDGER_DIVIDER}\n"
            "| S1 | official announcement | Publisher | primary | 2026-08-13 | https://example.test/official |\n\n"
            "## Coverage and uncertainty\n\n"
            "- **Topic-inherent unknown:** final adoption remains undecided.\n"
        )
        amb_src = root / "ambiguous.md"
        amb_dest = root / "ambiguous_repaired.md"
        amb_src.write_text(ambiguous_external, encoding="utf-8")
        amb_summary = invoke_repair(amb_src, amb_dest)
        amb_repaired = amb_dest.read_text(encoding="utf-8")
        assert "direct-fetch" not in amb_repaired, "repair must not invent direct-fetch for ambiguous external rows"
        assert amb_summary["changed"] is False, "ambiguous external row should not be changed"
        amb_lint = invoke_lint(amb_dest)
        assert amb_lint["ok"] is False, "ambiguous external row must still be rejected by linter"
        assert any("role must contain 'direct-fetch' or 'search-summary only'" in err for err in amb_lint["errors"])
    print("repair-report-structure: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
