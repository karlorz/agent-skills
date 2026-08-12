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
#   MODEL       model for the headless run (default: deepseek-v4-flash)
#   SMOKE_CWD   working directory researched by the cell
#               (default: the git repo root containing this plugin)
#   DEEP_RESEARCH_DEV_ARTIFACT_ROOT   repository-local ignored artifact root
#               (default: <repo>/.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs)
#   DEEP_RESEARCH_DEV_VAULT_ROOT      explicit vault root override (test-only;
#               default: resolved via `skillwiki path`; must be an existing
#               absolute directory; exit 3 when resolution or the containment
#               probe fails)
#
# Outputs (beside the cell):
#   cell.md         final report — everything after the LAST literal ===REPORT===
#                   marker (even when embedded inline after narration), with
#                   leading whitespace trimmed; full-stream fallback when the
#                   marker is absent or the remainder is empty (extract-report.py)
#   cell.full.md    full stdout stream (agent chatter + report)
#   meta.json       run metadata incl. duration_s and exit_code
#
# Harness notes: wiki work item (vault-relative)
#   projects/agent-skills/work/2026-08-11-deep-research-dev-eval-matrix/
#   — smoke-notes.md, invocation-and-smoke-harness-policy.md
#
set -euo pipefail

QUERY="${1:-}"
if [[ -z "$QUERY" ]]; then
  echo "usage: smoke-ephemeral.sh \"<query>\" [output-dir]" >&2
  echo "  query       research topic (required)" >&2
  echo "  output-dir  cell + meta.json destination" >&2
  echo "              (default: DEEP_RESEARCH_DEV_ARTIFACT_ROOT/<ts> — repo-local ignored root)" >&2
  echo "env: MODEL=<model> (default deepseek-v4-flash), SMOKE_CWD=<dir> (default: repo root)" >&2
  echo "     DEEP_RESEARCH_DEV_ARTIFACT_ROOT=<dir> (default: <repo>/.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs)" >&2
  echo "     DEEP_RESEARCH_DEV_VAULT_ROOT=<dir> (explicit vault root override; an output-dir inside it is rejected, exit 2; resolution/probe failure exits 3)" >&2
  exit 2
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "error: 'grok' CLI not found on PATH" >&2
  exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CWD="${SMOKE_CWD:-$REPO_ROOT}"
MODEL="${MODEL:-deepseek-v4-flash}"

ARTIFACT_ROOT="${DEEP_RESEARCH_DEV_ARTIFACT_ROOT:-$REPO_ROOT/.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs}"
if [[ -n "${2:-}" ]]; then
  OUT_DIR="$2"
else
  OUT_DIR="$ARTIFACT_ROOT/$(date +%Y%m%d-%H%M%S)"
fi

# Vault boundary guard, evaluated BEFORE mkdir -p and BEFORE any grok
# invocation. Vault root precedence: explicit DEEP_RESEARCH_DEV_VAULT_ROOT
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
RUN_ID="$(basename "$OUT_DIR")"
QUERY_ID="$(printf '%s' "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-*//; s/-*$//' | cut -c1-32)"
[[ -n "$QUERY_ID" ]] || QUERY_ID="query"

PROMPT="/deep-research-dev:deep-research-dev --ephemeral --unattended ${QUERY}

When the research report is complete, print a line exactly:
===REPORT===
then print the final report only (no tool narration)."

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"

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
  "attempt": 1,
  "model": "$(json_str "$MODEL")",
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

printf 'deep-research-dev smoke complete\n'
printf '  cell:     %s\n' "$CELL"
printf '  full:     %s\n' "$FULL"
printf '  meta:     %s\n' "$META"
printf '  exit:     %d\n' "$EXIT_CODE"
printf '  duration: %ds\n' "$DURATION_S"
