#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  schedule-status.sh [--json]
EOF
}

JSON_OUTPUT=false

while (($# > 0)); do
  case "$1" in
    --json)
      JSON_OUTPUT=true
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

loop_init_registry

BACKEND="$(loop_backend)"
JOB_COUNT="$(loop_job_count)"
COMMAND_TEMPLATE="$(loop_command_template)"
AGENT_BIN="${LOOP_AGENT_BIN:-${LOOP_CODEX_BIN:-codex}}"
AGENT_PATH="$(command -v "$AGENT_BIN" 2>/dev/null || true)"
LAUNCHCTL_PATH="$(command -v launchctl 2>/dev/null || true)"
CRONTAB_PATH="$(command -v crontab 2>/dev/null || true)"
SCHTASKS_PATH="$(command -v schtasks 2>/dev/null || true)"
LOCK_DIR="$(loop_registry_lock_dir)"
LOCK_TIMEOUT_SECONDS="$(loop_lock_timeout_seconds)"

if $JSON_OUTPUT; then
  jq -n \
    --arg backend "$BACKEND" \
    --arg state_dir "$(loop_state_dir)" \
    --arg jobs_file "$(loop_jobs_file)" \
    --arg logs_dir "$(loop_logs_dir)" \
    --arg launchers_dir "$(loop_launchers_dir)" \
    --arg plist_dir "$(loop_plist_dir)" \
    --arg lock_dir "$LOCK_DIR" \
    --arg command_template "$COMMAND_TEMPLATE" \
    --arg agent_bin "$AGENT_BIN" \
    --arg agent_path "$AGENT_PATH" \
    --arg launchctl_path "$LAUNCHCTL_PATH" \
    --arg crontab_path "$CRONTAB_PATH" \
    --arg schtasks_path "$SCHTASKS_PATH" \
    --argjson lock_timeout_seconds "$LOCK_TIMEOUT_SECONDS" \
    --argjson job_count "$JOB_COUNT" \
    '{
      backend: $backend,
      state_dir: $state_dir,
      jobs_file: $jobs_file,
      logs_dir: $logs_dir,
      launchers_dir: $launchers_dir,
      plist_dir: $plist_dir,
      lock_dir: $lock_dir,
      lock_timeout_seconds: $lock_timeout_seconds,
      command_template: $command_template,
      agent_bin: $agent_bin,
      agent_path: $agent_path,
      launchctl_path: $launchctl_path,
      crontab_path: $crontab_path,
      schtasks_path: $schtasks_path,
      job_count: $job_count
    }'
  exit 0
fi

echo "Loop scheduler status"
echo "Backend: $BACKEND"
echo "Jobs file: $(loop_jobs_file)"
echo "State dir: $(loop_state_dir)"
echo "Logs dir: $(loop_logs_dir)"
echo "Launchers dir: $(loop_launchers_dir)"
echo "Plist dir: $(loop_plist_dir)"
echo "Lock dir: $LOCK_DIR"
echo "Lock timeout: ${LOCK_TIMEOUT_SECONDS}s"
echo "Job count: $JOB_COUNT"
echo "Command template: $COMMAND_TEMPLATE"
echo "Agent bin: $AGENT_BIN"
if [[ -n "$AGENT_PATH" ]]; then
  echo "Agent path: $AGENT_PATH"
else
  echo "Agent path: not found in PATH"
fi
if [[ "$BACKEND" == "launchd" ]]; then
  if [[ -n "$LAUNCHCTL_PATH" ]]; then
    echo "launchctl: $LAUNCHCTL_PATH"
  else
    echo "launchctl: not found"
  fi
fi
if [[ "$BACKEND" == "cron" ]]; then
  if [[ -n "$CRONTAB_PATH" ]]; then
    echo "crontab: $CRONTAB_PATH"
  else
    echo "crontab: not found"
  fi
fi
if [[ "$BACKEND" == "task-scheduler" ]]; then
  if [[ -n "$SCHTASKS_PATH" ]]; then
    echo "schtasks: $SCHTASKS_PATH"
  else
    echo "schtasks: not found"
  fi
fi
