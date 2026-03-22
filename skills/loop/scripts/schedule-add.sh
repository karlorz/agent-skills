#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  schedule-add.sh --workspace DIR --interval 10m --prompt "check the deploy" [--run-now|--no-run-now] [--dry-run] [--json]
  schedule-add.sh --workspace DIR --interval 10m [--run-now|--no-run-now] [--dry-run] [--json] -- prompt words here
EOF
}

WORKSPACE=""
INTERVAL=""
PROMPT=""
RUN_NOW=true
DRY_RUN=false
JSON_OUTPUT=false
BACKEND=""

while (($# > 0)); do
  case "$1" in
    --workspace)
      shift
      loop_require_value "--workspace" "${1:-}"
      WORKSPACE="$1"
      ;;
    --interval)
      shift
      loop_require_value "--interval" "${1:-}"
      INTERVAL="$1"
      ;;
    --prompt)
      shift
      loop_require_value "--prompt" "${1:-}"
      PROMPT="$1"
      ;;
    --run-now)
      RUN_NOW=true
      ;;
    --no-run-now)
      RUN_NOW=false
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --json)
      JSON_OUTPUT=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      PROMPT="$*"
      break
      ;;
    *)
      if [[ -z "$PROMPT" ]]; then
        PROMPT="$1"
      else
        PROMPT="$PROMPT $1"
      fi
      ;;
  esac
  shift || true
done

if [[ -z "$WORKSPACE" || -z "$INTERVAL" || -z "$PROMPT" ]]; then
  usage >&2
  exit 1
fi

BACKEND="$(loop_backend)"
if [[ "$BACKEND" != "launchd" ]]; then
  loop_error "This prototype currently installs only macOS launchd jobs"
fi

WORKSPACE="$(loop_realpath_dir "$WORKSPACE")"
INTERVAL_SECONDS="$(loop_interval_to_seconds "$INTERVAL")"
JOB_ID="$(loop_generate_id)"
CREATED_AT="$(loop_now_utc)"
RUN_NOW_JSON=false
if $RUN_NOW; then
  RUN_NOW_JSON=true
fi

LAUNCHD_LABEL="$(loop_label_from_id "$JOB_ID")"
PLIST_PATH="$(loop_plist_path_from_id "$JOB_ID")"
LOG_PATH="$(loop_log_path_from_id "$JOB_ID")"
ERROR_LOG_PATH="$(loop_error_log_path_from_id "$JOB_ID")"

JOB_JSON="$(jq -n \
  --arg id "$JOB_ID" \
  --arg prompt "$PROMPT" \
  --arg workspace "$WORKSPACE" \
  --arg interval "$INTERVAL" \
  --arg backend "$BACKEND" \
  --arg launchd_label "$LAUNCHD_LABEL" \
  --arg plist_path "$PLIST_PATH" \
  --arg log_path "$LOG_PATH" \
  --arg error_log_path "$ERROR_LOG_PATH" \
  --arg created_at "$CREATED_AT" \
  --argjson interval_seconds "$INTERVAL_SECONDS" \
  --argjson run_now "$RUN_NOW_JSON" \
  '{
    id: $id,
    prompt: $prompt,
    workspace: $workspace,
    interval: $interval,
    interval_seconds: $interval_seconds,
    backend: $backend,
    run_now: $run_now,
    launchd_label: $launchd_label,
    plist_path: $plist_path,
    log_path: $log_path,
    error_log_path: $error_log_path,
    created_at: $created_at,
    updated_at: $created_at,
    last_run_started_at: null,
    last_run_finished_at: null,
    last_exit_code: null,
    last_status: "scheduled",
    last_trigger: null,
    run_count: 0
  }')"

if $DRY_RUN; then
  if $JSON_OUTPUT; then
    jq -n \
      --argjson job "$JOB_JSON" \
      '{mode: "dry-run", job: $job}'
    exit 0
  fi

  echo "Dry-run: would schedule loop job: $JOB_ID"
  echo "Workspace: $WORKSPACE"
  echo "Prompt: $PROMPT"
  echo "Interval: $INTERVAL (${INTERVAL_SECONDS}s)"
  echo "Backend: $BACKEND"
  echo "Plist: $PLIST_PATH"
  echo "Logs: $LOG_PATH"
  echo "Run now: $RUN_NOW"
  exit 0
fi

loop_init_registry
loop_write_launchd_plist "$JOB_ID" "$WORKSPACE" "$INTERVAL_SECONDS" "$SCRIPT_DIR/job-runner.sh"

if ! loop_append_job "$JOB_JSON"; then
  rm -f "$PLIST_PATH"
  loop_error "Failed to add loop job to registry: $JOB_ID"
fi

if ! loop_register_launchd_job "$PLIST_PATH"; then
  loop_remove_job_from_registry "$JOB_ID"
  rm -f "$PLIST_PATH"
  loop_error "Failed to register launchd job: $JOB_ID"
fi

if $RUN_NOW; then
  bash "$SCRIPT_DIR/job-runner.sh" --job-id "$JOB_ID" --trigger manual >/dev/null 2>&1 &
fi

if $JSON_OUTPUT; then
  jq -n \
    --argjson job "$JOB_JSON" \
    '{mode: "live", job: $job}'
  exit 0
fi

echo "Scheduled loop job: $JOB_ID"
echo "Workspace: $WORKSPACE"
echo "Prompt: $PROMPT"
echo "Interval: $INTERVAL (${INTERVAL_SECONDS}s)"
echo "Backend: launchd"
echo "Plist: $PLIST_PATH"
echo "Logs: $LOG_PATH"
echo "Run now: $RUN_NOW"
