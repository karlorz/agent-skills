#!/usr/bin/env python3
"""
test-research-contract.py — static contract test for deep-research-dev entrypoints.

Asserts that the slash skill (SKILL.md) and the direct agent (deep-research-dev.md)
expose the same capability-adaptive execution, answer-critical evidence discipline,
and strict Partial-status semantics.  No live model, network, Docker, or vault
access is required — this is a pure text-anchor check on the two Markdown
entrypoints.

Run:
    python3 skills/deep-research-dev/scripts/test-research-contract.py

Exit 0 + "research contract: ok"  →  all anchors present.
Exit 1 + missing-anchor name      →  RED — one or more anchors absent.
"""

import sys
from pathlib import Path

# ── File locations (relative to this script's directory) ────────────────────

_SCRIPTS_DIR = Path(__file__).resolve().parent
_SKILL_MD = _SCRIPTS_DIR / ".." / "skills" / "deep-research-dev" / "SKILL.md"
_AGENT_MD = _SCRIPTS_DIR / ".." / "agents" / "deep-research-dev.md"


def _read(path: Path) -> str:
    if not path.is_file():
        print(f"contract FAIL: file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


# ── Required anchors ─────────────────────────────────────────────────────────

# Anchors that must appear in the slash skill (SKILL.md).
required_skill = (
    # Capability-adaptive execution section
    "## Capability-adaptive execution",
    "same selected source plan sequentially inline",
    "not itself a source-plan degradation",
    # Answer-critical evidence discipline section
    "## Answer-critical evidence discipline",
    "before gathering evidence",
    "must not be omitted after discovery to obtain Verified",
    # Output template — exact audit heading
    "## Freshness & Verification Status",
    # Strict status rule
    "Status is **Partial** if any of:",
)

# Anchors that must appear in the direct agent (deep-research-dev.md).
required_agent = (
    "same selected source plan sequentially inline",
    "not itself a source-plan degradation",
    "must not be omitted after discovery to obtain Verified",
    "Status is **Partial** if any of:",
)

# Additional strict-policy anchors that must remain in the skill text.
required_skill_policy = (
    "every retained claim carries non-empty external verification",
    "unresolved material conflict",
)


# ── Test runner ──────────────────────────────────────────────────────────────

def main() -> int:
    skill_text = _read(_SKILL_MD)
    agent_text = _read(_AGENT_MD)

    failures: list[str] = []

    for phrase in required_skill:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing: {phrase!r}")

    for phrase in required_agent:
        if phrase not in agent_text:
            failures.append(f"agent.md missing: {phrase!r}")

    for phrase in required_skill_policy:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing policy: {phrase!r}")

    # Strict Partial semantics must be present in BOTH entrypoints.
    for label, text in (("SKILL.md", skill_text), ("agent.md", agent_text)):
        if "every retained claim carries non-empty external verification" not in text:
            failures.append(
                f"{label} missing: 'every retained claim carries non-empty external verification'"
            )

    if failures:
        for f in failures:
            print(f"contract FAIL: {f}", file=sys.stderr)
        return 1

    print("research contract: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())