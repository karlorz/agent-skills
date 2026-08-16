#!/usr/bin/env python3
"""Tests for record-usage.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
HELPER = SCRIPTS / "record-usage.py"


def run(*args: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HELPER), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def main() -> int:
    if not HELPER.is_file():
        print(f"RED: missing {HELPER}", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory(prefix="test-record-usage-") as temp:
        home = Path(temp) / "usage"
        query = "sk-abcdefghijklmnopqrstuvwxyz012345 " + ("A" * 250)
        completed = run(
            "--home",
            str(home),
            "--query",
            query,
            "--source",
            "phase6",
            "--invocation-mode",
            "interactive",
            "--output-mode",
            "stdout",
            "--status",
            "Partial",
            "--lint-ok",
            "false",
            "--outcome",
            "ok",
        )
        assert completed.returncode == 0, completed.stderr
        ledger = home / "ledger.jsonl"
        record = json.loads(ledger.read_text(encoding="utf-8"))
        assert record["schema"] == "deep-research-dev-usage.v1"
        assert record["query_len"] == len(query)
        assert len(record["query_truncated"]) == 200
        assert "sk-abcdefghijklmnopqrstuvwxyz012345" not in record["query_truncated"]
        assert record["status"] == "Partial"
        assert record["lint_ok"] is False
        assert record["source"] == "phase6"

        vault = Path(temp) / "vault"
        (vault / "projects").mkdir(parents=True)
        (vault / "SCHEMA.md").write_text("# schema\n", encoding="utf-8")
        refused = run("--home", str(vault), "--query", "topic")
        assert refused.returncode == 2, refused.stderr
        assert "vault" in refused.stderr.lower()
        assert not (vault / "ledger.jsonl").exists()

        lint = Path(temp) / "lint.json"
        lint.write_text(
            json.dumps({"ok": False, "errors": ["expected an H1 title"]}),
            encoding="utf-8",
        )
        completed = run(
            "--home",
            str(home),
            "--query",
            "second run",
            "--source",
            "smoke",
            "--lint-json",
            str(lint),
        )
        assert completed.returncode == 0, completed.stderr
        rows = [
            json.loads(line)
            for line in ledger.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        assert len(rows) == 2
        assert rows[1]["source"] == "smoke"
        assert rows[1]["lint_errors"] == ["expected an H1 title"]
    print("record-usage: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
