#!/usr/bin/env python3
"""repair-report-structure.py — structure-only presentation repair.

Allowed repairs:

* After ``**Status: Verified|Partial**``, the next substantive line must be an
  H1. Insert or move an H1; keep any interposed note after that H1.
* Non-URL path cells get a ``local-record:`` prefix when missing.

The repairer must not change Status, claim sentences, Coverage, existing URLs,
or invent role routes (such as ``direct-fetch`` or ``search-summary only``)
or ``sha256=`` hashes.

Stdlib only; no network, no Docker.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

STATUS_RE = re.compile(r"^\*\*Status: (Verified|Partial)\*\*$")
H1_RE = re.compile(r"^#\s+(.+)$")
H2_RE = re.compile(r"^##\s+(.+)$")
NUMERIC_H2_RE = re.compile(r"^([0-9]+)\.\s*(.+)$")
FENCE_OPEN_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,}).*$")
DIVIDER_CELL_RE = re.compile(r"^:?-{3,}:?$")
LEDGER_HEADER = [
    "Ref",
    "Role / retained use",
    "Publisher / title",
    "Source type",
    "Accessed",
    "Exact URL or local record",
]


def is_substantive(line: str) -> bool:
    text = line.strip()
    if not text:
        return False
    if text.startswith("<!--") and text.endswith("-->"):
        return False
    if re.fullmatch(r"[-*_]{3,}", text):
        return False
    return True


def split_cells(line: str) -> list[str]:
    parts = line.split("|")
    if line.lstrip().startswith("|"):
        parts = parts[1:]
    if line.rstrip().endswith("|"):
        parts = parts[:-1]
    return [part.strip() for part in parts]


def strip_fence_mask(lines: list[str]) -> list[bool]:
    """True when the line is outside a fenced code block."""
    outside = []
    fence = None
    for line in lines:
        match = FENCE_OPEN_RE.match(line)
        if fence is None:
            if match is not None:
                fence = match.group(1)[0]
                outside.append(False)
            else:
                outside.append(True)
        elif match is not None and match.group(1)[0] == fence:
            fence = None
            outside.append(False)
        else:
            outside.append(False)
    return outside


def join_cells(cells: list[str]) -> str:
    return "| " + " | ".join(cells) + " |"


def looks_like_path(record: str) -> bool:
    text = record.strip()
    if not text:
        return False
    if text.startswith(("/", "./", "../", "~/")):
        return True
    return "/" in text and "://" not in text


def repair_identity(lines: list[str], title: str | None) -> tuple[list[str], list[str]]:
    repairs: list[str] = []
    outside = strip_fence_mask(lines)
    substantive = [i for i, line in enumerate(lines) if outside[i] and is_substantive(line)]
    if not substantive:
        return lines, repairs
    status_idx = substantive[0]
    if STATUS_RE.match(lines[status_idx].strip()) is None:
        return lines, repairs
    second_idx = substantive[1] if len(substantive) > 1 else None
    if second_idx is not None and H1_RE.match(lines[second_idx].strip()):
        return lines, repairs

    existing_h1 = next(
        (
            i
            for i, line in enumerate(lines)
            if outside[i] and H1_RE.match(line.strip())
        ),
        None,
    )
    if existing_h1 is not None:
        heading = lines.pop(existing_h1)
        if existing_h1 < status_idx:
            status_idx -= 1
        if not heading.endswith("\n"):
            heading += "\n"
        lines.insert(status_idx + 1, heading)
        repairs.append("moved existing H1 immediately after Status")
        return lines, repairs

    derived = title
    if not derived:
        for i, line in enumerate(lines):
            if not outside[i]:
                continue
            match = H2_RE.match(line.strip())
            if match is None:
                continue
            numbered = NUMERIC_H2_RE.match(match.group(1).strip())
            if numbered is not None:
                derived = numbered.group(2).strip()
                break
    if not derived:
        derived = "Research report"
    lines.insert(status_idx + 1, f"# {derived}\n")
    repairs.append(f"inserted H1 after Status: {derived!r}")
    return lines, repairs


def repair_ledger(lines: list[str]) -> tuple[list[str], list[str]]:
    repairs: list[str] = []
    outside = strip_fence_mask(lines)
    sources_at = None
    for i, line in enumerate(lines):
        if outside[i] and line.strip() == "## Sources":
            sources_at = i
            break
    if sources_at is None:
        return lines, repairs

    end = len(lines)
    for i in range(sources_at + 1, len(lines)):
        if outside[i] and H2_RE.match(line_strip := lines[i].strip()) and line_strip != "## Sources":
            end = i
            break

    header_at = None
    for i in range(sources_at + 1, end):
        if not lines[i].lstrip().startswith("|"):
            continue
        if split_cells(lines[i]) == LEDGER_HEADER:
            header_at = i
            break
    if header_at is None:
        return lines, repairs

    for i in range(header_at + 1, end):
        if not lines[i].lstrip().startswith("|"):
            continue
        cells = split_cells(lines[i])
        if cells == LEDGER_HEADER:
            continue
        if cells and all(DIVIDER_CELL_RE.match(cell) for cell in cells):
            continue
        if len(cells) != 6:
            continue
        ref, role, publisher, stype, accessed, record = cells
        original_role, original_record = role, record
        record_stripped = record.strip()
        lower = record_stripped.lower()
        if lower.startswith("http://") or lower.startswith("https://"):
            # Structure-only repair must not guess or invent route tokens (direct-fetch or search-summary only)
            pass
        elif lower.startswith("local-record:"):
            pass
        elif looks_like_path(record_stripped):
            record = f"local-record: {record_stripped}"
            # Local rows do not require fetch tokens.
        else:
            pass
        if record != original_record:
            lines[i] = join_cells([ref, role, publisher, stype, accessed, record]) + "\n"
            repairs.append(f"{ref} prefixed local-record:")
    return lines, repairs


def repair_text(text: str, title: str | None) -> tuple[str, list[str]]:
    newline = "\n" if text.endswith("\n") else ""
    lines = text.splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines[-1] = lines[-1] + "\n"
    lines, identity_repairs = repair_identity(lines, title)
    lines, ledger_repairs = repair_ledger(lines)
    repaired = "".join(lines)
    if not newline and repaired.endswith("\n"):
        repaired = repaired[:-1]
    return repaired, identity_repairs + ledger_repairs


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="repair-report-structure.py")
    parser.add_argument("report")
    parser.add_argument("--output", required=True)
    parser.add_argument("--title", default=None)
    parser.add_argument("--summary-json", default=None)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    report_path = Path(args.report)
    output_path = Path(args.output)
    try:
        original = report_path.read_text(encoding="utf-8")
        repaired, repairs = repair_text(original, args.title)
        orig_status = next(
            (line for line in original.splitlines() if STATUS_RE.match(line.strip())),
            None,
        )
        new_status = next(
            (line for line in repaired.splitlines() if STATUS_RE.match(line.strip())),
            None,
        )
        if orig_status is not None and orig_status != new_status:
            print("error: refused to change Status", file=sys.stderr)
            return 1
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(repaired, encoding="utf-8")
        summary = {
            "changed": repaired != original,
            "ok": True,
            "output": str(output_path),
            "repairs": repairs,
        }
        payload = json.dumps(summary, ensure_ascii=False, sort_keys=True)
        if args.summary_json:
            Path(args.summary_json).write_text(payload + "\n", encoding="utf-8")
        print(payload)
        return 0
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
