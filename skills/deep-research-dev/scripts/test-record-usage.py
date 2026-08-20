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

        # 1. --lint-ok false without --lint-json must exit 2 and write no ledger row
        lint_false_alone = run(
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
        assert lint_false_alone.returncode == 2, (
            f"expected exit 2 for --lint-ok false alone, got {lint_false_alone.returncode}"
        )
        ledger = home / "ledger.jsonl"
        assert not ledger.exists(), "ledger row must not be written on invalid lint-ok false"

        # 2. Valid run with --plugin-version, --duration-s, and --lint-ok true round-trips
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
            "Verified",
            "--lint-ok",
            "true",
            "--duration-s",
            "14.5",
            "--plugin-version",
            "0.1.0-beta.4",
            "--outcome",
            "ok",
        )
        assert completed.returncode == 0, completed.stderr
        record = json.loads(ledger.read_text(encoding="utf-8"))
        assert record["schema"] == "deep-research-dev-usage.v1"
        assert record["query_len"] == len(query)
        assert len(record["query_truncated"]) == 200
        assert "sk-abcdefghijklmnopqrstuvwxyz012345" not in record["query_truncated"]
        assert record["status"] == "Verified"
        assert record["lint_ok"] is True
        assert record["duration_s"] == 14.5
        assert record["plugin_version"] == "0.1.0-beta.4"
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
