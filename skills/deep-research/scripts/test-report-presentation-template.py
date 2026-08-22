#!/usr/bin/env python3
"""
test-report-presentation-template.py — static contract test for the
S-owned report-presentation template.

Asserts that `references/report-presentation-template.md` (owned by
deep-research) carries the full approved presentation/source-ledger
contract: a language-adaptive numbered topical narrative with plain ASCII
ordinal H2 headings and no filler sections, literal unnumbered audit
headings, the `## Sources` ledger table
whose header row is exactly the six contract fields in order (duplicates,
omissions, reordering, and extra columns rejected), exact external-URL /
explicit local-record / stable [S<n>] / immutability (no refiner trimming) /
material-conflict rules.

Asserts D-only exclusions:
- No --reuse-s-template
- No deep-research-dev or D-lane terminology
- Standalone S-owned template

Run:
    python3 skills/deep-research/scripts/test-report-presentation-template.py

Exit 0 + "report presentation template: ok"  →  all anchors present.
Exit 1 + missing-anchor name                  →  RED — template or anchor absent.
"""

import sys
from pathlib import Path

# ── File location (relative to this script's directory) ─────────────────────

_SCRIPTS_DIR = Path(__file__).resolve().parent
_TEMPLATE = _SCRIPTS_DIR / ".." / "references" / "report-presentation-template.md"


def _read(path: Path) -> str:
    if not path.is_file():
        print(
            f"template FAIL: template file not found: {path.resolve()}",
            file=sys.stderr,
        )
        sys.exit(1)
    return path.read_text(encoding="utf-8")


# ── Required anchors ────────────────────────────────────────────────────────

# Language-adaptive numbered topical narrative; no filler sections.
required_narrative = (
    "language-adaptive",
    "numbered topical narrative",
    "no filler sections",
)

# Plain ASCII ordinal narrative H2 headings: every
# narrative section heading must use a plain ASCII ordinal prefix (`1.`,
# `2.`, `3.`, ...) in every report language — never localized numbering.
required_plain_ordinal_narrative = (
    "plain ASCII ordinal",
    "## 1. Decision summary",
    "the only unnumbered H2",
    "every report language",
)

# Literal unnumbered audit headings plus the Sources ledger heading
required_headings = (
    "## Freshness & Verification Status",
    "## Verification Methods",
    "## Coverage and uncertainty",
    "## Sources",
)

# Sources ledger table header — the field set must be exactly these six.
LEDGER_FIELDS = (
    "Ref",
    "Role / retained use",
    "Publisher / title",
    "Source type",
    "Accessed",
    "Exact URL or local record",
)

# Ledger rules: exact external URL, explicit local record, stable citation
# marker, immutability (no refiner trimming), material conflicts retained.
required_ledger_rules = (
    "exact external URL",
    "local record",
    "[S<n>]",
    "renumber",
    "must not be trimmed",
    "immutable",
    "material conflict",
)

# Generated reports identity and readability rules
required_identity_and_readability = (
    "# <localized report title>",
    "Evidence cutoff:",
    "**This report covers**",
    "canonical timeline table",
    "visual-only",
    "TL;DR",
    "explains facts once",
    "Coverage contains only",
)

# Source-access and local-record disclosure
required_source_disclosure = (
    "direct-fetch",
    "search-summary only",
    "local-record:",
    "retained-without-citation",
    "sha256=",
    "capture metadata",
    "numeric tool-count claims",
    "lint-report.py",
)

required_structured_fallback = (
    "structurally valid fallback",
    "Status header, H1 title",
    "all four audit headings",
    "explicit evidence-gap Coverage entry",
)

# Prohibited D-only features
prohibited_d_features = (
    "--reuse-s-template",
    "deep-research-dev",
    "skills/deep-research-dev",
    "record-usage",
    "review-usage",
)


def _is_separator_row(line: str) -> bool:
    """True for markdown table separator rows such as `| --- | :---: |`."""
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    cells = [cell for cell in cells if cell]
    if not cells:
        return False
    return all(
        "-" in cell and cell.strip(":").lstrip("-").rstrip("-").strip() == ""
        for cell in cells
    )


def _check_ledger_fields(text: str, failures: list[str]) -> None:
    lines = text.splitlines()

    sources_index = None
    for index, line in enumerate(lines):
        if line.strip() == "## Sources":
            sources_index = index
            break
    if sources_index is None:
        failures.append("missing `## Sources` section heading")
        return

    header = None
    for line in lines[sources_index + 1:]:
        stripped = line.strip()
        if not stripped.startswith("|") or _is_separator_row(stripped):
            continue
        header = stripped
        break

    if header is None:
        failures.append(
            "missing ledger header row inside `## Sources` "
            "(expected `| Ref | Role / retained use | Publisher / title | "
            "Source type | Accessed | Exact URL or local record |`)"
        )
        return

    cells = [cell.strip().strip("*") for cell in header.strip("|").split("|")]
    cells = [cell for cell in cells if cell]

    if cells != list(LEDGER_FIELDS):
        failures.append(
            "ledger header cells must be exactly, in order: "
            + ", ".join(LEDGER_FIELDS)
            + f" | got: {cells}"
        )


def main() -> int:
    text = _read(_TEMPLATE)

    failures: list[str] = []

    for phrase in required_narrative:
        if phrase not in text:
            failures.append(f"template missing narrative anchor: {phrase!r}")

    for phrase in required_plain_ordinal_narrative:
        if phrase not in text:
            failures.append(
                f"template missing plain-ordinal narrative anchor: {phrase!r}"
            )

    for phrase in required_headings:
        if phrase not in text:
            failures.append(f"template missing heading: {phrase!r}")

    _check_ledger_fields(text, failures)

    for phrase in required_ledger_rules:
        if phrase not in text:
            failures.append(f"template missing ledger rule: {phrase!r}")

    for phrase in required_identity_and_readability:
        if phrase not in text:
            failures.append(f"template missing identity/readability rule: {phrase!r}")

    for phrase in required_source_disclosure:
        if phrase not in text:
            failures.append(f"template missing source-disclosure rule: {phrase!r}")

    for phrase in required_structured_fallback:
        if phrase not in text:
            failures.append(f"template missing structured-fallback rule: {phrase!r}")

    for phrase in prohibited_d_features:
        if phrase in text:
            failures.append(f"template contains prohibited D-only feature: {phrase!r}")

    if failures:
        for f in failures:
            print(f"template FAIL: {f}", file=sys.stderr)
        return 1

    print("report presentation template: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
