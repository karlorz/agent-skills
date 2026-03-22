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

cleanup() {
  local jobs job_id plist_path launchd_label

  if [[ -f "${LOOP_JOBS_FILE:-}" ]]; then
    while IFS= read -r jobs; do
      job_id="$jobs"
      if [[ -z "$job_id" ]]; then
        continue
      fi
      if JOB_JSON="$(loop_get_job_json "$job_id" 2>/dev/null)"; then
        plist_path="$(jq -r '.plist_path // empty' <<<"$JOB_JSON")"
        launchd_label="$(jq -r '.launchd_label // empty' <<<"$JOB_JSON")"
        if [[ -n "$plist_path" && -f "$plist_path" ]]; then
          loop_unregister_launchd_job "$plist_path" >/dev/null 2>&1 || true
          rm -f "$plist_path"
        elif [[ -n "$launchd_label" ]]; then
          launchctl bootout "$(loop_launchd_domain)" "$launchd_label" >/dev/null 2>&1 || true
        fi
      fi
    done < <(jq -r '.[].id' "$LOOP_JOBS_FILE" 2>/dev/null || true)
  fi

  if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT:-}" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping scheduler test: launchd backend requires macOS"
  exit 0
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-scheduler-test.XXXXXX")"
trap cleanup EXIT

WORKSPACE="$TMP_ROOT/workspace"
mkdir -p "$WORKSPACE"

export LOOP_STATE_DIR="$TMP_ROOT/state"
export LOOP_LOG_DIR="$TMP_ROOT/logs"
export LOOP_PLIST_DIR="$TMP_ROOT/plists"
export LOOP_JOBS_FILE="$TMP_ROOT/state/jobs.json"
export LOOP_CODEX_BIN="/bin/echo"
export LOOP_CODEX_EXEC_ARGS=""
export LOOP_LOCK_TIMEOUT_SECONDS=5
mkdir -p "$LOOP_PLIST_DIR"

STATUS_JSON="$(bash "$SCRIPT_DIR/schedule-status.sh" --json)"
assert_eq "launchd" "$(jq -r '.backend' <<<"$STATUS_JSON")" "status backend"
assert_eq "0" "$(jq -r '.job_count' <<<"$STATUS_JSON")" "initial job count"

DRY_RUN_JSON="$(bash "$SCRIPT_DIR/schedule-add.sh" --workspace "$WORKSPACE" --interval 10m --prompt "check the deploy" --no-run-now --dry-run --json)"
DRY_JOB_ID="$(jq -r '.job.id' <<<"$DRY_RUN_JSON")"
DRY_PLIST_PATH="$(jq -r '.job.plist_path' <<<"$DRY_RUN_JSON")"
assert_eq "dry-run" "$(jq -r '.mode' <<<"$DRY_RUN_JSON")" "dry-run mode"
assert_eq "0" "$(jq 'length' "$LOOP_JOBS_FILE")" "dry-run should not persist a job"
assert_file_missing "$DRY_PLIST_PATH" "dry-run should not write a plist"

LIVE_ADD_JSON="$(bash "$SCRIPT_DIR/schedule-add.sh" --workspace "$WORKSPACE" --interval 1d --prompt "check the deploy" --no-run-now --json)"
JOB_ID="$(jq -r '.job.id' <<<"$LIVE_ADD_JSON")"
PLIST_PATH="$(jq -r '.job.plist_path' <<<"$LIVE_ADD_JSON")"
LOG_PATH="$(jq -r '.job.log_path' <<<"$LIVE_ADD_JSON")"
ERROR_LOG_PATH="$(jq -r '.job.error_log_path' <<<"$LIVE_ADD_JSON")"
LAUNCHD_LABEL="$(jq -r '.job.launchd_label' <<<"$LIVE_ADD_JSON")"

assert_eq "live" "$(jq -r '.mode' <<<"$LIVE_ADD_JSON")" "live add mode"
assert_eq "1" "$(jq 'length' "$LOOP_JOBS_FILE")" "live add should persist one job"
assert_file_exists "$PLIST_PATH" "live add should write a plist"
launchctl print "$(loop_launchd_domain)/$LAUNCHD_LABEL" >/dev/null

RUN_JSON="$(bash "$SCRIPT_DIR/schedule-run.sh" --job-id "$JOB_ID" --json)"
assert_eq "0" "$(jq -r '.exit_code' <<<"$RUN_JSON")" "manual run exit code"
assert_eq "success" "$(jq -r '.job.last_status' <<<"$RUN_JSON")" "manual run status"
assert_eq "1" "$(jq -r '.job.run_count' <<<"$RUN_JSON")" "manual run count"
assert_file_exists "$LOG_PATH" "manual run should create stdout log"
assert_file_exists "$ERROR_LOG_PATH" "manual run should create stderr log"
grep -F "check the deploy" "$LOG_PATH" >/dev/null

LOG_LIST="$(bash "$SCRIPT_DIR/schedule-logs.sh")"
grep -F "$JOB_ID" <<<"$LOG_LIST" >/dev/null

REMOVE_JSON="$(bash "$SCRIPT_DIR/schedule-remove.sh" --job-id "$JOB_ID" --purge-logs --json)"
assert_eq "live" "$(jq -r '.mode' <<<"$REMOVE_JSON")" "remove mode"
assert_eq "0" "$(jq 'length' "$LOOP_JOBS_FILE")" "remove should empty the registry"
assert_file_missing "$PLIST_PATH" "remove should delete the plist"
assert_file_missing "$LOG_PATH" "purge-logs should delete stdout log"
assert_file_missing "$ERROR_LOG_PATH" "purge-logs should delete stderr log"
if launchctl print "$(loop_launchd_domain)/$LAUNCHD_LABEL" >/dev/null 2>&1; then
  echo "Assertion failed: launchd job should be unloaded after removal" >&2
  exit 1
fi

printf '[]\n' >"$LOOP_JOBS_FILE"
export LOOP_REGISTRY_DELAY_SECONDS=0.05
for index in $(seq 1 8); do
  LOOP_JOB_ID="loop-lock-test-$index"
  LOOP_JOB_PROMPT="lock-test-$index"
  LOOP_JOB_CREATED_AT="$(loop_now_utc)"
  env LOOP_JOB_ID="$LOOP_JOB_ID" LOOP_JOB_PROMPT="$LOOP_JOB_PROMPT" LOOP_JOB_CREATED_AT="$LOOP_JOB_CREATED_AT" \
    bash -lc '
      set -euo pipefail
      source "$1"
      job_json="$(jq -n \
        --arg id "$LOOP_JOB_ID" \
        --arg prompt "$LOOP_JOB_PROMPT" \
        --arg workspace "$2" \
        --arg interval "10m" \
        --arg backend "launchd" \
        --arg launchd_label "test" \
        --arg plist_path "$3/$LOOP_JOB_ID.plist" \
        --arg log_path "$4/$LOOP_JOB_ID.log" \
        --arg error_log_path "$4/$LOOP_JOB_ID.err.log" \
        --arg created_at "$LOOP_JOB_CREATED_AT" \
        --argjson interval_seconds 600 \
        --argjson run_now false \
        '"'"'{
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
        }'"'"')"
      loop_append_job "$job_json"
    ' bash "$SCRIPT_DIR/common.sh" "$WORKSPACE" "$LOOP_PLIST_DIR" "$LOOP_LOG_DIR" &
done
wait
unset LOOP_REGISTRY_DELAY_SECONDS

assert_eq "8" "$(jq 'length' "$LOOP_JOBS_FILE")" "registry lock should preserve all concurrent appends"
assert_eq "8" "$(jq '[.[].id] | unique | length' "$LOOP_JOBS_FILE")" "registry lock should preserve unique ids"

echo "scheduler integration tests passed"
