#!/usr/bin/env python3
"""
test-research-contract.py — static contract test for deep-research-dev entrypoints.

Asserts that the slash skill (SKILL.md) and the direct agent (deep-research-dev.md)
expose the same capability-adaptive execution, answer-critical evidence discipline,
strict Partial-status semantics, and (per the approved presentation/source-ledger
plan) the landed report-presentation contract: the D-owned bundled template,
a complete immutable source ledger, stable [S<n>] mapping with exact
external-URL / local-record rules, interactive-only --reuse-s-template, and
literal audit headings.  No live model, network, Docker, or vault access is
required — this is a pure text-anchor check on the two Markdown entrypoints.

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
    # Strict status rule — Verified/Partial semantics
    "**Status: Verified**",
    "Status is **Partial** if any of:",
)

# Anchors that must appear in the direct agent (deep-research-dev.md).
required_agent = (
    "same selected source plan sequentially inline",
    "not itself a source-plan degradation",
    "must not be omitted after discovery to obtain Verified",
    "**Status: Verified**",
    "Status is **Partial** if any of:",
)

# Additional strict-policy anchors that must remain in the skill text.
required_skill_policy = (
    "every retained claim carries non-empty external verification",
    "unresolved material conflict",
)

# ── Landed presentation-contract anchors (approved plan — acceptance) ───────
#
# These phrases are part of the landed D report-presentation contract and must
# appear in BOTH entrypoints. Their presence is the acceptance evidence that
# the contract content remains in force in both files.

required_landed_contract = (
    # D-owned template reference + default bundled-template behavior.
    "references/report-presentation-template.md",
    "defaults to the bundled template",
    "bundled template",
    # Complete immutable source ledger (not a trimmed top-N list) covering
    # retained evidence and material conflicts/degradations.
    "immutable source ledger",
    "retained evidence",
    "degradations",
    # Stable [S<n>] mapping (markers never renumbered), exact external-URL
    # rule, explicit local-record rule.
    "renumber",
    "exact external URL",
    "local record",
    # Interactive/structure-only --reuse-s-template: safe bundled fallback,
    # cannot carry S facts/sources/conclusions, disabled under --unattended.
    "--reuse-s-template",
    "structure-only",
    "falls back to the bundled template",
    "cannot carry S facts/sources/conclusions",
    "disabled under `--unattended`",
)

# Literal audit headings must remain literal (##-level, unnumbered) in BOTH
# entrypoints. Both entrypoints now emit "## Freshness & Verification Status"
# and "## Coverage and uncertainty" literally; these anchors lock that in.
required_literal_headings = (
    "## Freshness & Verification Status",
    "## Coverage and uncertainty",
)

# The numbered Phase 3 list in BOTH entrypoints must instruct emitting the
# literal audit heading "## Verification Methods" (mirroring the item-5
# wording used for "## Freshness & Verification Status").
required_verification_methods_emission = (
    "emit as a literal `## Verification Methods` heading",
)

# Mode parity: the direct agent's Phase 1 interactive detection must exclude
# --ephemeral exactly like the slash skill's interactive mode row does.
required_agent_mode_parity = (
    "no `--unattended` / `--ephemeral` / smoke flags",
)

# Legacy top-N trimming instruction must stay REMOVED from both entrypoints.
# The old numbered top-N list is gone (the immutable ledger replaced it);
# the absence assertion below locks in that landed state.
legacy_trim_phrase = "Trim sources to top 5-7 most authoritative"


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

    # Landed presentation contract — must be present in both entrypoints.
    for phrase in required_landed_contract:
        for label, text in (("SKILL.md", skill_text), ("agent.md", agent_text)):
            if phrase not in text:
                failures.append(f"{label} missing landed-contract anchor: {phrase!r}")

    for phrase in required_literal_headings:
        for label, text in (("SKILL.md", skill_text), ("agent.md", agent_text)):
            if phrase not in text:
                failures.append(f"{label} missing literal audit heading: {phrase!r}")

    # Numbered Phase 3 item 6 must instruct emitting the literal
    # "## Verification Methods" audit heading in BOTH entrypoints.
    for phrase in required_verification_methods_emission:
        for label, text in (("SKILL.md", skill_text), ("agent.md", agent_text)):
            if phrase not in text:
                failures.append(
                    f"{label} missing Verification Methods literal-heading instruction: {phrase!r}"
                )

    # Mode parity: direct agent interactive detection excludes --ephemeral.
    for phrase in required_agent_mode_parity:
        if phrase not in agent_text:
            failures.append(f"agent.md missing mode-parity phrase: {phrase!r}")

    # Landed acceptance check: legacy top-N trimming must stay gone.
    for label, text in (("SKILL.md", skill_text), ("agent.md", agent_text)):
        if legacy_trim_phrase in text:
            failures.append(
                f"{label} still contains legacy top-N trimming phrase: {legacy_trim_phrase!r}"
            )

    if failures:
        for f in failures:
            print(f"contract FAIL: {f}", file=sys.stderr)
        return 1

    print("research contract: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())