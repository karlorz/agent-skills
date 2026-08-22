#!/usr/bin/env python3
"""select-report-candidate.py — deterministic candidate report selector.

Selects the best valid report candidate among:
1. Normal candidate (if lint-clean) -> selected: "normal"
2. Structure-only repaired candidate (if repairable & clean) -> selected: "repaired"
3. Prebuilt fallback checkpoint (if clean) -> selected: "fallback"

If candidate and fallback are both invalid/missing, exits nonzero and writes
diagnostics without silently treating invalid output as contract-clean.

Interface:
    python3 select-report-candidate.py \
      --candidate CANDIDATE.md \
      --fallback FALLBACK.md \
      --output OUTPUT.md \
      --lint-json LINT.json \
      --selection-json SELECTION.json \
      [--metadata META.json] [--artifact-root DIR] [--cutoff YYYY-MM-DD]

Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
LINTER = SCRIPTS_DIR / "lint-report.py"
REPAIRER = SCRIPTS_DIR / "repair-report-structure.py"

REPAIRABLE_PATTERNS = [
    r"expected an H1 title",
    r"first substantive line must be",
    r"must be an http\(s\):// URL or start with 'local-record:'",
    r"local record .* has no path",
]


def invoke_lint(
    report_path: Path,
    metadata_path: Path | None = None,
    artifact_root: Path | None = None,
    cutoff: str | None = None,
) -> dict:
    if not report_path.is_file():
        return {
            "ok": False,
            "errors": [f"file not found: {report_path}"],
            "_returncode": 2,
        }
    cmd = [sys.executable, str(LINTER), str(report_path)]
    if metadata_path and metadata_path.is_file():
        cmd.extend(["--metadata", str(metadata_path)])
    if artifact_root:
        cmd.extend(["--artifact-root", str(artifact_root)])
    if cutoff:
        cmd.extend(["--cutoff", cutoff])

    completed = subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    try:
        data = json.loads(completed.stdout)
    except Exception:
        data = {
            "ok": False,
            "errors": [f"linter error (exit {completed.returncode}): {completed.stderr.strip()}"],
        }
    data["_returncode"] = completed.returncode
    return data


def is_repairable(errors: list[str]) -> bool:
    if not errors:
        return False
    return any(any(re.search(p, err) for p in REPAIRABLE_PATTERNS) for err in errors)


def invoke_repair(src: Path, dest: Path) -> dict:
    cmd = [sys.executable, str(REPAIRER), str(src), "--output", str(dest)]
    completed = subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    try:
        data = json.loads(completed.stdout)
    except Exception:
        data = {
            "ok": False,
            "error": completed.stderr.strip(),
        }
    data["_returncode"] = completed.returncode
    return data


def atomic_write(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    temp_dest = dest.with_suffix(dest.suffix + ".tmp")
    shutil.copy2(src, temp_dest)
    temp_dest.replace(dest)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="select-report-candidate.py")
    parser.add_argument("--candidate", required=True, help="Path to raw candidate report")
    parser.add_argument("--fallback", required=True, help="Path to prebuilt fallback report")
    parser.add_argument("--output", required=True, help="Path to final output report")
    parser.add_argument("--lint-json", required=True, help="Path to output lint.json")
    parser.add_argument("--selection-json", required=True, help="Path to output selection.json")
    parser.add_argument("--metadata", default=None, help="Optional path to run metadata.json")
    parser.add_argument("--artifact-root", default=None, help="Optional artifact root directory")
    parser.add_argument("--cutoff", default=None, help="Optional evidence cutoff YYYY-MM-DD")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    candidate_path = Path(args.candidate)
    fallback_path = Path(args.fallback)
    output_path = Path(args.output)
    lint_json_path = Path(args.lint_json)
    selection_json_path = Path(args.selection_json)
    metadata_path = Path(args.metadata) if args.metadata else None
    artifact_root = Path(args.artifact_root) if args.artifact_root else None
    cutoff = args.cutoff

    selection_record = {
        "candidate_path": str(candidate_path),
        "fallback_path": str(fallback_path),
        "output_path": str(output_path),
        "selected": None,
        "repair_attempted": False,
        "repair_result": None,
        "candidate_lint": None,
        "repaired_lint": None,
        "fallback_lint": None,
        "final_lint_ok": False,
        "final_lint_errors": [],
    }

    with tempfile.TemporaryDirectory(prefix="select-candidate-") as tmpdir:
        tmp_root = Path(tmpdir)

        # 1. Lint candidate
        cand_lint = invoke_lint(candidate_path, metadata_path, artifact_root, cutoff)
        selection_record["candidate_lint"] = cand_lint

        if cand_lint.get("ok") is True:
            # Candidate is clean
            selection_record["selected"] = "normal"
            selection_record["final_lint_ok"] = True
            selection_record["final_lint_errors"] = []
            if candidate_path.resolve() != output_path.resolve():
                atomic_write(candidate_path, output_path)
            lint_json_path.parent.mkdir(parents=True, exist_ok=True)
            lint_json_path.write_text(json.dumps(cand_lint, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            selection_json_path.parent.mkdir(parents=True, exist_ok=True)
            selection_json_path.write_text(json.dumps(selection_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            print(json.dumps({"ok": True, "selected": "normal"}))
            return 0

        # 2. Candidate invalid; check if repairable
        cand_errors = cand_lint.get("errors", [])
        if is_repairable(cand_errors):
            selection_record["repair_attempted"] = True
            repaired_tmp = tmp_root / "repaired.md"
            repair_res = invoke_repair(candidate_path, repaired_tmp)
            selection_record["repair_result"] = repair_res
            if repair_res.get("ok") is True and repaired_tmp.is_file():
                rep_lint = invoke_lint(repaired_tmp, metadata_path, artifact_root, cutoff)
                selection_record["repaired_lint"] = rep_lint
                if rep_lint.get("ok") is True:
                    # Repaired report is clean!
                    selection_record["selected"] = "repaired"
                    selection_record["final_lint_ok"] = True
                    selection_record["final_lint_errors"] = []
                    atomic_write(repaired_tmp, output_path)
                    lint_json_path.parent.mkdir(parents=True, exist_ok=True)
                    lint_json_path.write_text(json.dumps(rep_lint, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                    selection_json_path.parent.mkdir(parents=True, exist_ok=True)
                    selection_json_path.write_text(json.dumps(selection_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                    print(json.dumps({"ok": True, "selected": "repaired"}))
                    return 0

        # 3. Candidate invalid (and repair either not applicable or failed). Check prebuilt fallback.
        if fallback_path.is_file():
            fall_lint = invoke_lint(fallback_path, metadata_path, artifact_root, cutoff)
            selection_record["fallback_lint"] = fall_lint
            if fall_lint.get("ok") is True:
                # Fallback report is clean!
                selection_record["selected"] = "fallback"
                selection_record["final_lint_ok"] = True
                selection_record["final_lint_errors"] = []
                atomic_write(fallback_path, output_path)
                lint_json_path.parent.mkdir(parents=True, exist_ok=True)
                lint_json_path.write_text(json.dumps(fall_lint, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                selection_json_path.parent.mkdir(parents=True, exist_ok=True)
                selection_json_path.write_text(json.dumps(selection_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                print(json.dumps({"ok": True, "selected": "fallback"}))
                return 0
        else:
            selection_record["fallback_lint"] = {
                "ok": False,
                "errors": [f"fallback report file not found: {fallback_path}"],
            }

        # 4. Fallback is missing or invalid -> hard failure
        selection_record["selected"] = "failed"
        selection_record["final_lint_ok"] = False
        selection_record["final_lint_errors"] = cand_errors
        # Write diagnostics
        lint_json_path.parent.mkdir(parents=True, exist_ok=True)
        lint_json_path.write_text(json.dumps(cand_lint, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        selection_json_path.parent.mkdir(parents=True, exist_ok=True)
        selection_json_path.write_text(json.dumps(selection_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"ok": False, "selected": "failed", "errors": cand_errors}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
