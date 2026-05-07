#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  job-runner.sh --job-id ID [--trigger scheduled|manual] [--check-due]
EOF
}

JOB_ID=""
TRIGGER="scheduled"
CHECK_DUE=false

while (($# > 0)); do
  case "$1" in
    --job-id)
      shift
      loop_require_value "--job-id" "${1:-}"
      JOB_ID="$1"
      ;;
    --trigger)
      shift
      loop_require_value "--trigger" "${1:-}"
      TRIGGER="$1"
      ;;
    --check-due)
      CHECK_DUE=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      loop_error "Unknown argument: $1"
      ;;
  esac
  shift || true
done

if [[ -z "$JOB_ID" ]]; then
  usage >&2
  exit 1
fi

loop_init_registry

if ! JOB_JSON="$(loop_get_job_json "$JOB_ID" 2>/dev/null)"; then
  loop_error "No scheduled loop job found for id: $JOB_ID"
fi

WORKSPACE="$(jq -r '.workspace' <<<"$JOB_JSON")"
PROMPT="$(jq -r '.prompt' <<<"$JOB_JSON")"
LOG_PATH="$(jq -r '.log_path' <<<"$JOB_JSON")"
ERROR_LOG_PATH="$(jq -r '.error_log_path' <<<"$JOB_JSON")"
COMMAND_TEMPLATE="$(jq -r '.command_template // empty' <<<"$JOB_JSON")"

mkdir -p "$(dirname "$LOG_PATH")"
mkdir -p "$(dirname "$ERROR_LOG_PATH")"

if $CHECK_DUE; then
  NOW_EPOCH="$(loop_now_epoch)"
  if [[ "$(loop_job_is_due_now "$JOB_JSON" "$NOW_EPOCH")" != "true" ]]; then
    exit 0
  fi
fi

if ! loop_acquire_job_lock "$JOB_ID"; then
  {
    printf '[%s] skipped job %s trigger=%s reason=already-running\n' "$(loop_now_utc)" "$JOB_ID" "$TRIGGER"
  } >>"$LOG_PATH"
  exit 0
fi
trap 'loop_release_job_lock "$JOB_ID"' EXIT

STARTED_AT="$(loop_now_utc)"
loop_update_job_started "$JOB_ID" "$TRIGGER" "$STARTED_AT"

if [[ ! -d "$WORKSPACE" ]]; then
  {
    printf '[%s] workspace missing for job %s\n' "$STARTED_AT" "$JOB_ID"
    printf 'workspace: %s\n' "$WORKSPACE"
  } >>"$ERROR_LOG_PATH"
  loop_update_job_finished "$JOB_ID" "$(loop_now_utc)" 1 "failed"
  exit 1
fi

if [[ -z "$COMMAND_TEMPLATE" ]]; then
  COMMAND_STRING="$(loop_build_codex_command "$WORKSPACE" "$PROMPT" "$JOB_ID")"
else
  COMMAND_STRING="$(loop_build_command_from_template "$COMMAND_TEMPLATE" "$WORKSPACE" "$PROMPT" "$JOB_ID")"
fi

{
  printf '[%s] starting job %s trigger=%s\n' "$STARTED_AT" "$JOB_ID" "$TRIGGER"
  printf 'workspace: %s\n' "$WORKSPACE"
  printf 'command: %s\n' "$COMMAND_STRING"
  printf 'prompt: %s\n' "$PROMPT"
} >>"$LOG_PATH"

set +e
bash -lc "$COMMAND_STRING" >>"$LOG_PATH" 2>>"$ERROR_LOG_PATH"
EXIT_CODE=$?
set -e

FINISHED_AT="$(loop_now_utc)"
STATUS="success"
if ((EXIT_CODE != 0)); then
  STATUS="failed"
fi

{
  printf '[%s] finished job %s exit_code=%s status=%s\n' \
    "$FINISHED_AT" \
    "$JOB_ID" \
    "$EXIT_CODE" \
    "$STATUS"
} >>"$LOG_PATH"

loop_update_job_finished "$JOB_ID" "$FINISHED_AT" "$EXIT_CODE" "$STATUS"

exit "$EXIT_CODE"
