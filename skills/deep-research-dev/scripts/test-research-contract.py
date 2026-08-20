#!/usr/bin/env python3
"""
test-research-contract.py — static contract test for deep-research-dev entrypoints.

Asserts that the slash skill (SKILL.md) and the direct agent (deep-research-dev.md)
expose the same capability-adaptive execution, answer-critical evidence discipline,
strict Partial-status semantics, and (per the approved presentation/source-ledger
plan) the landed report-presentation contract: the D-owned bundled template,
a complete immutable source ledger, stable [S<n>] mapping with exact
external-URL / local-record rules, interactive-only --reuse-s-template,
plain ASCII ordinal narrative H2 headings, and
literal audit headings.  The plugin README and the current CHANGELOG entry
must document that contract consistently (plain ASCII ordinal narrative
H2s, only narrative title text localized, `## 1. Findings` fallback
wording).  No live model, network, Docker, or vault access is required —
this is a pure text-anchor check on the two Markdown entrypoints plus the
two documentation files.

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
_README_MD = _SCRIPTS_DIR / ".." / "README.md"
_CHANGELOG_MD = _SCRIPTS_DIR / ".." / "CHANGELOG.md"
_TEMPLATE_MD = _SCRIPTS_DIR / ".." / "references" / "report-presentation-template.md"
_CODEX_TOOLS_MD = _SCRIPTS_DIR / ".." / "references" / "codex-tools.md"
_SMOKE_SH = _SCRIPTS_DIR / "smoke-ephemeral.sh"


def _read(path: Path) -> str:
    if not path.is_file():
        print(f"contract FAIL: file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


def _normalize_whitespace(text: str) -> str:
    """Compare prose contracts without coupling them to Markdown wrapping."""
    return " ".join(text.split())


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
    # Strict status rule — canonical matrix and labels
    "**Status: Verified**",
    "**Status: Partial**",
)

# Anchors that must appear in the direct agent adapter (deep-research-dev.md).
# The direct agent is a thin host adapter that points to the SKILL.md orchestrator.
required_agent_adapter = (
    "skills/deep-research-dev/SKILL.md",
    "do not invent a shorter",
    "STOP",
)

# Recipe phrases unique to the former twin that must NOT appear in the
# thin host adapter agent.md.
prohibited_agent_recipe = (
    "Phase 1: Topic Analysis (you, inline)",
    "Pass A — Consolidation",
    "Deep Research Complete",
)

# Additional strict-policy anchors that must remain in the skill text.
required_skill_policy = (
    "every retained claim carries non-empty external verification",
    "unresolved material conflict",
)

# A requested, primary-source-supported fact that is not yet decided is useful
# report content rather than a research failure. It must remain distinct from
# evidence gaps. Wording may differ across the concise direct agent, verbose
# slash skill, and reference template, so these are stable semantic phrases.
required_status_semantics = (
    "topic-inherent unknown",
    "require `Partial`",
    "planned question",
    "retained claim",
    "answer-critical claim",
    "source",
    "synthesis",
    "evidence gap",
)

legacy_blanket_uncertainty_rule = "an uncertainty was reported"

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
    # Immutable ledger and stable mapping.
    "immutable",
    "retained evidence",
    "renumber",
    "local record",
    # Interactive/structure-only --reuse-s-template.
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

# Numbered Phase 3 item 6 must instruct emitting the literal
# "## Verification Methods" audit heading in BOTH entrypoints.
required_verification_methods_emission = (
    "## Verification Methods",
)

# Mode parity: both entrypoints must treat --ephemeral as unattended in their
# detection/question gate, not only in a table row.
required_mode_parity = (
    "--unattended` or `--ephemeral",
    "no `--unattended` / `--ephemeral` / headless / smoke flags",
)

# Plain ASCII ordinal narrative H2 headings (approved correction): both
# entrypoints must instruct plain ASCII ordinal narrative H2 prefixes
# (`## 1. <title>`, `## 2. <title>`, ...) in every report language —
# never localized numbering.
required_plain_ordinal_narrative = (
    "plain ASCII ordinal",
    "ordinal",
)

# README documentation alignment (approved correction): the plugin README
# must describe the plain ASCII ordinal narrative H2 contract and must
# distinguish localized narrative title text from non-localized ordinal
# prefixes (the stale "section labels localize" claim is gone).
required_readme_plain_ordinal = (
    "plain\nASCII ordinal",
    "every\nreport language",
    "title text localizes",
    "ordinal prefixes",
)

# README and current CHANGELOG documentation alignment for the status-neutral
# topic-inherent-unknown policy.
required_status_semantics_docs = (
    "topic-inherent unknown",
    "does not by itself require `Partial`",
)

# The released dev plugin must use the packaged Codex marketplace path rather
# than advertise the standalone personal-skills channel as its installation
# mechanism.
required_codex_marketplace_discovery = (
    "root marketplace entry",
    "codex plugin add deep-research-dev@karlorz-agent-skills --json",
)
legacy_codex_personal_skill_discovery = "Discovery on Codex is via `~/.agents/skills/`"

# The next release adds deterministic generated-report validation and durable
# capture-time provenance. Both instruction surfaces must direct output through
# those mechanisms rather than relying on narrative self-reporting.
required_generated_report_contract = (
    "# <localized report title>",
    "Evidence cutoff:",
    "**This report covers**",
    "canonical timeline table",
    "visual-only",
    "direct-fetch",
    "search-summary only",
    "local-record:",
    "retained-without-citation",
    "numeric tool-count claims",
    "capture metadata",
    "lint-report.py",
)

# The linter validates these strings mechanically. In a localized report they
# remain literal English identifiers; surrounding prose may still localize.
required_literal_machine_tokens = (
    "literal English labels",
    "direct-fetch",
    "search-summary only",
    "local-record:",
    "retained-without-citation",
    "Evidence gap",
)

# Report prose cannot narrate tool invocation totals because the linter makes
# capture metadata authoritative. Phase 6 summaries must not reintroduce the
# conflicting count placeholders.
legacy_model_narrated_count_forms = (
    "Web search fallback: <count",
    "Deep-fetch: <count",
)

# The former minimalist fallback contradicted the output shape it was meant to
# protect. A fallback must retain the status/title/audit/ledger structure.
required_fallback_contract = (
    "structurally valid fallback",
    "Status header, H1 title",
    "all four audit headings",
    "explicit evidence-gap Coverage entry",
)

# Daily usage review + structure-only repair (0.1.0-beta.4).
required_usage_review_contract = (
    "second substantive line MUST be the H1",
    "repair-report-structure.py",
    "record-usage.py",
)

# Legacy top-N trimming instruction must stay REMOVED from both entrypoints.
# The old numbered top-N list is gone (the immutable ledger replaced it);
# the absence assertion below locks in that landed state.
legacy_trim_phrase = "Trim sources to top 5-7 most authoritative"


# Caller seam anchors (Task 2): named caller recommendations in SKILL.md.
required_caller_seam = (
    "Prefer /grok-search",
    "If D is invoked anyway",
)

# Usage writer contract (Task 3): smoke-ephemeral.sh must pass required argv
# unconditionally without gating --plugin-version on an if guard.
required_smoke_usage_argv = (
    '--duration-s "$DURATION_S"',
    '--lint-json "$LINT"',
    '--plugin-version "$PLUGIN_VERSION"',
)
prohibited_smoke_usage_guard = 'if [[ -n "${PLUGIN_VERSION:-}" ]]; then'

# ── Changelog helpers ────────────────────────────────────────────────────────

def _current_release_entry(changelog_text: str) -> tuple[str, str]:
    """Return the first versioned changelog entry and its heading.

    The first `## [` heading is the current release regardless of whether it is
    a stable version or an explicit beta prerelease.
    """
    lines = changelog_text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith("## [")), None)
    if start is None:
        return "", ""
    end = next(
        (i for i in range(start + 1, len(lines)) if lines[i].startswith("## [")),
        len(lines),
    )
    return lines[start], "\n".join(lines[start:end])


# ── Test runner ──────────────────────────────────────────────────────────────

def main() -> int:
    skill_text = _read(_SKILL_MD)
    agent_text = _read(_AGENT_MD)

    failures: list[str] = []

    for phrase in required_skill:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing: {phrase!r}")

    for phrase in required_agent_adapter:
        if phrase not in agent_text:
            failures.append(f"agent.md missing adapter anchor: {phrase!r}")

    for phrase in prohibited_agent_recipe:
        if phrase in agent_text:
            failures.append(f"agent.md still contains former twin recipe: {phrase!r}")

    for phrase in required_skill_policy:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing policy: {phrase!r}")

    # Strict Partial semantics must be present in SKILL.md and template.
    for phrase in required_status_semantics:
        if _normalize_whitespace(phrase) not in _normalize_whitespace(skill_text):
            failures.append(f"SKILL.md missing status-semantics anchor: {phrase!r}")

    template_text = _read(_TEMPLATE_MD)
    for phrase in required_status_semantics:
        if _normalize_whitespace(phrase) not in _normalize_whitespace(template_text):
            failures.append(f"report template missing status-semantics anchor: {phrase!r}")
    for phrase in required_generated_report_contract:
        if phrase not in template_text:
            failures.append(f"report template missing generated-report contract: {phrase!r}")
    for phrase in required_fallback_contract:
        if phrase not in template_text:
            failures.append(f"report template missing structured-fallback contract: {phrase!r}")

    # Landed presentation contract — present in SKILL.md.
    for phrase in required_landed_contract:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing landed-contract anchor: {phrase!r}")

    for phrase in required_generated_report_contract:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing generated-report contract: {phrase!r}")

    for phrase in required_literal_machine_tokens:
        for label, text in (("SKILL.md", skill_text), ("report template", template_text)):
            if phrase not in text:
                failures.append(f"{label} missing literal machine-token contract: {phrase!r}")

    for phrase in legacy_model_narrated_count_forms:
        for label, text in (("SKILL.md", skill_text), ("agent.md", agent_text)):
            if phrase in text:
                failures.append(f"{label} still contains model-narrated count form: {phrase!r}")

    for phrase in required_fallback_contract:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing structured-fallback contract: {phrase!r}")

    for phrase in required_usage_review_contract:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing usage-review contract: {phrase!r}")

    for phrase in required_caller_seam:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing caller-seam anchor: {phrase!r}")

    smoke_text = _read(_SMOKE_SH)
    for phrase in required_smoke_usage_argv:
        if phrase not in smoke_text:
            failures.append(f"smoke-ephemeral.sh missing required usage argv anchor: {phrase!r}")
    if prohibited_smoke_usage_guard in smoke_text:
        failures.append(
            f"smoke-ephemeral.sh must not conditionally guard --plugin-version with {prohibited_smoke_usage_guard!r}"
        )

    for phrase in required_literal_headings:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing literal audit heading: {phrase!r}")

    # Numbered Phase 3 item 6 must instruct emitting the literal
    # "## Verification Methods" audit heading in SKILL.md.
    for phrase in required_verification_methods_emission:
        if phrase not in skill_text:
            failures.append(
                f"SKILL.md missing Verification Methods literal-heading instruction: {phrase!r}"
            )

    # Mode parity: slash-skill detection and question gate include --ephemeral.
    for phrase in required_mode_parity:
        if phrase not in skill_text:
            failures.append(f"SKILL.md missing mode-parity phrase: {phrase!r}")

    # Plain ASCII ordinal narrative H2 headings — must be instructed in SKILL.md.
    for phrase in required_plain_ordinal_narrative:
        if phrase not in skill_text:
            failures.append(
                f"SKILL.md missing plain-ordinal narrative anchor: {phrase!r}"
            )

    # README documentation alignment — the plugin README must describe the
    # plain ASCII ordinal narrative H2 contract and distinguish localized
    # narrative title text from non-localized ordinal prefixes.
    readme_text = _read(_README_MD)
    for phrase in required_readme_plain_ordinal:
        if phrase not in readme_text:
            failures.append(f"README.md missing plain-ordinal doc anchor: {phrase!r}")
    for phrase in required_status_semantics_docs:
        if phrase not in readme_text:
            failures.append(f"README.md missing status-semantics doc anchor: {phrase!r}")

    codex_tools_text = _read(_CODEX_TOOLS_MD)
    for phrase in required_codex_marketplace_discovery:
        if phrase not in codex_tools_text:
            failures.append(f"Codex tools reference missing marketplace-discovery anchor: {phrase!r}")
    if legacy_codex_personal_skill_discovery in skill_text:
        failures.append("SKILL.md still advertises the obsolete Codex personal-skills discovery path")

    # CHANGELOG documentation alignment — the current release entry must carry
    # the corrected `## 1. Findings` fallback wording and must not contain the
    # stale exact `## Findings` text. Historical entries are out of scope.
    current_heading, current_entry = _current_release_entry(_read(_CHANGELOG_MD))
    if not current_heading:
        failures.append("CHANGELOG missing a current version entry")
    if "## 1. Findings" not in current_entry:
        failures.append(
            f"CHANGELOG current entry {current_heading or '<missing>'} missing corrected fallback wording: "
            "'## 1. Findings'"
        )
    if "## Findings" in current_entry:
        failures.append(
            f"CHANGELOG current entry {current_heading or '<missing>'} still contains stale exact fallback "
            "wording: '## Findings'"
        )

    for phrase in required_status_semantics_docs:
        if phrase not in current_entry:
            failures.append(
                f"CHANGELOG current entry {current_heading or '<missing>'} missing "
                f"status-semantics anchor: {phrase!r}"
            )

    # Landed acceptance check: legacy top-N trimming and the obsolete blanket
    # uncertainty trigger must stay gone from all instruction surfaces.
    for label, text in (("SKILL.md", skill_text), ("agent.md", agent_text), ("report template", template_text)):
        if legacy_trim_phrase in text:
            failures.append(
                f"{label} still contains legacy top-N trimming phrase: {legacy_trim_phrase!r}"
            )
        if legacy_blanket_uncertainty_rule in text:
            failures.append(
                f"{label} still contains obsolete blanket uncertainty trigger: {legacy_blanket_uncertainty_rule!r}"
            )

    if failures:
        for f in failures:
            print(f"contract FAIL: {f}", file=sys.stderr)
        return 1

    print("research contract: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())