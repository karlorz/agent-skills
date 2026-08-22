#!/usr/bin/env python3
"""lint-report.py — validate a deep-research generated research report.

Validates a report against the deep-research presentation contract:
exact status header, H1 title, sequential ASCII numbered narrative H2s, the
four fixed audit headings once and in order, the exact 6-cell immutable
source ledger, [S<n>] marker resolution, evidence-gap coverage semantics,
external/local source routing rules, the evidence cutoff, and
model-narrated numeric tool counts (counts belong in metadata only).

Interface:
    python3 lint-report.py REPORT.md [--metadata META.json]
        [--artifact-root PATH] [--cutoff YYYY-MM-DD]

Output: exactly one JSON object on stdout ({"ok": bool, "errors": [str],
diagnostics}); nothing on stderr.  Exit 0 = valid, 1 = validation errors,
2 = bad CLI/input.  Checks run in a fixed order, so identical input yields
identical output.  Stdlib only; no network, no Docker; filesystem access is
limited to reading REPORT.md and the optional metadata file.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timedelta

USAGE = (
    "usage: lint-report.py REPORT.md [--metadata META.json] "
    "[--artifact-root PATH] [--cutoff YYYY-MM-DD]"
)

AUDIT_HEADINGS = (
    "Freshness & Verification Status",
    "Verification Methods",
    "Sources",
    "Coverage and uncertainty",
)

LEDGER_HEADER_CELLS = (
    "Ref",
    "Role / retained use",
    "Publisher / title",
    "Source type",
    "Accessed",
    "Exact URL or local record",
)

STATUS_RE = re.compile(r"^\*\*Status: (Verified|Partial)\*\*$")
H1_RE = re.compile(r"^#\s+(.+)$")
H2_RE = re.compile(r"^##\s+(.+)$")
NUMERIC_H2_RE = re.compile(r"^([0-9]+)\.(\s|$)")
REF_RE = re.compile(r"S([0-9]+)")
MARKER_RE = re.compile(r"\[S([0-9]+)\]")
SHA256_RE = re.compile(r"sha256=([0-9a-fA-F]{64})(?![0-9a-fA-F])")
EVIDENCE_GAP_RE = re.compile(
    r"^\s*(?:[-*]\s+)?(?:\*\*)?evidence[- ]gap(?:\*\*)?\s*(?::|—|–|-)",
    re.IGNORECASE,
)
SEARCH_SUMMARY_ONLY_RE = re.compile(r"search-summary[ -]only", re.IGNORECASE)
DIVIDER_CELL_RE = re.compile(r"^:?-{3,}:?$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
FENCE_OPEN_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,}).*$")
TOOL_NAMES = (
    "web_fetch",
    "grok-search",
    "web_search",
    "get_sources",
    "Context7",
    "DeepWiki",
    "deep-fetch",
)

STARTED_HINT = (
    "metadata 'started' must parse as an ISO-8601 UTC timestamp "
    "(e.g. 2026-08-13T10:00:00Z), got: {}"
)


class UsageError(Exception):
    pass


def parse_args(argv):
    value_opts = {"--metadata", "--artifact-root", "--cutoff"}
    positionals = []
    values = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith("-") and arg != "-":
            if arg not in value_opts:
                raise UsageError(f"unknown option {arg!r}")
            if arg in values:
                raise UsageError(f"duplicate option {arg!r}")
            if i + 1 >= len(argv):
                raise UsageError(f"option {arg!r} requires a value")
            values[arg] = argv[i + 1]
            i += 2
        else:
            positionals.append(arg)
            i += 1
    if len(positionals) != 1:
        raise UsageError(f"expected exactly one REPORT.md path, got {len(positionals)}")
    return {
        "report": positionals[0],
        "metadata": values.get("--metadata"),
        "artifact_root": values.get("--artifact-root"),
        "cutoff": values.get("--cutoff"),
    }


def validate_cutoff(value):
    if not DATE_RE.match(value):
        return f"invalid --cutoff date {value!r}: expected YYYY-MM-DD"
    try:
        datetime.strptime(value, "%Y-%m-%d")
    except ValueError:
        return f"invalid --cutoff date {value!r}: not a real calendar date"
    return None


def emit(result):
    sys.stdout.write(json.dumps(result) + "\n")


def strip_leading_yaml_frontmatter(text):
    """Drop a leading closed YAML document so published vault pages lint as reports.

    Only the opening ``---`` / closing ``---`` pair at the start of the file is
    removed. Unclosed frontmatter is left unchanged.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return "\n".join(lines[index + 1 :])
    return text


def is_substantive(line):
    s = line.strip()
    if not s:
        return False
    if s.startswith("<!--") and s.endswith("-->"):
        return False
    if re.fullmatch(r"[-*_]{3,}", s):
        return False
    return True


def split_cells(line):
    parts = line.split("|")
    if line.lstrip().startswith("|"):
        parts = parts[1:]
    if line.rstrip().endswith("|"):
        parts = parts[:-1]
    return [p.strip() for p in parts]


def strip_fenced_code(text):
    """Return report text excluding fenced code blocks for structural checks."""
    kept = []
    fence = None
    for line in text.splitlines():
        match = FENCE_OPEN_RE.match(line)
        if fence is None:
            if match is not None:
                fence = match.group(1)[0]
                kept.append("")
            else:
                kept.append(line)
        elif match is not None and match.group(1)[0] == fence:
            fence = None
            kept.append("")
        else:
            kept.append("")
    return "\n".join(kept)


def local_record_inside_artifact_root(record, artifact_root):
    if not artifact_root:
        return False
    try:
        from pathlib import Path
        root_path = Path(artifact_root).resolve()
        if not root_path.is_dir():
            return False
        rec_path = Path(record.strip())
        if not rec_path.is_absolute():
            rec_path = (root_path / rec_path).resolve()
        else:
            rec_path = rec_path.resolve()
        if not rec_path.is_file():
            return False
        return rec_path.is_relative_to(root_path)
    except (OSError, ValueError, RuntimeError):
        return False


def coverage_has_evidence_gap(coverage_text):
    """True only for a positive, classified Coverage evidence-gap bullet."""
    return any(EVIDENCE_GAP_RE.match(line) is not None for line in coverage_text.splitlines())


def validate_report(text, metadata, args):
    errors = []
    structural_text = strip_fenced_code(strip_leading_yaml_frontmatter(text))
    lines = structural_text.splitlines()

    # -- Status header and H1 -------------------------------------------------
    status = None
    substantive = [ln for ln in lines if is_substantive(ln)]
    if not substantive:
        errors.append("report is empty: no substantive lines")
    else:
        m = STATUS_RE.match(substantive[0].strip())
        if m is None:
            errors.append(
                "first substantive line must be exactly '**Status: Verified**' or "
                f"'**Status: Partial**', got: {substantive[0].strip()!r}"
            )
        else:
            status = m.group(1)
        if len(substantive) < 2:
            errors.append("expected an H1 title ('# <title>') after the status line")
        else:
            if H1_RE.match(substantive[1].strip()) is None:
                errors.append(
                    "expected an H1 title ('# <title>') as the second substantive line, "
                    f"got: {substantive[1].strip()!r}"
                )

    # -- H2 headings: audit set + sequential numbered narratives --------------
    h2s = []  # (line_number, heading)
    for idx, line in enumerate(lines):
        m = H2_RE.match(line.strip())
        if m is not None:
            h2s.append((idx, m.group(1).strip()))

    audit_seen = []
    expected_num = 1
    numbering_broken = False
    coverage_passed = False
    for _, heading in h2s:
        if heading == "Coverage and uncertainty":
            coverage_passed = True
        if coverage_passed and heading not in AUDIT_HEADINGS:
            continue
        if heading in AUDIT_HEADINGS:
            audit_seen.append(heading)
        elif not numbering_broken:
            m = NUMERIC_H2_RE.match(heading)
            if m is None:
                errors.append(f"unnumbered H2 is not an audit heading: '## {heading}'")
                numbering_broken = True
            else:
                num = int(m.group(1))
                if num != expected_num:
                    errors.append(
                        f"numbered H2 '## {heading}' is not sequential: "
                        f"expected '## {expected_num}. ...'"
                    )
                    numbering_broken = True
                else:
                    expected_num += 1

    if audit_seen != list(AUDIT_HEADINGS):
        if len(audit_seen) != len(set(audit_seen)):
            dup = next(h for h in audit_seen if audit_seen.count(h) > 1)
            errors.append(
                "audit headings must occur once in this order: "
                f"{', '.join(AUDIT_HEADINGS)} (duplicate: {dup})"
            )
        else:
            missing = [h for h in AUDIT_HEADINGS if h not in audit_seen]
            if missing:
                errors.append(
                    "audit headings must occur once in this order: "
                    f"{', '.join(AUDIT_HEADINGS)} (missing: {', '.join(missing)})"
                )
            else:
                for want, got in zip(AUDIT_HEADINGS, audit_seen):
                    if want != got:
                        errors.append(
                            "audit headings must occur once in this order: "
                            f"{', '.join(AUDIT_HEADINGS)} "
                            f"(expected '{want}' before '{got}')"
                        )
                        break

    # -- Sources ledger -------------------------------------------------------
    rows = []
    header_found = False
    sources_index = next(
        (i for i, (_, h) in enumerate(h2s) if h == "Sources"), None
    )
    if sources_index is not None:
        start = h2s[sources_index][0] + 1
        end = h2s[sources_index + 1][0] if sources_index + 1 < len(h2s) else len(lines)
        section = lines[start:end]
        for offset, line in enumerate(section):
            if not line.lstrip().startswith("|"):
                continue
            if split_cells(line) == list(LEDGER_HEADER_CELLS):
                header_found = True
                header_at = offset
                break
        if not header_found:
            errors.append(
                "source ledger must have the exact 6-cell header: "
                "| Ref | Role / retained use | Publisher / title | Source type | "
                "Accessed | Exact URL or local record |"
            )
        else:
            refs_seen = set()
            for line in section[header_at + 1:]:
                if not line.lstrip().startswith("|"):
                    continue
                cells = split_cells(line)
                if cells == list(LEDGER_HEADER_CELLS):
                    continue  # repeated header
                if cells and all(DIVIDER_CELL_RE.match(c) for c in cells):
                    continue  # separator row
                if len(cells) != 6:
                    errors.append(
                        f"source ledger row must have exactly 6 cells: {line.strip()!r}"
                    )
                    continue
                if any(c == "" for c in cells):
                    errors.append(
                        f"source ledger row has an empty cell: {line.strip()!r}"
                    )
                    continue
                ref, role, _publisher, _stype, _accessed, url = cells
                rm = REF_RE.fullmatch(ref)
                if rm is None:
                    errors.append(
                        f"ledger row must start with a unique 'S<number>' ref, got: {ref!r}"
                    )
                    continue
                if ref in refs_seen:
                    errors.append(f"duplicate ledger ref {ref}")
                    continue
                refs_seen.add(ref)
                rows.append(
                    {
                        "ref": ref,
                        "number": int(rm.group(1)),
                        "role": role,
                        "url": url,
                    }
                )
            if not rows:
                errors.append("source ledger has no rows")

    # Only count citations outside the immutable ledger itself. A row's own
    # `S<n>` cell and a retained-without-citation explanation are not an
    # in-body citation.
    body_text = structural_text
    if sources_index is not None:
        body_lines = lines[:h2s[sources_index][0]]
        if sources_index + 1 < len(h2s):
            body_lines.extend(lines[h2s[sources_index + 1][0]:])
        body_text = "\n".join(body_lines)
    marker_refs = set("S" + n for n in MARKER_RE.findall(body_text))
    if sources_index is not None and header_found:
        ref_numbers = {row["number"] for row in rows}
        for num in sorted(int(n) for n in MARKER_RE.findall(body_text)):
            if num not in ref_numbers:
                errors.append(f"[S{num}] does not resolve to a ledger row")

    # -- Coverage and uncertainty section --------------------------------------
    coverage_text = None
    cov_index = next(
        (i for i, (_, h) in enumerate(h2s) if h == "Coverage and uncertainty"), None
    )
    if cov_index is not None:
        cstart = h2s[cov_index][0] + 1
        cend = h2s[cov_index + 1][0] if cov_index + 1 < len(h2s) else len(lines)
        coverage_text = "\n".join(lines[cstart:cend])

    if coverage_text is not None and status is not None:
        has_evidence_gap = coverage_has_evidence_gap(coverage_text)
        if status == "Partial" and not has_evidence_gap:
            errors.append(
                "Partial status requires an evidence-gap phrase in Coverage and uncertainty"
            )
        elif status == "Verified" and has_evidence_gap:
            errors.append(
                "Verified status cannot retain an evidence-gap phrase in Coverage and uncertainty"
            )

    # -- Per-row ledger rules ---------------------------------------------------
    for row in rows:
        if row["ref"] not in marker_refs and "retained-without-citation" not in row["role"].lower():
            errors.append(f"ledger row {row['ref']} is not cited")
        url = row["url"].strip()
        url_low = url.lower()
        role_low = row["role"].lower()
        if url_low.startswith("http://") or url_low.startswith("https://"):
            has_direct_fetch = "direct-fetch" in role_low
            has_search_summary_only = SEARCH_SUMMARY_ONLY_RE.search(role_low) is not None
            if not has_direct_fetch and not has_search_summary_only:
                errors.append(
                    f"external source {row['ref']} role must contain 'direct-fetch' or "
                    f"'search-summary only': {row['role']!r}"
                )
            if has_search_summary_only and coverage_text is not None:
                if (
                    re.search(rf"\b{row['ref']}\b", coverage_text) is None
                    or SEARCH_SUMMARY_ONLY_RE.search(coverage_text) is None
                ):
                    errors.append(
                        f"search-summary only source {row['ref']} must be disclosed in "
                        "Coverage and uncertainty with 'search-summary only'"
                    )
        elif url_low.startswith("local-record:"):
            record = url[len("local-record:"):].strip()
            if not record:
                errors.append(f"local record {row['ref']} has no path")
            elif SHA256_RE.search(record) is None:
                if not local_record_inside_artifact_root(record, args["artifact_root"]):
                    if "sha256=" in record:
                        errors.append(
                            f"local record {row['ref']} has a malformed sha256= hash "
                            "(expected exactly 64 hex characters)"
                        )
                    else:
                        errors.append(
                            f"local record {row['ref']} is outside the artifact root or does not exist as a regular file "
                            f"without sha256 (expected a 'sha256=' + 64-hex hash): {url!r}"
                        )
        else:
            errors.append(
                f"source {row['ref']} record must be an http(s):// URL or start with "
                f"'local-record:': {url!r}"
            )

    # -- Evidence cutoff --------------------------------------------------------
    if args["cutoff"] is not None:
        cutoff = args["cutoff"]
        if f"Evidence cutoff: {cutoff}" not in text:
            errors.append(
                f"evidence cutoff must equal {cutoff}: "
                f"report must state 'Evidence cutoff: {cutoff}'"
            )
        started = metadata.get("started")
        if started is not None:
            if not isinstance(started, str):
                errors.append(
                    "metadata 'started' must parse as an ISO-8601 UTC timestamp "
                    f"(e.g. 2026-08-13T10:00:00Z), got non-string: {started!r}"
                )
            else:
                s = started.strip()
                if s.endswith(("Z", "z")):
                    s = s[:-1] + "+00:00"
                try:
                    started_dt = datetime.fromisoformat(s)
                except ValueError:
                    errors.append(STARTED_HINT.format(repr(started)))
                else:
                    offset = started_dt.utcoffset()
                    if offset is None or offset != timedelta(0):
                        errors.append(STARTED_HINT.format(repr(started)))
                    else:
                        cutoff_date = datetime.strptime(cutoff, "%Y-%m-%d").date()
                        if cutoff_date > started_dt.date():
                            errors.append(
                                f"evidence cutoff {cutoff} cannot be after metadata "
                                f"start date {started_dt.date().isoformat()}"
                            )

    # -- Model-narrated numeric tool counts --------------------------------------
    for name in TOOL_NAMES:
        pattern = re.compile(
            r"\b" + re.escape(name) + r"\s*(?:×|x|:)\s*([0-9]+)", re.IGNORECASE
        )
        m = pattern.search(structural_text)
        if m is not None:
            errors.append(
                f"numeric tool-count claim in report text: {m.group(0).strip()!r} "
                "(counts belong in metadata, not in the report)"
            )

    diagnostics = {
        "status": status,
        "ledger_rows": len(rows),
        "body_markers": len(marker_refs),
        "cited_rows": sum(1 for row in rows if row["ref"] in marker_refs),
    }
    return errors, diagnostics


def main():
    try:
        args = parse_args(sys.argv[1:])
    except UsageError as exc:
        emit({"ok": False, "errors": [str(exc), USAGE]})
        return 2

    try:
        with open(args["report"], "r", encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        emit({"ok": False, "errors": [f"cannot read report file {args['report']!r}: {exc}"]})
        return 2

    metadata = {}
    if args["metadata"] is not None:
        try:
            with open(args["metadata"], "r", encoding="utf-8") as fh:
                metadata = json.load(fh)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            emit(
                {
                    "ok": False,
                    "errors": [f"cannot read metadata file {args['metadata']!r}: {exc}"],
                }
            )
            return 2
        if not isinstance(metadata, dict):
            emit(
                {
                    "ok": False,
                    "errors": [
                        f"metadata file {args['metadata']!r} must contain a JSON object"
                    ],
                }
            )
            return 2

    if args["cutoff"] is not None:
        bad = validate_cutoff(args["cutoff"])
        if bad is not None:
            emit({"ok": False, "errors": [bad]})
            return 2

    errors, diagnostics = validate_report(text, metadata, args)
    emit({"ok": not errors, "errors": errors, **diagnostics})
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
