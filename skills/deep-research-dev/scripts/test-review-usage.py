#!/usr/bin/env python3
"""Tests for review-usage.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
HELPER = SCRIPTS / "review-usage.py"


def main() -> int:
    if not HELPER.is_file():
        print(f"RED: missing {HELPER}", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory(prefix="test-review-usage-") as temp:
        root = Path(temp)
        ledger = root / "ledger.jsonl"
        smoke_root = root / "smoke" / "cell-a"
        smoke_root.mkdir(parents=True)
        ledger.write_text(
            json.dumps(
                {
                    "recorded_at": "2026-08-17T01:00:00Z",
                    "source": "phase6",
                    "query_truncated": "skillwiki latest",
                    "lint_ok": False,
                    "lint_errors": ["expected an H1 title"],
                    "outcome": "ok",
                    "duration_s": 12,
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        (smoke_root / "meta.json").write_text(
            json.dumps(
                {
                    "started": "2026-08-17T02:00:00Z",
                    "query_id": "hstech",
                    "report_lint_ok": True,
                    "report_lint_errors": [],
                    "duration_s": 463,
                    "outcome": "ok",
                }
            ),
            encoding="utf-8",
        )
        out = root / "reviews" / "2026-08-17.md"
        completed = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "--date",
                "2026-08-17",
                "--ledger",
                str(ledger),
                "--repo",
                str(root),
                "--smoke-root",
                str(root / "smoke"),
                "--out",
                str(out),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert completed.returncode == 0, completed.stderr
        text = out.read_text(encoding="utf-8")
        assert "Ledger records: 1" in text
        assert "Smoke metas: 1" in text
        assert "skillwiki latest" in text
        assert "expected an H1 title" in text

        vault = root / "vault"
        (vault / "projects").mkdir(parents=True)
        (vault / "SCHEMA.md").write_text("# schema\n", encoding="utf-8")
        refused = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "--date",
                "2026-08-17",
                "--ledger",
                str(ledger),
                "--out",
                str(vault / "reviews" / "2026-08-17.md"),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert refused.returncode == 2, refused.stderr
        assert "vault" in refused.stderr.lower()
    print("review-usage: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
