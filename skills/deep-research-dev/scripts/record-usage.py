#!/usr/bin/env python3
"""record-usage.py — append one deep-research-dev usage record.

The host-local ledger is append-only JSONL. Default home:

    ~/.grok/deep-research-dev-usage/ledger.jsonl

Override with ``DEEP_RESEARCH_DEV_USAGE_HOME`` or ``--home``. The writer
never creates files inside a SkillWiki vault (SCHEMA.md + projects/).

Stdlib only; no network, no Docker.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import sys
from pathlib import Path

SCHEMA = "deep-research-dev-usage.v1"
QUERY_TRUNCATE = 200
DEFAULT_HOME = Path.home() / ".grok" / "deep-research-dev-usage"
LEDGER_NAME = "ledger.jsonl"
SECRET_RE = re.compile(
    r"(?i)(?:"
    r"sk-[A-Za-z0-9]{10,}"
    r"|bearer\s+[A-Za-z0-9._\-]{12,}"
    r"|(?:api[_-]?key|token|password|secret)\s*[:=]\s*\S+"
    r"|AKIA[0-9A-Z]{16}"
    r")"
)


class UsageError(Exception):
    pass


def utc_now() -> str:
    return _dt.datetime.now(tz=_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def is_inside_vault(path: Path) -> bool:
    resolved = path.resolve()
    for parent in [resolved, *resolved.parents]:
        if (parent / "SCHEMA.md").is_file() and (parent / "projects").is_dir():
            return True
    return False


def redact(text: str) -> str:
    return SECRET_RE.sub("[REDACTED:secret]", text)


def query_fields(query: str) -> dict:
    redacted = redact(query)
    return {
        "query_len": len(query),
        "query_sha256": hashlib.sha256(query.encode("utf-8")).hexdigest(),
        "query_truncated": redacted[:QUERY_TRUNCATE],
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="record-usage.py")
    parser.add_argument("--query", required=True)
    parser.add_argument("--home", default=os.environ.get("DEEP_RESEARCH_DEV_USAGE_HOME"))
    parser.add_argument("--source", choices=("phase6", "smoke"), default="phase6")
    parser.add_argument(
        "--invocation-mode",
        choices=("interactive", "unattended"),
        default="unattended",
    )
    parser.add_argument(
        "--output-mode",
        choices=("stdout", "file", "vault"),
        default="stdout",
    )
    parser.add_argument("--duration-s", type=float, required=True)
    parser.add_argument(
        "--outcome",
        choices=("ok", "failed", "unknown"),
        default="unknown",
    )
    parser.add_argument(
        "--status",
        choices=("Verified", "Partial", "unknown"),
        default="unknown",
    )
    parser.add_argument("--lint-ok", choices=("true", "false", "null"), default="null")
    parser.add_argument("--lint-json", default=None)
    parser.add_argument("--plugin-version", required=True)
    parser.add_argument("--cwd", default=None)
    parser.add_argument("--report-path", default=None)
    parser.add_argument("--smoke-meta", default=None)
    return parser.parse_args(argv)


def lint_fields(args: argparse.Namespace) -> tuple[bool | None, list[str]]:
    if args.lint_json:
        payload = json.loads(Path(args.lint_json).read_text(encoding="utf-8"))
        ok = payload.get("ok") is True
        errors = list(payload.get("errors") or [])
        if not ok and not errors:
            raise UsageError("--lint-json with ok: false requires non-empty errors")
        return ok, errors[:20]
    if args.lint_ok == "true":
        return True, []
    if args.lint_ok == "false":
        raise UsageError("--lint-ok false requires --lint-json to provide lint errors")
    return None, []


def build_record(args: argparse.Namespace) -> dict:
    if not str(args.plugin_version).strip():
        raise UsageError("--plugin-version must be non-empty")
    lint_ok, lint_errors = lint_fields(args)
    record = {
        "cwd": args.cwd,
        "duration_s": args.duration_s,
        "invocation_mode": args.invocation_mode,
        "lint_errors": lint_errors,
        "lint_ok": lint_ok,
        "outcome": args.outcome,
        "output_mode": args.output_mode,
        "plugin_version": args.plugin_version,
        "recorded_at": utc_now(),
        "report_path": args.report_path,
        "schema": SCHEMA,
        "smoke_meta_path": args.smoke_meta,
        "source": args.source,
        "status": args.status,
        **query_fields(args.query),
    }
    return {key: record[key] for key in sorted(record)}


def append_record(home: Path, record: dict) -> Path:
    if is_inside_vault(home):
        raise UsageError(f"refusing to write usage ledger inside SkillWiki vault: {home}")
    home.mkdir(parents=True, exist_ok=True)
    ledger = home / LEDGER_NAME
    with ledger.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    return ledger


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        home = Path(args.home).expanduser() if args.home else DEFAULT_HOME
        if not home.is_absolute():
            raise UsageError("--home must be an absolute directory")
        record = build_record(args)
        ledger = append_record(home, record)
    except UsageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"ok": True, "ledger": str(ledger)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
