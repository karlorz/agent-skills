#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  schedule-logs.sh [--job-id ID] [--tail N] [--stderr] [--path-only]
  schedule-logs.sh ID [--tail N] [--stderr] [--path-only]
EOF
}

JOB_ID=""
TAIL_LINES=40
SHOW_STDERR=false
PATH_ONLY=false

while (($# > 0)); do
  case "$1" in
    --job-id)
      shift
      loop_require_value "--job-id" "${1:-}"
      JOB_ID="$1"
      ;;
    --tail)
      shift
      loop_require_value "--tail" "${1:-}"
      TAIL_LINES="$1"
      ;;
    --stderr)
      SHOW_STDERR=true
      ;;
    --path-only)
      PATH_ONLY=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$JOB_ID" ]]; then
        JOB_ID="$1"
      else
        loop_error "Unknown argument: $1"
      fi
      ;;
  esac
  shift || true
done

loop_init_registry

if [[ -z "$JOB_ID" ]]; then
  loop_list_jobs_json \
    | jq -r '.[] | [.id, .log_path, .error_log_path] | @tsv' \
    | while IFS=$'\t' read -r job_id log_path error_log_path; do
        printf '%s\t%s\t%s\n' "$job_id" "$log_path" "$error_log_path"
      done
  exit 0
fi

if ! JOB_JSON="$(loop_get_job_json "$JOB_ID" 2>/dev/null)"; then
  loop_error "No scheduled loop job found for id: $JOB_ID"
fi

LOG_PATH="$(jq -r '.log_path' <<<"$JOB_JSON")"
ERROR_LOG_PATH="$(jq -r '.error_log_path' <<<"$JOB_JSON")"
TARGET_PATH="$LOG_PATH"
if $SHOW_STDERR; then
  TARGET_PATH="$ERROR_LOG_PATH"
fi

if $PATH_ONLY; then
  echo "$TARGET_PATH"
  exit 0
fi

if [[ ! -f "$TARGET_PATH" ]]; then
  echo "No log file found at $TARGET_PATH"
  exit 0
fi

tail -n "$TAIL_LINES" "$TARGET_PATH"
