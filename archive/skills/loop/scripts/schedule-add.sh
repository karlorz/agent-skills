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
case "$BACKEND" in
  launchd|cron|task-scheduler) ;;
  *)
    loop_error "Unsupported loop backend: $BACKEND"
    ;;
esac

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
LAUNCHER_PATH="$(loop_launcher_path_from_id "$JOB_ID")"
CRON_TAG="$(loop_cron_tag_from_id "$JOB_ID")"
TASK_NAME="$(loop_task_name_from_id "$JOB_ID")"
TASK_WRAPPER_PATH="$(loop_task_wrapper_path_from_id "$JOB_ID")"
COMMAND_TEMPLATE="$(loop_command_template)"

if [[ "$BACKEND" != "launchd" ]]; then
  LAUNCHD_LABEL=""
  PLIST_PATH=""
fi
if [[ "$BACKEND" != "task-scheduler" ]]; then
  TASK_NAME=""
  TASK_WRAPPER_PATH=""
fi
if [[ "$BACKEND" != "cron" ]]; then
  CRON_TAG=""
fi

JOB_JSON="$(jq -n \
  --arg id "$JOB_ID" \
  --arg prompt "$PROMPT" \
  --arg workspace "$WORKSPACE" \
  --arg interval "$INTERVAL" \
  --arg backend "$BACKEND" \
  --arg command_template "$COMMAND_TEMPLATE" \
  --arg launchd_label "$LAUNCHD_LABEL" \
  --arg plist_path "$PLIST_PATH" \
  --arg launcher_path "$LAUNCHER_PATH" \
  --arg cron_tag "$CRON_TAG" \
  --arg task_name "$TASK_NAME" \
  --arg task_wrapper_path "$TASK_WRAPPER_PATH" \
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
    command_template: $command_template,
    run_now: $run_now,
    launchd_label: $launchd_label,
    plist_path: $plist_path,
    launcher_path: $launcher_path,
    cron_tag: $cron_tag,
    task_name: $task_name,
    task_wrapper_path: $task_wrapper_path,
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
  echo "Launcher: $LAUNCHER_PATH"
  if [[ -n "$PLIST_PATH" ]]; then
    echo "Plist: $PLIST_PATH"
  fi
  if [[ -n "$CRON_TAG" ]]; then
    echo "Cron tag: $CRON_TAG"
  fi
  if [[ -n "$TASK_NAME" ]]; then
    echo "Task name: $TASK_NAME"
  fi
  echo "Logs: $LOG_PATH"
  echo "Run now: $RUN_NOW"
  exit 0
fi

loop_init_registry
loop_write_job_launcher "$JOB_ID" "$SCRIPT_DIR/job-runner.sh"
if [[ "$BACKEND" == "launchd" ]]; then
  loop_write_launchd_plist "$JOB_ID" "$LAUNCHER_PATH" "$LOG_PATH" "$ERROR_LOG_PATH"
elif [[ "$BACKEND" == "task-scheduler" ]]; then
  loop_write_windows_wrapper "$JOB_ID" "$LAUNCHER_PATH"
fi

if ! loop_append_job "$JOB_JSON"; then
  if [[ -n "$LAUNCHER_PATH" ]]; then
    rm -f "$LAUNCHER_PATH"
  fi
  if [[ -n "$TASK_WRAPPER_PATH" ]]; then
    rm -f "$TASK_WRAPPER_PATH"
  fi
  if [[ -n "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
  fi
  loop_error "Failed to add loop job to registry: $JOB_ID"
fi

REGISTER_EXIT=0
case "$BACKEND" in
  launchd)
    loop_register_launchd_job "$PLIST_PATH" || REGISTER_EXIT=$?
    ;;
  cron)
    loop_register_cron_job "$JOB_ID" "$LAUNCHER_PATH" || REGISTER_EXIT=$?
    ;;
  task-scheduler)
    loop_register_task_scheduler_job "$JOB_ID" "$TASK_WRAPPER_PATH" || REGISTER_EXIT=$?
    ;;
esac

if ((REGISTER_EXIT != 0)); then
  loop_remove_job_from_registry "$JOB_ID"
  if [[ -n "$LAUNCHER_PATH" ]]; then
    rm -f "$LAUNCHER_PATH"
  fi
  if [[ -n "$TASK_WRAPPER_PATH" ]]; then
    rm -f "$TASK_WRAPPER_PATH"
  fi
  if [[ -n "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
  fi
  loop_error "Failed to register ${BACKEND} job: $JOB_ID"
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
echo "Backend: $BACKEND"
echo "Launcher: $LAUNCHER_PATH"
if [[ -n "$PLIST_PATH" ]]; then
  echo "Plist: $PLIST_PATH"
fi
if [[ -n "$CRON_TAG" ]]; then
  echo "Cron tag: $CRON_TAG"
fi
if [[ -n "$TASK_NAME" ]]; then
  echo "Task name: $TASK_NAME"
fi
echo "Logs: $LOG_PATH"
echo "Run now: $RUN_NOW"
