#!/usr/bin/env bash
#
# smoke-ephemeral.sh — one headless deep-research-dev smoke cell.
#
# Runs the dev-lane skill (slash `/deep-research-dev:deep-research-dev`) through
# `grok -p` in unattended, ephemeral mode and captures the result:
#
#   grok -p "/deep-research-dev:deep-research-dev --ephemeral --unattended <query>
#            <===REPORT=== framing>" -m $MODEL --yolo --cwd $SMOKE_CWD \
#            --output-format plain
#
# Usage:
#   smoke-ephemeral.sh "<query>" [output-dir]
#
#   query       research topic (required)
#   output-dir  where cell.md / cell.full.md / meta.json are written
#               (default: $DEEP_RESEARCH_DEV_ARTIFACT_ROOT/<timestamp>/, i.e.
#               <repo>/.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs/;
#               rejected with exit 2 when inside the resolved SkillWiki vault;
#               fails closed with exit 3 when the vault root cannot be resolved,
#               the containment probe fails, or the probe output is not an
#               exact `inside`/`outside` verdict)
#
# Environment:
#   MODEL       model for the headless run (default: flash-max)
#   SMOKE_CWD   working directory researched by the cell
#               (default: the git repo root containing this plugin)
#   DEEP_RESEARCH_DEV_ARTIFACT_ROOT   repository-local ignored artifact root
#               (default: <repo>/.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs)
#   DEEP_RESEARCH_DEV_VAULT_ROOT      explicit vault root override (test-only;
#               default: resolved via `skillwiki path`; must be an existing
#               absolute directory; exit 3 when resolution or the containment
#               probe fails)
#   DEEP_RESEARCH_DEV_PLUGIN_ROOT     optional absolute expected plugin root;
#               defaults to this packaged plugin's root and fails closed when
#               another same-named plugin wins discovery
#
# Outputs (beside the cell):
#   cell.md         final report — everything after the LAST literal ===REPORT===
#                   marker (even when embedded inline after narration), with
#                   leading whitespace trimmed; full-stream fallback when the
#                   marker is absent or the remainder is empty (extract-report.py)
#   cell.full.md    full stdout stream (agent chatter + report)
#   meta.json       run metadata incl. duration_s and exit_code
#   session-summary.json  frozen selected session summary when uniquely observed
#   lint.json       deterministic generated-report lint result
#
# Session provenance is captured fail-closed: a unique decoded fresh session
# adds observed model, summary SHA-256, and tool counts to meta.json; zero or
# ambiguous matches remain explicitly unverified without changing the report.
#
# Harness notes: wiki work item (vault-relative)
#   projects/agent-skills/work/2026-08-11-deep-research-dev-eval-matrix/
#   — smoke-notes.md, invocation-and-smoke-harness-policy.md
#
set -euo pipefail

QUERY="${1:-}"
EVIDENCE_CUTOFF="${DEEP_RESEARCH_DEV_EVIDENCE_CUTOFF:-}"
if [[ -z "$QUERY" ]]; then
  echo "usage: smoke-ephemeral.sh \"<query>\" [output-dir]" >&2
  echo "  query       research topic (required)" >&2
  echo "  output-dir  cell + meta.json destination" >&2
  echo "              (default: DEEP_RESEARCH_DEV_ARTIFACT_ROOT/<ts> — repo-local ignored root)" >&2
  echo "env: MODEL=<model> (default flash-max), SMOKE_CWD=<dir> (default: repo root)" >&2
  echo "     DEEP_RESEARCH_DEV_ARTIFACT_ROOT=<dir> (default: <repo>/.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs)" >&2
  echo "     DEEP_RESEARCH_DEV_EVIDENCE_CUTOFF=YYYY-MM-DD (optional report evidence cutoff for linting)" >&2
  echo "     DEEP_RESEARCH_DEV_SESSIONS_ROOT=<dir> (test-only session root override)" >&2
  echo "     DEEP_RESEARCH_DEV_VAULT_ROOT=<dir> (existing absolute vault root override)" >&2
  echo "     DEEP_RESEARCH_DEV_PLUGIN_ROOT=<dir> (optional exact local plugin root; defaults to this packaged plugin)" >&2
  exit 2
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "error: 'grok' CLI not found on PATH" >&2
  exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CWD="${SMOKE_CWD:-$REPO_ROOT}"
MODEL="${MODEL:-flash-max}"
PROVENANCE_HELPER="$SCRIPT_DIR/capture-session-provenance.py"
REPORT_LINTER="$SCRIPT_DIR/lint-report.py"
USAGE_HELPER="$SCRIPT_DIR/record-usage.py"
REPAIR_HELPER="$SCRIPT_DIR/repair-report-structure.py"
FALLBACK_BUILDER="$SCRIPT_DIR/build-fallback-report.py"
SELECTOR_HELPER="$SCRIPT_DIR/select-report-candidate.py"
if [[ -n "${DEEP_RESEARCH_DEV_SESSIONS_ROOT:-}" ]]; then
  # A caller-provided sessions root is test-only; snapshot it if available but
  # never create it here. A missing root records unavailable provenance after
  # the raw capture without touching the user's home session tree.
  SESSIONS_ROOT="$DEEP_RESEARCH_DEV_SESSIONS_ROOT"
else
  SESSIONS_ROOT="$HOME/.grok/sessions/$(python3 - "$CWD" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
)"
fi

[[ -f "$PROVENANCE_HELPER" ]] || { echo "error: provenance helper missing: $PROVENANCE_HELPER" >&2; exit 3; }
[[ -f "$REPORT_LINTER" ]] || { echo "error: report linter missing: $REPORT_LINTER" >&2; exit 3; }
[[ -f "$USAGE_HELPER" ]] || { echo "error: usage helper missing: $USAGE_HELPER" >&2; exit 3; }
[[ -f "$REPAIR_HELPER" ]] || { echo "error: repair helper missing: $REPAIR_HELPER" >&2; exit 3; }
[[ -f "$FALLBACK_BUILDER" ]] || { echo "error: fallback builder missing: $FALLBACK_BUILDER" >&2; exit 3; }
[[ -f "$SELECTOR_HELPER" ]] || { echo "error: selector helper missing: $SELECTOR_HELPER" >&2; exit 3; }

EXPECTED_PLUGIN_ROOT="${DEEP_RESEARCH_DEV_PLUGIN_ROOT:-$PLUGIN_ROOT}"
EXPECTED_PLUGIN_ROOT="$(python3 - "$EXPECTED_PLUGIN_ROOT" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).expanduser()
if not root.is_absolute() or not root.is_dir():
    raise SystemExit(1)
print(root.resolve())
PY
)" || {
  echo "error: DEEP_RESEARCH_DEV_PLUGIN_ROOT must be an existing absolute plugin directory" >&2
  exit 3
}
DISCOVERED_SKILL="$(grok inspect --json 2>/dev/null | python3 -c '
import json
import sys
try:
    data = json.load(sys.stdin)
    matches = [
        item.get("source", {}).get("path")
        for item in data.get("skills", [])
        if item.get("name") == "deep-research-dev"
        and item.get("source", {}).get("type") == "plugin"
    ]
except (OSError, ValueError, TypeError):
    raise SystemExit(1)
if len(matches) != 1 or not isinstance(matches[0], str):
    raise SystemExit(1)
print(matches[0])
')" || {
  echo "error: could not resolve exactly one discovered deep-research-dev plugin skill" >&2
  exit 3
}
if ! python3 - "$DISCOVERED_SKILL" "$EXPECTED_PLUGIN_ROOT" <<'PY'
from pathlib import Path
import sys
try:
    skill = Path(sys.argv[1]).resolve()
    root = Path(sys.argv[2]).resolve()
    skill.relative_to(root)
except (ValueError, OSError):
    raise SystemExit(1)
raise SystemExit(0)
PY
then
  echo "error: selected deep-research-dev skill is not under DEEP_RESEARCH_DEV_PLUGIN_ROOT; refusing live capture" >&2
  echo "  discovered: $DISCOVERED_SKILL" >&2
  echo "  expected root: $EXPECTED_PLUGIN_ROOT" >&2
  exit 3
fi
PLUGIN_VERSION="$(python3 - "$EXPECTED_PLUGIN_ROOT/.claude-plugin/plugin.json" <<'PY'
import json
import sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    version = data["version"]
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
if not isinstance(version, str) or not version:
    raise SystemExit(1)
print(version)
PY
)" || {
  echo "error: could not read selected deep-research-dev plugin version" >&2
  exit 3
}
DISCOVERED_SKILL_SHA256="$(python3 - "$DISCOVERED_SKILL" <<'PY'
import hashlib
from pathlib import Path
import sys
try:
    print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
except OSError:
    raise SystemExit(1)
PY
)" || {
  echo "error: could not hash selected deep-research-dev skill" >&2
  exit 3
}

ARTIFACT_ROOT="${DEEP_RESEARCH_DEV_ARTIFACT_ROOT:-$REPO_ROOT/.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs}"
if [[ -n "${2:-}" ]]; then
  OUT_DIR="$2"
else
  OUT_DIR="$ARTIFACT_ROOT/$(date +%Y%m%d-%H%M%S)"
fi

# Source selection is evaluated before this guard. The vault boundary guard runs
# BEFORE mkdir -p and BEFORE the headless model invocation. Vault root precedence: explicit DEEP_RESEARCH_DEV_VAULT_ROOT
# override, then `skillwiki path`. Three outcomes:
#   1. vault root resolves and output-dir is inside it  -> exit 2 (unchanged);
#   2. vault root resolves and output-dir is outside it -> continue;
#   3. vault root cannot resolve, or the containment probe fails or emits
#      anything other than the exact sentinels `inside`/`outside` -> exit 3.
# The probe signals its ordinary verdicts with sentinel output on exit 0;
# exit code 1 is reserved for probe failure (an unexpected Python exception
# also exits 1), so a crashed probe can never be mistaken for "outside".
resolve_vault_root() {
  local value
  if [[ -n "${DEEP_RESEARCH_DEV_VAULT_ROOT:-}" ]]; then
    # Explicit override: same final validity contract as every other
    # resolved value — trim outer whitespace, require an absolute path,
    # require an existing directory. Anything else is a resolution
    # failure: the boundary guard fails closed (exit 3) before
    # mkdir -p or any grok invocation.
    value="$(printf '%s' "$DEEP_RESEARCH_DEV_VAULT_ROOT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "$value" && "$value" == /* && -d "$value" ]] || return 1
    printf '%s\n' "$value"
    return 0
  fi
  command -v skillwiki >/dev/null 2>&1 || return 1
  # Probe `skillwiki path --plain` and `skillwiki path` separately: the
  # stdout of a failed first probe must never be concatenated with the
  # second probe's output.
  if ! value="$(skillwiki path --plain 2>/dev/null)"; then
    if ! value="$(skillwiki path 2>/dev/null)"; then
      return 1
    fi
  fi
  # Whitespace around a valid result may be trimmed.
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -n "$value" && "$value" != NO_VAULT_CONFIGURED* ]] || return 1
  # Normalize possible `skillwiki path` output forms to a bare path:
  # plain "/path", human hint "/path (via <source>)", or JSON in any layout
  # (parsed with Python 3 stdlib, not line regexes). Malformed or
  # unrecognized output is a resolution failure: the boundary guard fails
  # closed (exit 3) rather than misfiring on a bogus vault root.
  if [[ "$value" == \{* ]]; then
    value="$(json_path_value "$value")" || return 1
    value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  else
    value="${value%% (via*}"
  fi
  # Strict validation: reject NO_VAULT_CONFIGURED, relative paths, and
  # paths that are not existing directories.
  [[ -n "$value" && "$value" != NO_VAULT_CONFIGURED* ]] || return 1
  [[ "$value" == /* && -d "$value" ]] || return 1
  printf '%s\n' "$value"
}

# Extract the "data"."path" string of a skillwiki `path` JSON payload.
# Exits 1 (resolution failure) on malformed JSON or a missing/non-string
# path, never inventing a vault root.
json_path_value() {
  python3 - "$1" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
    path = data["data"]["path"]
except Exception:
    raise SystemExit(1)
if not isinstance(path, str) or not path.strip():
    raise SystemExit(1)
print(path)
PY
}

is_inside_path() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys
try:
    candidate = Path(sys.argv[1]).expanduser().resolve()
    parent = Path(sys.argv[2]).expanduser().resolve()
except Exception:
    # Any internal path-resolution failure: nonzero exit, no sentinel.
    raise SystemExit(1)
try:
    candidate.relative_to(parent)
except ValueError:
    # Ordinary case: candidate is not under parent -> outside.
    print("outside")
else:
    print("inside")
PY
}

if ! VAULT_ROOT="$(resolve_vault_root)"; then
  echo "error: SkillWiki vault resolution failed (boundary guard fails closed): cannot verify output-dir against the vault root" >&2
  echo "  install the skillwiki CLI or set DEEP_RESEARCH_DEV_VAULT_ROOT; refusing to create output dir or invoke grok" >&2
  exit 3
fi

# Sentinel containment verdict: the probe prints exactly `inside` or
# `outside` and exits 0 on ordinary execution. Any probe failure (nonzero
# exit, including the ordinary Python exception code 1) or any output other
# than the exact sentinels is a boundary failure that fails closed (exit 3)
# before mkdir/Grok. Exit code 1 must never mean both "outside" and an
# unexpected Python failure.
PROBE_RC=0
PROBE_OUTPUT="$(is_inside_path "$OUT_DIR" "$VAULT_ROOT")" || PROBE_RC=$?
if [[ "$PROBE_RC" -ne 0 ]]; then
  echo "error: SkillWiki vault boundary guard failed: python3 containment probe failed (exit $PROBE_RC); refusing to continue" >&2
  exit 3
fi
if [[ "$PROBE_OUTPUT" == "inside" ]]; then
  echo "error: output-dir must not be inside SkillWiki vault: $OUT_DIR" >&2
  exit 2
fi
if [[ "$PROBE_OUTPUT" != "outside" ]]; then
  echo "error: SkillWiki vault boundary guard failed: python3 containment probe produced unrecognized output; refusing to continue" >&2
  exit 3
fi
mkdir -p "$OUT_DIR"

CELL="$OUT_DIR/cell.md"
FULL="$OUT_DIR/cell.full.md"
META="$OUT_DIR/meta.json"
PROVENANCE="$OUT_DIR/provenance.json"
FROZEN_SUMMARY="$OUT_DIR/session-summary.json"
LINT="$OUT_DIR/lint.json"
FALLBACK_INPUT="$OUT_DIR/fallback-input.json"
FALLBACK_MD="$OUT_DIR/fallback.md"
SELECTION_JSON="$OUT_DIR/report-selection.json"
RUN_ID="$(basename "$OUT_DIR")"
QUERY_ID="$(printf '%s' "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-*//; s/-*$//' | cut -c1-32)"
[[ -n "$QUERY_ID" ]] || QUERY_ID="query"

PROMPT="/deep-research-dev:deep-research-dev --ephemeral --unattended ${QUERY}

Before normal synthesis:
1. Write the retained-claim and source-ledger JSON to:
$FALLBACK_INPUT
2. Run the installed plugin fallback builder to generate:
$FALLBACK_MD
Do not change fallback.md after synthesis.

When the research report is complete, print a line exactly:
===REPORT===
then print the final report only (no tool narration)."

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"
BEFORE_SESSIONS="$OUT_DIR/sessions-before.txt"
PROVENANCE_SNAPSHOT_RC=0
python3 "$PROVENANCE_HELPER" snapshot \
  --sessions-root "$SESSIONS_ROOT" \
  --output "$BEFORE_SESSIONS" || PROVENANCE_SNAPSHOT_RC=$?
if [[ "$PROVENANCE_SNAPSHOT_RC" -ne 0 ]]; then
  : >"$BEFORE_SESSIONS"
fi

set +e
grok -p "$PROMPT" -m "$MODEL" --yolo --cwd "$CWD" --output-format plain >"$FULL" 2>&1
EXIT_CODE=$?
set -e

FINISHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FINISH_EPOCH="$(date +%s)"
DURATION_S=$(( FINISH_EPOCH - START_EPOCH ))

# Extract the final report: everything after the LAST literal ===REPORT=== marker,
# even when the model appends it inline after narration (live q2-D failure mode:
# "...no source-plan channel failed.===REPORT==="). Leading whitespace/newlines
# after the marker are trimmed. extract-report.py falls back to the full stream
# when the marker is absent or the remainder is empty; the -s guard below stays
# as a safety net for any unexpected empty extraction.
python3 "$SCRIPT_DIR/extract-report.py" "$FULL" >"$CELL"
if [[ ! -s "$CELL" ]]; then
  cp "$FULL" "$CELL"
fi

BYTES_STDOUT="$(wc -c <"$FULL" | tr -d ' ')"
BYTES_REPORT="$(wc -c <"$CELL" | tr -d ' ')"
if [[ "$EXIT_CODE" -eq 0 ]]; then OUTCOME="ok"; else OUTCOME="failed"; fi

json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

cat >"$META" <<EOF
{
  "run_id": "$(json_str "$RUN_ID")",
  "phase": "smoke",
  "lane": "D",
  "query_id": "$(json_str "$QUERY_ID")",
  "evidence_cutoff": "$(json_str "$EVIDENCE_CUTOFF")",
  "attempt": 1,
  "model": "$(json_str "$MODEL")",
  "plugin_version": "$(json_str "$PLUGIN_VERSION")",
  "plugin_skill": "$(json_str "$DISCOVERED_SKILL")",
  "plugin_skill_sha256": "$(json_str "$DISCOVERED_SKILL_SHA256")",
  "slash": "/deep-research-dev:deep-research-dev --ephemeral --unattended",
  "cwd": "$(json_str "$CWD")",
  "started": "$(json_str "$STARTED")",
  "finished": "$(json_str "$FINISHED")",
  "duration_s": $DURATION_S,
  "exit_code": $EXIT_CODE,
  "outcome": "$(json_str "$OUTCOME")",
  "cell": "cell.md",
  "bytes_stdout": $BYTES_STDOUT,
  "bytes_report": $BYTES_REPORT,
  "purpose": "single-cell ephemeral unattended smoke (deep-research-dev dev lane)"
}
EOF

# Capture-time session provenance is independent of report extraction. It is
# fail-closed: a missing, malformed, or ambiguous session leaves no observed
# model rather than guessing. The raw report and process outcome remain intact.
PROVENANCE_RC=0
if [[ "$PROVENANCE_SNAPSHOT_RC" -eq 0 ]]; then
  python3 "$PROVENANCE_HELPER" resolve \
    --sessions-root "$SESSIONS_ROOT" \
    --before "$BEFORE_SESSIONS" \
    --started "$STARTED" \
    --query "$QUERY" \
    --output "$PROVENANCE" \
    --frozen-summary "$FROZEN_SUMMARY" || PROVENANCE_RC=$?
else
  python3 - "$PROVENANCE" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "actual_model": None,
    "actual_model_matches": [],
    "fresh_session_ids": [],
    "observation_error": "pre-launch session snapshot failed; model observation unavailable",
    "tool_counts": {},
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  PROVENANCE_RC=1
fi

# Capture metadata is merged only after the provenance helper has produced its
# immutable observation. The linter consumes the final metadata so the cutoff
# check can compare against capture start time.
python3 - "$META" "$PROVENANCE" "$PROVENANCE_RC" <<'PY'
import json
import sys
from pathlib import Path
meta_path = Path(sys.argv[1])
provenance_path = Path(sys.argv[2])
provenance_rc = int(sys.argv[3])
meta = json.loads(meta_path.read_text(encoding="utf-8"))
provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
for key in ("actual_model", "session_id", "session_provenance", "tool_counts", "fresh_session_ids", "actual_model_matches"):
    if key in provenance:
        meta[key] = provenance[key]
if "observation_error" in provenance:
    meta["actual_model_observation_error"] = provenance["observation_error"]
meta["provenance_observation_exit_code"] = provenance_rc
meta["provenance"] = "provenance.json"
if meta.get("session_provenance"):
    meta["frozen_session_summary"] = "session-summary.json"
meta_path.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

# Run deterministic candidate selection: normal candidate -> repair -> fallback.
# Selection metadata records candidate lint, repair attempts, and final chosen mode.
SELECTOR_ARGS=(
  --candidate "$CELL"
  --fallback "$FALLBACK_MD"
  --output "$CELL"
  --lint-json "$LINT"
  --selection-json "$SELECTION_JSON"
  --metadata "$META"
  --artifact-root "$OUT_DIR"
)
if [[ -n "$EVIDENCE_CUTOFF" ]]; then
  SELECTOR_ARGS+=(--cutoff "$EVIDENCE_CUTOFF")
fi
SELECTOR_RC=0
python3 "$SELECTOR_HELPER" "${SELECTOR_ARGS[@]}" >/dev/null 2>&1 || SELECTOR_RC=$?

python3 - "$META" "$LINT" "$SELECTION_JSON" "$SELECTOR_RC" <<'PY'
import json
import sys
from pathlib import Path
meta_path = Path(sys.argv[1])
lint_path = Path(sys.argv[2])
selection_path = Path(sys.argv[3])
selector_rc = int(sys.argv[4])
meta = json.loads(meta_path.read_text(encoding="utf-8"))
lint = json.loads(lint_path.read_text(encoding="utf-8")) if lint_path.is_file() else {}
selection = json.loads(selection_path.read_text(encoding="utf-8")) if selection_path.is_file() else {}

meta["report_lint"] = "lint.json"
meta["report_selection"] = "report-selection.json"
meta["report_candidate_selected"] = selection.get("selected")
meta["report_lint_exit_code"] = selector_rc
meta["report_lint_ok"] = lint.get("ok") is True and selector_rc == 0
meta["report_lint_errors"] = lint.get("errors", [])
meta_path.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

# Host-local usage record. Failure must not change the smoke exit code or
# mutate the captured report.
USAGE_STATUS="$(python3 - "$CELL" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"^\*\*Status: (Verified|Partial)\*\*$", text, re.M)
print(match.group(1) if match else "unknown")
PY
)"
USAGE_ARGS=(
  --query "$QUERY"
  --source smoke
  --invocation-mode unattended
  --output-mode stdout
  --outcome "$OUTCOME"
  --status "$USAGE_STATUS"
  --duration-s "$DURATION_S"
  --lint-json "$LINT"
  --plugin-version "$PLUGIN_VERSION"
  --cwd "$CWD"
  --report-path "$CELL"
  --smoke-meta "$META"
)
if [[ -n "${DEEP_RESEARCH_DEV_USAGE_HOME:-}" ]]; then
  USAGE_ARGS+=(--home "$DEEP_RESEARCH_DEV_USAGE_HOME")
fi
USAGE_RC=0
python3 "$USAGE_HELPER" "${USAGE_ARGS[@]}" >/dev/null || USAGE_RC=$?
if [[ "$USAGE_RC" -ne 0 ]]; then
  echo "warning: usage ledger write failed (exit $USAGE_RC); smoke result unchanged" >&2
fi

printf 'deep-research-dev smoke complete\n'
printf '  cell:     %s\n' "$CELL"
printf '  full:     %s\n' "$FULL"
printf '  meta:     %s\n' "$META"
printf '  exit:     %d\n' "$EXIT_CODE"
printf '  duration: %ds\n' "$DURATION_S"
