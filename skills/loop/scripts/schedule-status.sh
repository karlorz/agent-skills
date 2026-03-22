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
CODEX_BIN="${LOOP_CODEX_BIN:-codex}"
CODEX_PATH="$(command -v "$CODEX_BIN" 2>/dev/null || true)"
LAUNCHCTL_PATH="$(command -v launchctl 2>/dev/null || true)"
LOCK_DIR="$(loop_registry_lock_dir)"
LOCK_TIMEOUT_SECONDS="$(loop_lock_timeout_seconds)"

if $JSON_OUTPUT; then
  jq -n \
    --arg backend "$BACKEND" \
    --arg state_dir "$(loop_state_dir)" \
    --arg jobs_file "$(loop_jobs_file)" \
    --arg logs_dir "$(loop_logs_dir)" \
    --arg plist_dir "$(loop_plist_dir)" \
    --arg lock_dir "$LOCK_DIR" \
    --arg codex_bin "$CODEX_BIN" \
    --arg codex_path "$CODEX_PATH" \
    --arg launchctl_path "$LAUNCHCTL_PATH" \
    --argjson lock_timeout_seconds "$LOCK_TIMEOUT_SECONDS" \
    --argjson job_count "$JOB_COUNT" \
    '{
      backend: $backend,
      state_dir: $state_dir,
      jobs_file: $jobs_file,
      logs_dir: $logs_dir,
      plist_dir: $plist_dir,
      lock_dir: $lock_dir,
      lock_timeout_seconds: $lock_timeout_seconds,
      codex_bin: $codex_bin,
      codex_path: $codex_path,
      launchctl_path: $launchctl_path,
      job_count: $job_count
    }'
  exit 0
fi

echo "Loop scheduler status"
echo "Backend: $BACKEND"
echo "Jobs file: $(loop_jobs_file)"
echo "State dir: $(loop_state_dir)"
echo "Logs dir: $(loop_logs_dir)"
echo "Plist dir: $(loop_plist_dir)"
echo "Lock dir: $LOCK_DIR"
echo "Lock timeout: ${LOCK_TIMEOUT_SECONDS}s"
echo "Job count: $JOB_COUNT"
echo "Codex bin: $CODEX_BIN"
if [[ -n "$CODEX_PATH" ]]; then
  echo "Codex path: $CODEX_PATH"
else
  echo "Codex path: not found in PATH"
fi
if [[ "$BACKEND" == "launchd" ]]; then
  if [[ -n "$LAUNCHCTL_PATH" ]]; then
    echo "launchctl: $LAUNCHCTL_PATH"
  else
    echo "launchctl: not found"
  fi
fi
