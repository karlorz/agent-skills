#!/usr/bin/env python3
"""Merge the harness-owned contract into ~/.grok/AGENTS.md.

Preserves ALL existing content except the harness marker block (ADR-1,
2026-08-09):

  <!-- grok-build-harness:begin --> ... <!-- grok-build-harness:end -->

  - splice:      file already has the marker block -> keep head, replace the
                 block, keep tail (canonical path; byte-idempotent)
  - migration:   v0.2.0 files have an unmarked `## Subagent contract` block
                 ending at the known `- Full rules:` line -> replace exactly
                 that block with the marked one (ADR-2)
  - insert:      otherwise -> insert the marked contract after the llm-wiki
                 skillwiki marker (or at the top), keeping all existing lines

Usage:
  merge-agents.py <asset AGENTS.md> <existing AGENTS.md> > merged
  merge-agents.py --status <asset AGENTS.md> <existing AGENTS.md>
      prints one of: missing | match | drift | unmarked | absent
"""

import os
import sys

BEGIN = "<!-- grok-build-harness:begin -->"
END = "<!-- grok-build-harness:end -->"
FULL_RULES = "- Full rules: read `~/.grok/agentrules.md`."
SKILLWIKI_BEGIN = "<!-- skillwiki:begin -->"
SKILLWIKI_END = "<!-- skillwiki:end -->"


def contract_lines(path: str) -> list[str]:
    return open(path, encoding="utf-8").read().splitlines()


def splice(dst_lines: list[str], contract: list[str]):
    """Replace the harness block between BEGIN and END; None if not found."""
    try:
        i = dst_lines.index(BEGIN)
    except ValueError:
        return None
    try:
        j = dst_lines.index(END, i)
    except ValueError:
        return None
    return dst_lines[:i] + contract + dst_lines[j + 1 :]


def migrate(dst_lines: list[str], contract: list[str]):
    """Replace an unmarked v0.2.0 contract block with the marked one."""
    for k, line in enumerate(dst_lines):
        if line != "## Subagent contract":
            continue
        for m in range(k, len(dst_lines)):
            if dst_lines[m] == FULL_RULES:
                return dst_lines[:k] + contract + dst_lines[m + 1 :]
        break
    return None


def extract_block(lines: list[str]):
    """Return the inclusive harness marker block, or None."""
    try:
        i = lines.index(BEGIN)
        j = lines.index(END, i)
    except ValueError:
        return None
    return lines[i : j + 1]


def is_unmarked(lines: list[str]) -> bool:
    return any(line == "## Subagent contract" for line in lines) and any(
        line == FULL_RULES for line in lines
    )


def status(asset: str, dst: str) -> str:
    if not os.path.isfile(dst):
        return "missing"
    contract = contract_lines(asset)
    dst_lines = open(dst, encoding="utf-8").read().splitlines()
    live = extract_block(dst_lines)
    if live is not None:
        return "match" if live == contract else "drift"
    if is_unmarked(dst_lines):
        return "unmarked"
    return "absent"


def insert(dst_lines: list[str], contract: list[str]) -> list[str]:
    """Insert the marked contract after the skillwiki marker (or at top)."""
    if dst_lines and dst_lines[0] == SKILLWIKI_BEGIN:
        try:
            e = dst_lines.index(SKILLWIKI_END)
        except ValueError:
            pass
        else:
            head = dst_lines[: e + 1]
            tail = dst_lines[e + 1 :]
            out = head + contract
            if tail and tail[0] != "":
                out = out + [""]
            return out + tail
    return contract + dst_lines


def main() -> int:
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "--status":
        sys.stdout.write(status(args[1], args[2]) + "\n")
        return 0
    if len(args) != 2 or args[0].startswith("-"):
        sys.stderr.write(
            "Usage: merge-agents.py <asset AGENTS.md> <existing AGENTS.md>\n"
            "       merge-agents.py --status <asset AGENTS.md> <existing AGENTS.md>\n"
        )
        return 2
    asset, dst = args
    contract = contract_lines(asset)
    dst_lines = open(dst, encoding="utf-8").read().splitlines()
    merged = splice(dst_lines, contract) or migrate(dst_lines, contract) or insert(
        dst_lines, contract
    )
    sys.stdout.write("\n".join(merged) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
