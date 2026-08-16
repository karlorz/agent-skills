#!/usr/bin/env python3
"""review-usage.py — harvest the daily deep-research-dev usage review.

Merges the host-local usage ledger with smoke/eval ``meta.json`` files and
writes an ignored markdown review. Never writes inside a SkillWiki vault.

Stdlib only; no network, no Docker.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
PLUGIN_ROOT = SCRIPTS.parent
REPO_DEFAULT = PLUGIN_ROOT.parent.parent
DEFAULT_LEDGER = Path.home() / ".grok" / "deep-research-dev-usage" / "ledger.jsonl"
DEFAULT_SMOKE_ROOTS = (
    ".superpowers/sdd/deep-research-dev-eval-matrix",
    ".superpowers/sdd/deep-research-dev-reliability-report-lint",
    ".superpowers/sdd/deep-research-dev-presentation-ledger",
    ".superpowers/sdd/deep-research-dev-smoke",
    ".superpowers/sdd/deep-research-dev-smoke-b",
)


def is_inside_vault(path: Path) -> bool:
    resolved = path.resolve()
    for parent in [resolved, *resolved.parents]:
        if (parent / "SCHEMA.md").is_file() and (parent / "projects").is_dir():
            return True
    return False


def utc_today() -> str:
    return _dt.datetime.now(tz=_dt.timezone.utc).strftime("%Y-%m-%d")


def load_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            records.append(payload)
    return records


def date_of(value: object) -> str | None:
    if not isinstance(value, str) or len(value) < 10:
        return None
    return value[:10]


def collect_smoke(roots: list[Path], day: str) -> list[dict]:
    found = []
    for root in roots:
        if not root.is_dir():
            continue
        for meta_path in root.rglob("meta.json"):
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(meta, dict):
                continue
            started = date_of(meta.get("started")) or date_of(meta.get("finished"))
            if started != day:
                continue
            lint_errors = meta.get("report_lint_errors") or []
            found.append(
                {
                    "source": "smoke",
                    "path": str(meta_path),
                    "query_truncated": str(meta.get("query_id") or "")[:200],
                    "status": "unknown",
                    "lint_ok": meta.get("report_lint_ok"),
                    "lint_errors": lint_errors if isinstance(lint_errors, list) else [],
                    "duration_s": meta.get("duration_s"),
                    "outcome": meta.get("outcome"),
                    "started": meta.get("started"),
                    "cell": str(meta_path.parent / "cell.md")
                    if (meta_path.parent / "cell.md").is_file()
                    else None,
                }
            )
    return found


def render(day: str, ledger: list[dict], smoke: list[dict]) -> str:
    ledger_for_day = [row for row in ledger if date_of(row.get("recorded_at")) == day]
    lint_failures = [
        row
        for row in [*ledger_for_day, *smoke]
        if row.get("lint_ok") is False
    ]
    lines = [
        f"# deep-research-dev daily usage review — {day}",
        "",
        "This review is a local ignored artifact. It is not a vault page and",
        "is not a promotion decision.",
        "",
        f"- Ledger records: {len(ledger_for_day)}",
        f"- Smoke metas: {len(smoke)}",
        f"- Lint failures: {len(lint_failures)}",
        "",
        "## Lint failures",
        "",
    ]
    if not lint_failures:
        lines.append("None.")
    else:
        for row in lint_failures:
            query = row.get("query_truncated") or "(no query)"
            errors = row.get("lint_errors") or []
            lines.append(f"- `{query}`")
            for err in errors[:8]:
                lines.append(f"  - {err}")
    lines.extend(["", "## Runs", ""])
    if not ledger_for_day and not smoke:
        lines.append("No runs recorded for this day.")
    else:
        lines.append("| Source | Query | Outcome | Lint | Duration s |")
        lines.append("| --- | --- | --- | --- | ---: |")
        for row in [*ledger_for_day, *smoke]:
            source = row.get("source") or ""
            query = (row.get("query_truncated") or "")[:60]
            outcome = row.get("outcome") or ""
            lint = row.get("lint_ok")
            dur = row.get("duration_s") if row.get("duration_s") is not None else ""
            lines.append(f"| {source} | {query} | {outcome} | {lint} | {dur} |")
    lines.append("")
    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="review-usage.py")
    parser.add_argument("--date", default=utc_today())
    parser.add_argument(
        "--ledger",
        default=os.environ.get("DEEP_RESEARCH_DEV_USAGE_LEDGER") or str(DEFAULT_LEDGER),
    )
    parser.add_argument("--repo", default=str(REPO_DEFAULT))
    parser.add_argument("--smoke-root", action="append", default=None)
    parser.add_argument("--out", default=None)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    repo = Path(args.repo)
    out = (
        Path(args.out)
        if args.out
        else repo / ".superpowers" / "sdd" / "deep-research-dev-usage" / "reviews" / f"{args.date}.md"
    )
    if is_inside_vault(out):
        print(f"error: refusing to write review inside SkillWiki vault: {out}", file=sys.stderr)
        return 2
    smoke_roots = (
        [Path(root) for root in args.smoke_root]
        if args.smoke_root
        else [repo / rel for rel in DEFAULT_SMOKE_ROOTS]
    )
    try:
        ledger = load_jsonl(Path(args.ledger))
        smoke = collect_smoke(smoke_roots, args.date)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render(args.date, ledger, smoke), encoding="utf-8")
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"ok": True, "out": str(out)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
