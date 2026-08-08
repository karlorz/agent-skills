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

Usage: merge-agents.py <asset AGENTS.md> <existing AGENTS.md> > merged
"""

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
    asset, dst = sys.argv[1], sys.argv[2]
    contract = contract_lines(asset)
    dst_lines = open(dst, encoding="utf-8").read().splitlines()
    merged = splice(dst_lines, contract) or migrate(dst_lines, contract) or insert(
        dst_lines, contract
    )
    sys.stdout.write("\n".join(merged) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
