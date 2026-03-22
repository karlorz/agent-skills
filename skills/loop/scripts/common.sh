#!/usr/bin/env bash
set -euo pipefail

loop_error() {
  echo "$*" >&2
  return 1
}

loop_require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    loop_error "Missing value for $flag"
  fi
}

loop_state_dir() {
  printf '%s\n' "${LOOP_STATE_DIR:-$HOME/.codex/loop-scheduler}"
}

loop_jobs_file() {
  printf '%s\n' "${LOOP_JOBS_FILE:-$(loop_state_dir)/jobs.json}"
}

loop_logs_dir() {
  printf '%s\n' "${LOOP_LOG_DIR:-$(loop_state_dir)/logs}"
}

loop_plist_dir() {
  printf '%s\n' "${LOOP_PLIST_DIR:-$HOME/Library/LaunchAgents}"
}

loop_backend() {
  case "$(uname -s)" in
    Darwin)
      printf 'launchd\n'
      ;;
    Linux)
      printf 'cron\n'
      ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
      printf 'task-scheduler\n'
      ;;
    *)
      printf 'unsupported\n'
      ;;
  esac
}

loop_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

loop_realpath_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    loop_error "Directory does not exist: $dir"
  fi
  (
    cd "$dir"
    pwd
  )
}

loop_lock_timeout_seconds() {
  printf '%s\n' "${LOOP_LOCK_TIMEOUT_SECONDS:-15}"
}

loop_lock_stale_seconds() {
  printf '%s\n' "${LOOP_LOCK_STALE_SECONDS:-300}"
}

loop_registry_lock_dir() {
  printf '%s\n' "$(loop_state_dir)/registry.lock"
}

loop_registry_lock_owner_file() {
  printf '%s/owner' "$(loop_registry_lock_dir)"
}

loop_write_registry_lock_owner() {
  local owner_file="$1"
  cat >"$owner_file" <<EOF
pid=$$
started_at_epoch=$(date +%s)
host=$(hostname)
EOF
}

loop_registry_lock_owner_value() {
  local key="$1"
  local owner_file

  owner_file="$(loop_registry_lock_owner_file)"
  if [[ ! -f "$owner_file" ]]; then
    return 1
  fi

  awk -F= -v key="$key" '$1 == key { print $2; exit }' "$owner_file"
}

loop_registry_lock_owner_pid() {
  loop_registry_lock_owner_value "pid"
}

loop_registry_lock_started_at_epoch() {
  loop_registry_lock_owner_value "started_at_epoch"
}

loop_pid_is_alive() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

loop_registry_lock_is_stale() {
  local started_at_epoch pid now age stale_seconds

  started_at_epoch="$(loop_registry_lock_started_at_epoch 2>/dev/null || true)"
  [[ "$started_at_epoch" =~ ^[0-9]+$ ]] || return 1

  stale_seconds="$(loop_lock_stale_seconds)"
  now="$(date +%s)"
  age=$((now - started_at_epoch))
  if ((age < stale_seconds)); then
    return 1
  fi

  pid="$(loop_registry_lock_owner_pid 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    return 0
  fi

  if ! loop_pid_is_alive "$pid"; then
    return 0
  fi

  return 1
}

loop_acquire_registry_lock() {
  local lock_dir timeout_seconds deadline

  mkdir -p "$(loop_state_dir)"
  lock_dir="$(loop_registry_lock_dir)"
  timeout_seconds="$(loop_lock_timeout_seconds)"
  deadline=$((SECONDS + timeout_seconds))

  while true; do
    if mkdir "$lock_dir" 2>/dev/null; then
      loop_write_registry_lock_owner "$(loop_registry_lock_owner_file)"
      return 0
    fi

    if loop_registry_lock_is_stale; then
      rm -rf "$lock_dir"
      continue
    fi

    if ((SECONDS >= deadline)); then
      loop_error "Timed out waiting for loop registry lock: $lock_dir"
    fi

    sleep 0.1
  done
}

loop_release_registry_lock() {
  local lock_dir owner_pid

  lock_dir="$(loop_registry_lock_dir)"
  if [[ ! -d "$lock_dir" ]]; then
    return 0
  fi

  owner_pid="$(loop_registry_lock_owner_pid 2>/dev/null || true)"
  if [[ -n "$owner_pid" && "$owner_pid" != "$$" ]]; then
    loop_error "Refusing to release loop registry lock owned by pid $owner_pid"
  fi

  rm -rf "$lock_dir"
}

loop_with_registry_lock() {
  local had_errexit=0
  local exit_code=0

  if [[ $- == *e* ]]; then
    had_errexit=1
  fi

  loop_acquire_registry_lock

  if ((had_errexit)); then
    set +e
  fi
  "$@"
  exit_code=$?
  if ((had_errexit)); then
    set -e
  fi

  loop_release_registry_lock
  return "$exit_code"
}

loop_registry_debug_delay() {
  local delay="${LOOP_REGISTRY_DELAY_SECONDS:-}"
  if [[ -n "$delay" ]]; then
    sleep "$delay"
  fi
}

loop_generate_id() {
  python3 - <<'PY'
import secrets
import time

print(f"loop-{int(time.time())}-{secrets.token_hex(3)}")
PY
}

loop_interval_to_seconds() {
  local interval="$1"
  if [[ ! "$interval" =~ ^([0-9]+)([smhd])$ ]]; then
    loop_error "Unsupported interval format: $interval (expected Ns, Nm, Nh, or Nd)"
  fi

  local count="${BASH_REMATCH[1]}"
  local unit="${BASH_REMATCH[2]}"
  local seconds=0

  case "$unit" in
    s)
      seconds="$count"
      ;;
    m)
      seconds=$((count * 60))
      ;;
    h)
      seconds=$((count * 3600))
      ;;
    d)
      seconds=$((count * 86400))
      ;;
  esac

  if ((seconds < 60)); then
    seconds=60
  fi

  printf '%s\n' "$seconds"
}

loop_label_from_id() {
  printf 'com.openai.codex.loop.%s\n' "$1"
}

loop_plist_path_from_id() {
  printf '%s/%s.plist\n' "$(loop_plist_dir)" "$(loop_label_from_id "$1")"
}

loop_log_path_from_id() {
  printf '%s/%s.log\n' "$(loop_logs_dir)" "$1"
}

loop_error_log_path_from_id() {
  printf '%s/%s.err.log\n' "$(loop_logs_dir)" "$1"
}

loop_xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

loop_init_registry() {
  mkdir -p "$(loop_state_dir)"
  mkdir -p "$(loop_logs_dir)"

  if [[ "$(loop_backend)" == "launchd" ]]; then
    mkdir -p "$(loop_plist_dir)"
  fi

  if [[ ! -f "$(loop_jobs_file)" ]]; then
    printf '[]\n' >"$(loop_jobs_file)"
  fi
}

loop_get_job_json_unlocked() {
  local job_id="$1"
  jq -ce --arg id "$job_id" '.[] | select(.id == $id)' "$(loop_jobs_file)"
}

loop_get_job_json() {
  loop_with_registry_lock loop_get_job_json_unlocked "$1"
}

loop_list_jobs_json_unlocked() {
  jq '.' "$(loop_jobs_file)"
}

loop_list_jobs_json() {
  loop_with_registry_lock loop_list_jobs_json_unlocked
}

loop_job_count_unlocked() {
  jq 'length' "$(loop_jobs_file)"
}

loop_job_count() {
  loop_with_registry_lock loop_job_count_unlocked
}

loop_append_job_unlocked() {
  local job_json="$1"
  local job_id jobs_file tmp_file

  job_id="$(jq -r '.id' <<<"$job_json")"
  jobs_file="$(loop_jobs_file)"
  tmp_file="${jobs_file}.tmp"

  if jq -e --arg id "$job_id" '.[] | select(.id == $id)' "$jobs_file" >/dev/null; then
    loop_error "Loop job already exists: $job_id"
  fi

  loop_registry_debug_delay
  jq --argjson job "$job_json" '. + [$job]' "$jobs_file" >"$tmp_file"
  mv "$tmp_file" "$jobs_file"
}

loop_append_job() {
  loop_with_registry_lock loop_append_job_unlocked "$1"
}

loop_remove_job_from_registry_unlocked() {
  local job_id="$1"
  local jobs_file tmp_file

  jobs_file="$(loop_jobs_file)"
  tmp_file="${jobs_file}.tmp"

  loop_registry_debug_delay
  jq --arg id "$job_id" 'map(select(.id != $id))' "$jobs_file" >"$tmp_file"
  mv "$tmp_file" "$jobs_file"
}

loop_remove_job_from_registry() {
  loop_with_registry_lock loop_remove_job_from_registry_unlocked "$1"
}

loop_update_job_started_unlocked() {
  local job_id="$1"
  local trigger="$2"
  local started_at="$3"
  local jobs_file tmp_file

  jobs_file="$(loop_jobs_file)"
  tmp_file="${jobs_file}.tmp"

  loop_registry_debug_delay
  jq \
    --arg id "$job_id" \
    --arg trigger "$trigger" \
    --arg started_at "$started_at" \
    '
      map(
        if .id == $id then
          . + {
            last_run_started_at: $started_at,
            last_trigger: $trigger,
            last_status: "running",
            updated_at: $started_at,
            run_count: ((.run_count // 0) + 1)
          }
        else
          .
        end
      )
    ' \
    "$jobs_file" >"$tmp_file"
  mv "$tmp_file" "$jobs_file"
}

loop_update_job_started() {
  loop_with_registry_lock loop_update_job_started_unlocked "$1" "$2" "$3"
}

loop_update_job_finished_unlocked() {
  local job_id="$1"
  local finished_at="$2"
  local exit_code="$3"
  local status="$4"
  local jobs_file tmp_file

  jobs_file="$(loop_jobs_file)"
  tmp_file="${jobs_file}.tmp"

  loop_registry_debug_delay
  jq \
    --arg id "$job_id" \
    --arg finished_at "$finished_at" \
    --arg status "$status" \
    --argjson exit_code "$exit_code" \
    '
      map(
        if .id == $id then
          . + {
            last_run_finished_at: $finished_at,
            last_exit_code: $exit_code,
            last_status: $status,
            updated_at: $finished_at
          }
        else
          .
        end
      )
    ' \
    "$jobs_file" >"$tmp_file"
  mv "$tmp_file" "$jobs_file"
}

loop_update_job_finished() {
  loop_with_registry_lock loop_update_job_finished_unlocked "$1" "$2" "$3" "$4"
}

loop_build_codex_command() {
  local workspace="$1"
  local prompt="$2"
  local codex_bin="${LOOP_CODEX_BIN:-codex}"
  local exec_args="${LOOP_CODEX_EXEC_ARGS:---full-auto}"

  local quoted_bin quoted_workspace quoted_prompt
  quoted_bin="$(printf '%q' "$codex_bin")"
  quoted_workspace="$(printf '%q' "$workspace")"
  quoted_prompt="$(printf '%q' "$prompt")"

  if [[ -n "$exec_args" ]]; then
    printf '%s exec -C %s --skip-git-repo-check %s %s\n' \
      "$quoted_bin" \
      "$quoted_workspace" \
      "$exec_args" \
      "$quoted_prompt"
  else
    printf '%s exec -C %s --skip-git-repo-check %s\n' \
      "$quoted_bin" \
      "$quoted_workspace" \
      "$quoted_prompt"
  fi
}

loop_launchd_domain() {
  printf 'gui/%s\n' "$(id -u)"
}

loop_register_launchd_job() {
  local plist_path="$1"
  local domain

  if ! command -v launchctl >/dev/null 2>&1; then
    loop_error "launchctl is required for the launchd backend"
  fi

  domain="$(loop_launchd_domain)"
  launchctl bootout "$domain" "$plist_path" >/dev/null 2>&1 || true
  launchctl bootstrap "$domain" "$plist_path"
}

loop_unregister_launchd_job() {
  local plist_path="$1"
  local domain

  if ! command -v launchctl >/dev/null 2>&1; then
    loop_error "launchctl is required for the launchd backend"
  fi

  domain="$(loop_launchd_domain)"
  launchctl bootout "$domain" "$plist_path" >/dev/null 2>&1 || true
}

loop_write_launchd_plist() {
  local job_id="$1"
  local workspace="$2"
  local interval_seconds="$3"
  local runner_script="$4"

  local label plist_path log_path err_path state_dir logs_dir path_env home_dir codex_bin exec_args jobs_file

  label="$(loop_label_from_id "$job_id")"
  plist_path="$(loop_plist_path_from_id "$job_id")"
  log_path="$(loop_log_path_from_id "$job_id")"
  err_path="$(loop_error_log_path_from_id "$job_id")"
  state_dir="$(loop_state_dir)"
  logs_dir="$(loop_logs_dir)"
  path_env="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
  home_dir="$HOME"
  codex_bin="${LOOP_CODEX_BIN:-codex}"
  exec_args="${LOOP_CODEX_EXEC_ARGS:---full-auto}"
  jobs_file="$(loop_jobs_file)"

  cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$(loop_xml_escape "$label")</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>$(loop_xml_escape "$runner_script")</string>
      <string>--job-id</string>
      <string>$(loop_xml_escape "$job_id")</string>
      <string>--trigger</string>
      <string>scheduled</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$(loop_xml_escape "$workspace")</string>
    <key>StartInterval</key>
    <integer>${interval_seconds}</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$(loop_xml_escape "$log_path")</string>
    <key>StandardErrorPath</key>
    <string>$(loop_xml_escape "$err_path")</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>$(loop_xml_escape "$path_env")</string>
      <key>HOME</key>
      <string>$(loop_xml_escape "$home_dir")</string>
      <key>LOOP_STATE_DIR</key>
      <string>$(loop_xml_escape "$state_dir")</string>
      <key>LOOP_LOG_DIR</key>
      <string>$(loop_xml_escape "$logs_dir")</string>
      <key>LOOP_JOBS_FILE</key>
      <string>$(loop_xml_escape "$jobs_file")</string>
      <key>LOOP_CODEX_BIN</key>
      <string>$(loop_xml_escape "$codex_bin")</string>
      <key>LOOP_CODEX_EXEC_ARGS</key>
      <string>$(loop_xml_escape "$exec_args")</string>
    </dict>
  </dict>
</plist>
EOF
}
