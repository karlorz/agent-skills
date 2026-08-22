#!/usr/bin/env python3
"""capture-session-provenance.py — resolve the unique fresh deep-research-dev
session for a headless run and freeze its summary.

Contract with smoke-ephemeral.sh / the dev-loop smoke runner:

* ``snapshot`` captures the direct-child session IDs before launch. ``resolve``
  scans the post-launch direct child directories minus that snapshot. Each fresh
  candidate must carry a parseable ``summary.json`` and a decodable
  ``chat_history.jsonl`` whose user records contain exactly the full
  reconstructed headless prompt:

      /deep-research-dev:deep-research-dev --ephemeral --unattended <query>

      When the research report is complete, print a line exactly:
      ===REPORT===
      then print the final report only (no tool narration).

* The prompt match is exact: decoded JSONL user content must either equal the
  full reconstructed prompt after trailing-whitespace normalization or place
  that exact normalized prompt in its explicit ``<user_query>`` envelope. It
  never uses a raw substring or prefix search.
* ``created_at`` (summary) is compared as a timezone-aware datetime against
  ``--started``; naive or unparseable timestamps never match.
* ``agent_name`` is captured as-is (null permitted) and never used to filter.
* A unique match freezes the byte-identical ``summary.json`` to
  ``--frozen-summary`` (parents created) and counts assistant ``tool_calls``
  by name. Any failure — missing/unreadable root or before file, invalid
  ``--started``, malformed candidate files, or an unfreezable summary —
  fails closed: no model/session is reported.
* Exit codes: 0 exactly one candidate, 1 zero/multiple/not-observable,
  2 bad CLI invocation. Output JSON is deterministic (sorted keys, indent).

Stdlib only; no network access.
"""

from __future__ import annotations

import argparse
import datetime as _datetime
import hashlib
import json
import re
import sys
from pathlib import Path

PREFIX = "/deep-research-dev:deep-research-dev --ephemeral --unattended "
FRAMING = (
    "\n\nWhen the research report is complete, print a line exactly:\n"
    "===REPORT===\n"
    "then print the final report only (no tool narration)."
)


def build_prompt(query: str) -> str:
    """Reconstruct the exact headless prompt for a query."""
    return PREFIX + query + FRAMING


def parse_iso_aware(value: str) -> _datetime.datetime | None:
    """Parse ISO-8601 with an explicit UTC offset; None when not parseable."""
    text = value[:-1] + "+00:00" if value.endswith(("Z", "z")) else value
    try:
        parsed = _datetime.datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed


class JsonlError(Exception):
    """Raised when chat_history.jsonl cannot be decoded reliably."""


def decode_records(path: Path) -> list[dict]:
    """Decode chat_history.jsonl into record dicts (blank lines ignored)."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise JsonlError(str(exc)) from exc
    records: list[dict] = []
    for number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except ValueError as exc:
            raise JsonlError(f"line {number}: {exc}") from exc
        if not isinstance(record, dict):
            raise JsonlError(f"line {number}: record is not a JSON object")
        records.append(record)
    return records


def user_text(record: dict) -> str | None:
    """Full decoded text of a user record; None when content is undecodable."""
    content = record.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "text":
                continue
            text = block.get("text")
            if not isinstance(text, str):
                return None
            parts.append(text)
        return "".join(parts)
    return None


def user_text_matches_prompt(record: dict, prompt_text: str) -> bool:
    """Return whether decoded user content carries exactly the known prompt.

    Grok may persist the raw headless prompt as the complete user message or
    wrap it in a ``<user_query>`` block alongside host metadata and skill
    context. Decode JSONL before matching, and inspect only that explicit user
    query envelope; arbitrary substring matching would allow a quoted or
    prefix-extended command to establish provenance.
    """
    text = user_text(record)
    if text is None:
        return False
    normalized_prompt = prompt_text.rstrip()
    if text.rstrip() == normalized_prompt:
        return True
    for match in re.finditer(r"<user_query>\s*(.*?)\s*</user_query>", text, re.DOTALL):
        if match.group(1).rstrip() == normalized_prompt:
            return True
    return False


def count_tool_calls(records: list[dict]) -> dict[str, int]:
    """Count assistant tool_calls by name; non-str names are ignored."""
    counts: dict[str, int] = {}
    for record in records:
        if record.get("type") != "assistant":
            continue
        calls = record.get("tool_calls")
        if not isinstance(calls, list):
            continue
        for call in calls:
            if not isinstance(call, dict):
                continue
            name = call.get("name")
            if isinstance(name, str):
                counts[name] = counts.get(name, 0) + 1
    return counts


def evaluate(session_dir: Path, started: _datetime.datetime, prompt_text: str) -> dict | None:
    """Match a single fresh candidate; None when it does not qualify."""
    summary_path = session_dir / "summary.json"
    try:
        summary_bytes = summary_path.read_bytes()
    except OSError:
        return None
    try:
        summary = json.loads(summary_bytes)
    except ValueError:
        return None
    if not isinstance(summary, dict):
        return None
    created_raw = summary.get("created_at")
    if not isinstance(created_raw, str):
        return None
    created = parse_iso_aware(created_raw)
    if created is None or created < started:
        return None
    agent_name = summary.get("agent_name")
    if agent_name is not None and not isinstance(agent_name, str):
        return None
    model = summary.get("current_model_id")
    if not isinstance(model, str):
        return None
    try:
        records = decode_records(session_dir / "chat_history.jsonl")
    except JsonlError:
        return None
    if not any(
        record.get("type") == "user" and user_text_matches_prompt(record, prompt_text)
        for record in records
    ):
        return None
    return {
        "session_id": session_dir.name,
        "created_at": created_raw,
        "agent_name": agent_name,
        "current_model_id": model,
        "summary_sha256": hashlib.sha256(summary_bytes).hexdigest(),
        "summary_bytes": summary_bytes,
        "tool_counts": count_tool_calls(records),
    }


def write_output(path: Path, observation: dict) -> None:
    """Write deterministic JSON; fail closed on stderr when impossible."""
    text = json.dumps(observation, sort_keys=True, indent=2) + "\n"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    except OSError as exc:
        print(f"error: cannot write output {path}: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


def run_resolve(args: argparse.Namespace) -> int:
    observation = {
        "actual_model": None,
        "tool_counts": {},
        "fresh_session_ids": [],
        "actual_model_matches": [],
    }

    if (args.query is None and args.prompt_file is None) or (
        args.query is not None and args.prompt_file is not None
    ):
        observation["observation_error"] = (
            "exactly one of --query or --prompt-file must be provided"
        )
        write_output(args.output, observation)
        return 2

    if args.prompt_file is not None:
        try:
            prompt_text = args.prompt_file.read_text(encoding="utf-8")
        except OSError as exc:
            observation["observation_error"] = (
                f"cannot read prompt file {args.prompt_file}: {exc}"
            )
            write_output(args.output, observation)
            return 1
    else:
        prompt_text = build_prompt(args.query)

    started = parse_iso_aware(args.started)
    if started is None:
        observation["observation_error"] = (
            f"invalid started timestamp {args.started!r}: "
            "expected ISO-8601 datetime with UTC offset (e.g. 2026-08-13T10:00:00Z)"
        )
        write_output(args.output, observation)
        return 1

    try:
        before_ids = set(args.before.read_text(encoding="utf-8").splitlines())
    except OSError as exc:
        observation["observation_error"] = f"cannot read before file {args.before}: {exc}"
        write_output(args.output, observation)
        return 1

    try:
        fresh = sorted(
            entry.name for entry in args.sessions_root.iterdir() if entry.is_dir()
        )
    except OSError as exc:
        observation["observation_error"] = f"cannot list sessions root {args.sessions_root}: {exc}"
        write_output(args.output, observation)
        return 1
    fresh = [name for name in fresh if name not in before_ids]
    observation["fresh_session_ids"] = fresh

    matches = [
        info
        for name in fresh
        if (info := evaluate(args.sessions_root / name, started, prompt_text)) is not None
    ]
    observation["actual_model_matches"] = [
        {
            "session_id": info["session_id"],
            "model": info["current_model_id"],
            "created_at": info["created_at"],
        }
        for info in matches
    ]

    if len(matches) == 1:
        unique = matches[0]
        try:
            args.frozen_summary.parent.mkdir(parents=True, exist_ok=True)
            args.frozen_summary.write_bytes(unique["summary_bytes"])
        except OSError as exc:
            observation["observation_error"] = (
                f"cannot freeze summary to {args.frozen_summary}: {exc}"
            )
            write_output(args.output, observation)
            return 1
        observation["actual_model"] = unique["current_model_id"]
        observation["session_id"] = unique["session_id"]
        observation["session_provenance"] = {
            "session_id": unique["session_id"],
            "created_at": unique["created_at"],
            "agent_name": unique["agent_name"],
            "current_model_id": unique["current_model_id"],
            "summary_sha256": unique["summary_sha256"],
        }
        observation["tool_counts"] = dict(sorted(unique["tool_counts"].items()))
        write_output(args.output, observation)
        return 0

    if len(matches) == 0:
        observation["observation_error"] = "no matching session found in fresh candidates"
    else:
        observation["observation_error"] = (
            f"ambiguous: {len(matches)} fresh sessions match the query"
        )
    write_output(args.output, observation)
    return 1


def run_snapshot(args: argparse.Namespace) -> int:
    try:
        session_ids = sorted(
            entry.name for entry in args.sessions_root.iterdir() if entry.is_dir()
        )
    except OSError as exc:
        print(f"error: cannot list sessions root {args.sessions_root}: {exc}", file=sys.stderr)
        return 1
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text("".join(f"{session_id}\n" for session_id in session_ids), encoding="utf-8")
    except OSError as exc:
        print(f"error: cannot write snapshot {args.output}: {exc}", file=sys.stderr)
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="capture-session-provenance.py",
        description=(
            "Resolve the unique fresh deep-research-dev session for a headless "
            "run and freeze its summary."
        ),
    )
    subparsers = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")
    snapshot = subparsers.add_parser("snapshot", help="snapshot current session IDs before launch")
    snapshot.add_argument("--sessions-root", required=True, metavar="PATH", type=Path)
    snapshot.add_argument("--output", required=True, metavar="OUTPUT.txt", type=Path)
    resolve = subparsers.add_parser(
        "resolve", help="resolve the unique matching fresh session"
    )
    resolve.add_argument("--sessions-root", required=True, metavar="PATH", type=Path)
    resolve.add_argument("--before", required=True, metavar="PATH", type=Path)
    resolve.add_argument("--started", required=True, metavar="ISO_Z")
    resolve.add_argument("--query", required=False, default=None, metavar="QUERY")
    resolve.add_argument(
        "--prompt-file", required=False, default=None, metavar="PATH", type=Path
    )
    resolve.add_argument("--output", required=True, metavar="OUTPUT.json", type=Path)
    resolve.add_argument("--frozen-summary", required=True, metavar="PATH", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "snapshot":
        return run_snapshot(args)
    if args.command == "resolve":
        return run_resolve(args)
    parser.error(f"unknown command {args.command!r}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
