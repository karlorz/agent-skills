#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  local message="$2"

  if [[ ! -f "$path" ]]; then
    echo "Assertion failed: $message" >&2
    echo "  missing file: $path" >&2
    exit 1
  fi
}

assert_file_missing() {
  local path="$1"
  local message="$2"

  if [[ -e "$path" ]]; then
    echo "Assertion failed: $message" >&2
    echo "  unexpected path: $path" >&2
    exit 1
  fi
}

make_fake_crontab() {
  local bin_dir="$1"
  local state_file="$2"

  cat >"$bin_dir/crontab" <<EOF
#!/usr/bin/env bash
set -euo pipefail
STATE_FILE="$state_file"
if [[ "\${1:-}" == "-l" ]]; then
  cat "\$STATE_FILE" 2>/dev/null || true
  exit 0
fi
if [[ "\${1:-}" == "-" ]]; then
  cat >"\$STATE_FILE"
  exit 0
fi
echo "unsupported fake crontab args: \$*" >&2
exit 1
EOF
  chmod +x "$bin_dir/crontab"
}

make_fake_schtasks() {
  local bin_dir="$1"
  local log_file="$2"

  cat >"$bin_dir/schtasks" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$log_file"
exit 0
EOF
  chmod +x "$bin_dir/schtasks"
}

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT:-}" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-scheduler-test.XXXXXX")"
WORKSPACE="$TMP_ROOT/workspace"
mkdir -p "$WORKSPACE"

export LOOP_COMMAND_TEMPLATE="/bin/echo {prompt}"
export LOOP_LOCK_TIMEOUT_SECONDS=5

run_launchd_suite() {
  export LOOP_BACKEND=launchd
  export LOOP_STATE_DIR="$TMP_ROOT/launchd/state"
  export LOOP_LOG_DIR="$TMP_ROOT/launchd/logs"
  export LOOP_PLIST_DIR="$TMP_ROOT/launchd/plists"
  export LOOP_JOBS_FILE="$TMP_ROOT/launchd/state/jobs.json"

  mkdir -p "$LOOP_PLIST_DIR"

  STATUS_JSON="$(bash "$SCRIPT_DIR/schedule-status.sh" --json)"
  assert_eq "launchd" "$(jq -r '.backend' <<<"$STATUS_JSON")" "launchd status backend"
  assert_eq "0" "$(jq -r '.job_count' <<<"$STATUS_JSON")" "launchd initial job count"

  DRY_RUN_JSON="$(bash "$SCRIPT_DIR/schedule-add.sh" --workspace "$WORKSPACE" --interval 10m --prompt "check the deploy" --no-run-now --dry-run --json)"
  DRY_LAUNCHER_PATH="$(jq -r '.job.launcher_path' <<<"$DRY_RUN_JSON")"
  DRY_PLIST_PATH="$(jq -r '.job.plist_path' <<<"$DRY_RUN_JSON")"
  assert_eq "dry-run" "$(jq -r '.mode' <<<"$DRY_RUN_JSON")" "launchd dry-run mode"
  assert_eq "0" "$(jq 'length' "$LOOP_JOBS_FILE")" "launchd dry-run should not persist a job"
  assert_file_missing "$DRY_LAUNCHER_PATH" "launchd dry-run should not write a launcher"
  assert_file_missing "$DRY_PLIST_PATH" "launchd dry-run should not write a plist"

  LIVE_ADD_JSON="$(bash "$SCRIPT_DIR/schedule-add.sh" --workspace "$WORKSPACE" --interval 1d --prompt "check the deploy" --no-run-now --json)"
  JOB_ID="$(jq -r '.job.id' <<<"$LIVE_ADD_JSON")"
  PLIST_PATH="$(jq -r '.job.plist_path' <<<"$LIVE_ADD_JSON")"
  LAUNCHER_PATH="$(jq -r '.job.launcher_path' <<<"$LIVE_ADD_JSON")"
  LOG_PATH="$(jq -r '.job.log_path' <<<"$LIVE_ADD_JSON")"
  ERROR_LOG_PATH="$(jq -r '.job.error_log_path' <<<"$LIVE_ADD_JSON")"
  LAUNCHD_LABEL="$(jq -r '.job.launchd_label' <<<"$LIVE_ADD_JSON")"

  assert_eq "live" "$(jq -r '.mode' <<<"$LIVE_ADD_JSON")" "launchd live add mode"
  assert_eq "1" "$(jq 'length' "$LOOP_JOBS_FILE")" "launchd live add should persist one job"
  assert_file_exists "$LAUNCHER_PATH" "launchd live add should write a launcher"
  assert_file_exists "$PLIST_PATH" "launchd live add should write a plist"
  launchctl print "$(loop_launchd_domain)/$LAUNCHD_LABEL" >/dev/null

  RUN_JSON="$(bash "$SCRIPT_DIR/schedule-run.sh" --job-id "$JOB_ID" --json)"
  assert_eq "0" "$(jq -r '.exit_code' <<<"$RUN_JSON")" "launchd manual run exit code"
  assert_eq "success" "$(jq -r '.job.last_status' <<<"$RUN_JSON")" "launchd manual run status"
  assert_eq "1" "$(jq -r '.job.run_count' <<<"$RUN_JSON")" "launchd manual run count"
  assert_file_exists "$LOG_PATH" "launchd manual run should create stdout log"
  assert_file_exists "$ERROR_LOG_PATH" "launchd manual run should create stderr log"
  grep -F "check the deploy" "$LOG_PATH" >/dev/null

  REMOVE_JSON="$(bash "$SCRIPT_DIR/schedule-remove.sh" --job-id "$JOB_ID" --purge-logs --json)"
  assert_eq "live" "$(jq -r '.mode' <<<"$REMOVE_JSON")" "launchd remove mode"
  assert_eq "0" "$(jq 'length' "$LOOP_JOBS_FILE")" "launchd remove should empty the registry"
  assert_file_missing "$PLIST_PATH" "launchd remove should delete the plist"
  assert_file_missing "$LAUNCHER_PATH" "launchd remove should delete the launcher"
  assert_file_missing "$LOG_PATH" "launchd purge-logs should delete stdout log"
  assert_file_missing "$ERROR_LOG_PATH" "launchd purge-logs should delete stderr log"
  if launchctl print "$(loop_launchd_domain)/$LAUNCHD_LABEL" >/dev/null 2>&1; then
    echo "Assertion failed: launchd job should be unloaded after removal" >&2
    exit 1
  fi
}

run_cron_suite() {
  local fake_bin cron_state

  fake_bin="$TMP_ROOT/fake-cron-bin"
  cron_state="$TMP_ROOT/fake-crontab.txt"
  mkdir -p "$fake_bin"
  make_fake_crontab "$fake_bin" "$cron_state"

  export PATH="$fake_bin:$PATH"
  export LOOP_BACKEND=cron
  export LOOP_STATE_DIR="$TMP_ROOT/cron/state"
  export LOOP_LOG_DIR="$TMP_ROOT/cron/logs"
  export LOOP_JOBS_FILE="$TMP_ROOT/cron/state/jobs.json"

  STATUS_JSON="$(bash "$SCRIPT_DIR/schedule-status.sh" --json)"
  assert_eq "cron" "$(jq -r '.backend' <<<"$STATUS_JSON")" "cron status backend"

  ADD_JSON="$(bash "$SCRIPT_DIR/schedule-add.sh" --workspace "$WORKSPACE" --interval 2h --prompt "cron check" --no-run-now --json)"
  JOB_ID="$(jq -r '.job.id' <<<"$ADD_JSON")"
  LAUNCHER_PATH="$(jq -r '.job.launcher_path' <<<"$ADD_JSON")"
  CRON_TAG="$(jq -r '.job.cron_tag' <<<"$ADD_JSON")"

  assert_eq "cron" "$(jq -r '.job.backend' <<<"$ADD_JSON")" "cron add backend"
  assert_file_exists "$LAUNCHER_PATH" "cron add should write a launcher"
  grep -F "$CRON_TAG" "$cron_state" >/dev/null
  grep -F "$LAUNCHER_PATH" "$cron_state" >/dev/null

  REMOVE_JSON="$(bash "$SCRIPT_DIR/schedule-remove.sh" --job-id "$JOB_ID" --json)"
  assert_eq "live" "$(jq -r '.mode' <<<"$REMOVE_JSON")" "cron remove mode"
  assert_file_missing "$LAUNCHER_PATH" "cron remove should delete the launcher"
  if [[ -s "$cron_state" ]]; then
    if grep -Fq "$CRON_TAG" "$cron_state"; then
      echo "Assertion failed: cron entry should be removed" >&2
      exit 1
    fi
  fi
}

run_task_scheduler_suite() {
  local fake_bin schtasks_log

  fake_bin="$TMP_ROOT/fake-schtasks-bin"
  schtasks_log="$TMP_ROOT/fake-schtasks.log"
  mkdir -p "$fake_bin"
  make_fake_schtasks "$fake_bin" "$schtasks_log"

  export PATH="$fake_bin:$PATH"
  export LOOP_BACKEND=task-scheduler
  export LOOP_STATE_DIR="$TMP_ROOT/task/state"
  export LOOP_LOG_DIR="$TMP_ROOT/task/logs"
  export LOOP_JOBS_FILE="$TMP_ROOT/task/state/jobs.json"

  ADD_JSON="$(bash "$SCRIPT_DIR/schedule-add.sh" --workspace "$WORKSPACE" --interval 30m --prompt "windows check" --no-run-now --json)"
  JOB_ID="$(jq -r '.job.id' <<<"$ADD_JSON")"
  TASK_NAME="$(jq -r '.job.task_name' <<<"$ADD_JSON")"
  TASK_WRAPPER_PATH="$(jq -r '.job.task_wrapper_path' <<<"$ADD_JSON")"

  assert_eq "task-scheduler" "$(jq -r '.job.backend' <<<"$ADD_JSON")" "task-scheduler add backend"
  assert_file_exists "$TASK_WRAPPER_PATH" "task-scheduler add should write a wrapper"
  grep -F "/Create" "$schtasks_log" >/dev/null
  grep -F "$TASK_NAME" "$schtasks_log" >/dev/null

  REMOVE_JSON="$(bash "$SCRIPT_DIR/schedule-remove.sh" --job-id "$JOB_ID" --json)"
  assert_eq "live" "$(jq -r '.mode' <<<"$REMOVE_JSON")" "task-scheduler remove mode"
  assert_file_missing "$TASK_WRAPPER_PATH" "task-scheduler remove should delete the wrapper"
  grep -F "/Delete" "$schtasks_log" >/dev/null
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  run_launchd_suite
else
  echo "Skipping live launchd suite on non-macOS host"
fi

run_cron_suite
run_task_scheduler_suite

printf 'scheduler integration tests passed\n'
