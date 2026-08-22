#!/usr/bin/env python3
"""Regression suite for the deep-research generated-report linter.

The linter must validate report output itself rather than merely the written
skill instructions. All fixtures are local and deterministic.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
LINTER = SCRIPTS / "lint-report.py"

LEDGER_HEADER = (
    "| Ref | Role / retained use | Publisher / title | Source type | Accessed | "
    "Exact URL or local record |"
)
LEDGER_DIVIDER = "| --- | --- | --- | --- | --- | --- |"


def report(
    *,
    status: str = "Verified",
    title: bool = True,
    extra_h2: str = "",
    audit_order: tuple[str, ...] = (
        "Freshness & Verification Status",
        "Verification Methods",
        "Sources",
        "Coverage and uncertainty",
    ),
    sources: str | None = None,
    coverage: str = "- **Topic-inherent unknown:** final adoption remains undecided in retained primary evidence.",
    source_marker: str = "[S1]",
    cutoff: str = "2026-08-12",
    include_tool_count: bool = False,
) -> str:
    title_block = "# HSTECH consultation report\n\n" if title else ""
    source_rows = sources or (
        "| S1 | direct-fetch; retained official evidence | Publisher / official notice | primary | "
        "2026-08-13 | https://example.test/official |"
    )
    sections = {
        "Freshness & Verification Status": (
            "## Freshness & Verification Status\n\n"
            "| Claim | Status | Source route | Notes |\n"
            "| --- | --- | --- | --- |\n"
            f"| Consultation remains open | externally verified | direct-fetch → primary | {source_marker} |\n"
        ),
        "Verification Methods": (
            "## Verification Methods\n\n"
            "Open the cited official notice and compare its publication date.\n"
        ),
        "Sources": (
            "## Sources\n\n"
            f"{LEDGER_HEADER}\n{LEDGER_DIVIDER}\n{source_rows}\n"
        ),
        "Coverage and uncertainty": f"## Coverage and uncertainty\n\n{coverage}\n",
    }
    tool_line = "\nThe research used web_fetch ×5.\n" if include_tool_count else ""
    return (
        f"**Status: {status}**\n\n"
        f"{title_block}"
        f"> Evidence cutoff: {cutoff} · Verification date: 2026-08-13 · Scope: official methodology\n\n"
        "**This report covers**\n1. Proposal\n2. Timeline\n3. Undecided items\n\n"
        "## 1. Decision summary\n\n"
        f"The proposal remains under consultation {source_marker}.\n"
        f"{tool_line}"
        "## 2. Official timeline\n\n"
        "| Milestone | Date |\n| --- | --- |\n| Consultation deadline | 2026-09-18 |\n\n"
        f"{extra_h2}"
        + "\n".join(sections[name] for name in audit_order)
    )


def invoke(path: Path, *args: str) -> dict[str, object]:
    completed = subprocess.run(
        [sys.executable, str(LINTER), str(path), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(
            f"linter did not emit JSON (exit {completed.returncode}): {completed.stderr!r}"
        ) from exc
    result["_returncode"] = completed.returncode
    return result


def assert_valid(path: Path, *args: str) -> None:
    result = invoke(path, *args)
    assert result["ok"] is True, result
    assert result["_returncode"] == 0, result


def assert_invalid(path: Path, expected: str, *args: str) -> None:
    result = invoke(path, *args)
    assert result["ok"] is False, result
    assert result["_returncode"] == 1, result
    errors = "\n".join(result["errors"])
    assert expected in errors, errors


def main() -> int:
    if not LINTER.is_file():
        print(f"RED: report linter is missing: {LINTER}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="test-lint-report-") as temp:
        root = Path(temp)
        valid = root / "valid.md"
        valid.write_text(report(), encoding="utf-8")
        metadata = root / "meta.json"
        metadata.write_text(
            json.dumps({"started": "2026-08-13T10:00:00Z", "tool_counts": {"web_fetch": 5}}),
            encoding="utf-8",
        )
        assert_valid(valid, "--metadata", str(metadata), "--cutoff", "2026-08-12")

        fenced_content = root / "fenced-content.md"
        fenced_content.write_text(
            report().replace(
                "Open the cited official notice and compare its publication date.",
                "Open the cited official notice and compare its publication date.\n\n"
                "```markdown\n"
                "## Example heading, not report structure\n"
                "[S99]\n"
                "web_fetch ×5\n"
                "```",
            ),
            encoding="utf-8",
        )
        assert_valid(fenced_content, "--metadata", str(metadata), "--cutoff", "2026-08-12")

        missing_title = root / "missing-title.md"
        missing_title.write_text(report(title=False), encoding="utf-8")
        assert_invalid(missing_title, "expected an H1 title")

        bad_headings = root / "bad-headings.md"
        bad_headings.write_text(report(extra_h2="## Analysis\n\nDuplicated explanation.\n"), encoding="utf-8")
        assert_invalid(bad_headings, "unnumbered H2 is not an audit heading")

        wrong_audit_order = root / "wrong-audit-order.md"
        wrong_audit_order.write_text(
            report(
                audit_order=(
                    "Verification Methods",
                    "Freshness & Verification Status",
                    "Sources",
                    "Coverage and uncertainty",
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(wrong_audit_order, "audit headings must occur once in this order")

        unknown_marker = root / "unknown-marker.md"
        unknown_marker.write_text(report(source_marker="[S2]"), encoding="utf-8")
        assert_invalid(unknown_marker, "[S2] does not resolve")

        uncited = root / "uncited.md"
        uncited.write_text(
            report(
                source_marker="",
                sources=(
                    "| S1 | direct-fetch; retained official evidence | Publisher / official notice | primary | 2026-08-13 | https://example.test/official |\n"
                    "| S2 | direct-fetch; retained secondary evidence | Publisher / follow-up | secondary | 2026-08-13 | https://example.test/follow-up |"
                ),
            ),
            encoding="utf-8",
        )
        assert_invalid(uncited, "ledger row S1 is not cited")

        retained = root / "retained.md"
        retained.write_text(
            report(
                sources=(
                    "| S1 | direct-fetch; retained official evidence | Publisher / official notice | primary | 2026-08-13 | https://example.test/official |\n"
                    "| S2 | direct-fetch; retained-without-citation: corroborative context | Publisher / follow-up | secondary | 2026-08-13 | https://example.test/follow-up |"
                )
            ),
            encoding="utf-8",
        )
        assert_valid(retained)

        partial_without_gap = root / "partial-without-gap.md"
        partial_without_gap.write_text(report(status="Partial"), encoding="utf-8")
        assert_invalid(partial_without_gap, "Partial status requires an evidence-gap")

        partial_with_documented_gap = root / "partial-with-documented-gap.md"
        partial_with_documented_gap.write_text(
            report(
                status="Partial",
                coverage=(
                    "- **Evidence gap** — required official notice was unavailable."
                ),
            ),
            encoding="utf-8",
        )
        assert_valid(partial_with_documented_gap)

        verified_with_gap = root / "verified-with-gap.md"
        verified_with_gap.write_text(
            report(coverage="- **Evidence gap:** answer-critical official notice was unavailable."),
            encoding="utf-8",
        )
        assert_invalid(verified_with_gap, "Verified status cannot retain an evidence-gap")

        verified_without_gaps = root / "verified-without-gaps.md"
        verified_without_gaps.write_text(
            report(
                coverage=(
                    "- **Topic-inherent unknown:** final adoption remains undecided in retained primary evidence.\n"
                    "- No evidence gaps remain."
                )
            ),
            encoding="utf-8",
        )
        assert_valid(verified_without_gaps)

        search_summary = root / "search-summary.md"
        search_summary.write_text(
            report(
                sources=(
                    "| S1 | search-summary only; retained media headline | Publisher / headline | secondary | 2026-08-13 | https://example.test/headline |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(search_summary, "search-summary only source S1")

        disclosed_search_summary = root / "disclosed-search-summary.md"
        disclosed_search_summary.write_text(
            report(
                sources=(
                    "| S1 | search-summary only; retained media headline | Publisher / headline | secondary | 2026-08-13 | https://example.test/headline |"
                ),
                coverage=(
                    "- **Topic-inherent unknown:** final adoption remains undecided in retained primary evidence.\n"
                    "- **Source disclosure:** S1 is search-summary only and was not directly fetched."
                ),
            ),
            encoding="utf-8",
        )
        assert_valid(disclosed_search_summary)

        # Ledger cell validations: Source type and Accessed date
        invalid_source_type = root / "invalid-source-type.md"
        invalid_source_type.write_text(
            report(
                sources=(
                    "| S1 | direct-fetch; retained official evidence | Publisher / official notice | invalid_type | 2026-08-13 | https://example.test/official |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(invalid_source_type, "source type must be one of")

        malformed_accessed = root / "malformed-accessed.md"
        malformed_accessed.write_text(
            report(
                sources=(
                    "| S1 | direct-fetch; retained official evidence | Publisher / official notice | primary | 2026/08/13 | https://example.test/official |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(malformed_accessed, "accessed date")

        impossible_accessed = root / "impossible-accessed.md"
        impossible_accessed.write_text(
            report(
                sources=(
                    "| S1 | direct-fetch; retained official evidence | Publisher / official notice | primary | 2026-02-30 | https://example.test/official |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(impossible_accessed, "accessed date")

        # Valid positive source types
        for valid_stype in ("primary", "secondary", "repository", "other"):
            stype_md = root / f"valid-stype-{valid_stype}.md"
            stype_md.write_text(
                report(
                    sources=(
                        f"| S1 | direct-fetch; retained evidence | Publisher | {valid_stype} | 2026-08-13 | https://example.test/official |"
                    )
                ),
                encoding="utf-8",
            )
            assert_valid(stype_md)

        volatile_local = root / "volatile-local.md"
        volatile_local.write_text(
            report(
                sources=(
                    "| S1 | local-record: parsed spreadsheet | Publisher / schedule | primary | 2026-08-13 | local-record: /tmp/schedule.xlsx |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(volatile_local, "outside the artifact root")

        hashed_local = root / "hashed-local.md"
        hashed_local.write_text(
            report(
                sources=(
                    "| S1 | local-record: parsed spreadsheet | Publisher / schedule | primary | 2026-08-13 | local-record: /tmp/schedule.xlsx sha256="
                    + "a" * 64
                    + " |"
                )
            ),
            encoding="utf-8",
        )
        assert_valid(hashed_local, "--artifact-root", str(root))

        artifact_local = root / "artifact-local.md"
        artifact_local.write_text(
            report(
                sources=(
                    "| S1 | local-record: captured spreadsheet | Publisher / schedule | primary | 2026-08-13 | local-record: evidence/schedule.xlsx |"
                )
            ),
            encoding="utf-8",
        )
        valid_evidence = root / "evidence" / "schedule.xlsx"
        valid_evidence.parent.mkdir(parents=True, exist_ok=True)
        valid_evidence.write_text("dummy xlsx data", encoding="utf-8")
        assert_valid(artifact_local, "--artifact-root", str(root))

        # Durable unhashed local records test cases
        nonexistent_local = root / "nonexistent-local.md"
        nonexistent_local.write_text(
            report(
                sources=(
                    "| S1 | local-record: captured spreadsheet | Publisher / schedule | primary | 2026-08-13 | local-record: evidence/nonexistent.xlsx |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(nonexistent_local, "outside the artifact root or does not exist as a regular file", "--artifact-root", str(root))

        evidence_dir = root / "evidence_dir"
        evidence_dir.mkdir(parents=True, exist_ok=True)
        dir_local = root / "dir-local.md"
        dir_local.write_text(
            report(
                sources=(
                    "| S1 | local-record: captured directory | Publisher / schedule | primary | 2026-08-13 | local-record: evidence_dir |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(dir_local, "outside the artifact root or does not exist as a regular file", "--artifact-root", str(root))

        outside_file = root.parent / "outside_secret.txt"
        outside_file.write_text("secret", encoding="utf-8")
        escape_symlink = root / "escape_link.txt"
        if not escape_symlink.exists():
            escape_symlink.symlink_to(outside_file)
        escape_local = root / "escape-local.md"
        escape_local.write_text(
            report(
                sources=(
                    "| S1 | local-record: symlink escape | Publisher / schedule | primary | 2026-08-13 | local-record: escape_link.txt |"
                )
            ),
            encoding="utf-8",
        )
        assert_invalid(escape_local, "outside the artifact root", "--artifact-root", str(root))

        assert_valid(artifact_local, "--artifact-root", str(root))
        assert_invalid(artifact_local, "outside the artifact root", "--artifact-root", str(root / "nonexistent_root_dir"))
        assert_valid(hashed_local, "--artifact-root", str(root))

        mismatched_cutoff = root / "mismatched-cutoff.md"
        mismatched_cutoff.write_text(report(cutoff="2026-08-13"), encoding="utf-8")
        assert_invalid(mismatched_cutoff, "evidence cutoff must equal 2026-08-12", "--cutoff", "2026-08-12")

        narrated_count = root / "narrated-count.md"
        narrated_count.write_text(report(include_tool_count=True), encoding="utf-8")
        assert_invalid(narrated_count, "numeric tool-count claim")

        wrapped = root / "vault-wrapped.md"
        wrapped.write_text(
            "---\n"
            'title: "Published query"\n'
            "created: 2026-08-20\n"
            "type: query\n"
            "---\n\n"
            + report()
            + "\n## Related Notes\n\n- [[queries/example]]\n",
            encoding="utf-8",
        )
        assert_valid(wrapped, "--metadata", str(metadata), "--cutoff", "2026-08-12")

        yaml_only = root / "yaml-only.md"
        yaml_only.write_text("---\ntitle: no report\n---\n\nJust prose.\n", encoding="utf-8")
        assert_invalid(yaml_only, "first substantive line must be exactly")

        related_mid = root / "related-mid.md"
        related_mid.write_text(
            report(extra_h2="## Related Notes\n\n- [[queries/example]]\n"),
            encoding="utf-8",
        )
        assert_invalid(related_mid, "unnumbered H2 is not an audit heading")

    print("report lint: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
