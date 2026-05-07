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

loop_codex_home() {
  if [[ -n "${CODEX_HOME:-}" ]]; then
    printf '%s\n' "$CODEX_HOME"
  else
    printf '%s/.codex\n' "$HOME"
  fi
}

loop_state_dir() {
  printf '%s\n' "${LOOP_STATE_DIR:-$(loop_codex_home)/loop-scheduler}"
}

loop_jobs_file() {
  printf '%s\n' "${LOOP_JOBS_FILE:-$(loop_state_dir)/jobs.json}"
}

loop_logs_dir() {
  printf '%s\n' "${LOOP_LOG_DIR:-$(loop_state_dir)/logs}"
}

loop_launchers_dir() {
  printf '%s\n' "${LOOP_LAUNCHERS_DIR:-$(loop_state_dir)/launchers}"
}

loop_windows_wrappers_dir() {
  printf '%s\n' "${LOOP_WINDOWS_WRAPPERS_DIR:-$(loop_state_dir)/windows-wrappers}"
}

loop_plist_dir() {
  printf '%s\n' "${LOOP_PLIST_DIR:-$HOME/Library/LaunchAgents}"
}

loop_backend() {
  if [[ -n "${LOOP_BACKEND:-}" ]]; then
    printf '%s\n' "$LOOP_BACKEND"
    return 0
  fi

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

loop_dispatch_interval_seconds() {
  local seconds="${LOOP_DISPATCH_INTERVAL_SECONDS:-60}"
  if ! [[ "$seconds" =~ ^[0-9]+$ ]]; then
    loop_error "LOOP_DISPATCH_INTERVAL_SECONDS must be a non-negative integer"
  fi
  if ((seconds < 60)); then
    seconds=60
  fi
  printf '%s\n' "$seconds"
}

loop_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

loop_now_epoch() {
  date +%s
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

loop_write_lock_owner() {
  local owner_file="$1"
  cat >"$owner_file" <<EOF
pid=$$
started_at_epoch=$(loop_now_epoch)
host=$(hostname)
EOF
}

loop_lock_owner_value() {
  local owner_file="$1"
  local key="$2"
  if [[ ! -f "$owner_file" ]]; then
    return 1
  fi
  awk -F= -v key="$key" '$1 == key { print $2; exit }' "$owner_file"
}

loop_pid_is_alive() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

loop_lock_is_stale() {
  local owner_file="$1"
  local started_at_epoch pid now age stale_seconds

  started_at_epoch="$(loop_lock_owner_value "$owner_file" "started_at_epoch" 2>/dev/null || true)"
  [[ "$started_at_epoch" =~ ^[0-9]+$ ]] || return 1

  stale_seconds="$(loop_lock_stale_seconds)"
  now="$(loop_now_epoch)"
  age=$((now - started_at_epoch))
  if ((age < stale_seconds)); then
    return 1
  fi

  pid="$(loop_lock_owner_value "$owner_file" "pid" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    return 0
  fi

  if ! loop_pid_is_alive "$pid"; then
    return 0
  fi

  return 1
}

loop_registry_lock_owner_pid() {
  loop_lock_owner_value "$(loop_registry_lock_owner_file)" "pid"
}

loop_acquire_registry_lock() {
  local lock_dir timeout_seconds deadline

  mkdir -p "$(loop_state_dir)"
  lock_dir="$(loop_registry_lock_dir)"
  timeout_seconds="$(loop_lock_timeout_seconds)"
  deadline=$((SECONDS + timeout_seconds))

  while true; do
    if mkdir "$lock_dir" 2>/dev/null; then
      loop_write_lock_owner "$(loop_registry_lock_owner_file)"
      return 0
    fi

    if loop_lock_is_stale "$(loop_registry_lock_owner_file)"; then
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

loop_job_locks_dir() {
  printf '%s\n' "$(loop_state_dir)/job-locks"
}

loop_job_lock_dir_from_id() {
  printf '%s/%s.lock\n' "$(loop_job_locks_dir)" "$1"
}

loop_job_lock_owner_file_from_id() {
  printf '%s/owner' "$(loop_job_lock_dir_from_id "$1")"
}

loop_job_lock_owner_pid() {
  loop_lock_owner_value "$(loop_job_lock_owner_file_from_id "$1")" "pid"
}

loop_job_lock_is_stale() {
  loop_lock_is_stale "$(loop_job_lock_owner_file_from_id "$1")"
}

loop_acquire_job_lock() {
  local job_id="$1"
  local lock_dir owner_file

  mkdir -p "$(loop_job_locks_dir)"
  lock_dir="$(loop_job_lock_dir_from_id "$job_id")"
  owner_file="$(loop_job_lock_owner_file_from_id "$job_id")"

  if mkdir "$lock_dir" 2>/dev/null; then
    loop_write_lock_owner "$owner_file"
    return 0
  fi

  if loop_job_lock_is_stale "$job_id"; then
    rm -rf "$lock_dir"
    if mkdir "$lock_dir" 2>/dev/null; then
      loop_write_lock_owner "$owner_file"
      return 0
    fi
  fi

  return 1
}

loop_release_job_lock() {
  local job_id="$1"
  local lock_dir owner_pid

  lock_dir="$(loop_job_lock_dir_from_id "$job_id")"
  if [[ ! -d "$lock_dir" ]]; then
    return 0
  fi

  owner_pid="$(loop_job_lock_owner_pid "$job_id" 2>/dev/null || true)"
  if [[ -n "$owner_pid" && "$owner_pid" != "$$" ]]; then
    loop_error "Refusing to release loop job lock owned by pid $owner_pid"
  fi

  rm -rf "$lock_dir"
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

loop_launcher_path_from_id() {
  printf '%s/%s.sh\n' "$(loop_launchers_dir)" "$1"
}

loop_cron_tag_from_id() {
  printf '# codex-loop:%s' "$1"
}

loop_task_name_from_id() {
  printf 'CodexLoop-%s\n' "$1"
}

loop_task_wrapper_path_from_id() {
  printf '%s/%s.cmd\n' "$(loop_windows_wrappers_dir)" "$1"
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
  mkdir -p "$(loop_launchers_dir)"
  mkdir -p "$(loop_job_locks_dir)"

  case "$(loop_backend)" in
    launchd)
      mkdir -p "$(loop_plist_dir)"
      ;;
    task-scheduler)
      mkdir -p "$(loop_windows_wrappers_dir)"
      ;;
  esac

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

loop_iso_to_epoch() {
  local iso_value="$1"
  python3 - "$iso_value" <<'PY'
import datetime
import sys

value = sys.argv[1]
if not value:
    raise SystemExit(1)
if value.endswith("Z"):
    value = value[:-1] + "+00:00"
print(int(datetime.datetime.fromisoformat(value).timestamp()))
PY
}

loop_job_is_due_now() {
  local job_json="$1"
  local now_epoch="$2"

  python3 - "$job_json" "$now_epoch" <<'PY'
import datetime
import json
import sys

job = json.loads(sys.argv[1])
now_epoch = int(sys.argv[2])
interval_seconds = int(job.get("interval_seconds") or 0)
anchor = job.get("last_run_started_at") or job.get("created_at")

if not anchor or interval_seconds <= 0:
    print("true")
    raise SystemExit(0)

if anchor.endswith("Z"):
    anchor = anchor[:-1] + "+00:00"

anchor_epoch = int(datetime.datetime.fromisoformat(anchor).timestamp())
print("true" if now_epoch - anchor_epoch >= interval_seconds else "false")
PY
}

loop_default_command_template() {
  local agent_bin="${LOOP_AGENT_BIN:-${LOOP_CODEX_BIN:-codex}}"
  local exec_args="${LOOP_AGENT_EXEC_ARGS:-${LOOP_CODEX_EXEC_ARGS:---full-auto}}"

  if [[ -n "$exec_args" ]]; then
    printf '%s exec -C {workspace} --skip-git-repo-check %s {prompt}\n' "$agent_bin" "$exec_args"
  else
    printf '%s exec -C {workspace} --skip-git-repo-check {prompt}\n' "$agent_bin"
  fi
}

loop_command_template() {
  if [[ -n "${LOOP_COMMAND_TEMPLATE:-}" ]]; then
    printf '%s\n' "$LOOP_COMMAND_TEMPLATE"
  else
    loop_default_command_template
  fi
}

loop_build_command_from_template() {
  local template="$1"
  local workspace="$2"
  local prompt="$3"
  local job_id="${4:-}"

  local quoted_workspace quoted_prompt quoted_job_id rendered
  quoted_workspace="$(printf '%q' "$workspace")"
  quoted_prompt="$(printf '%q' "$prompt")"
  quoted_job_id="$(printf '%q' "$job_id")"

  rendered="$template"
  rendered="${rendered//\{workspace\}/$quoted_workspace}"
  rendered="${rendered//\{prompt\}/$quoted_prompt}"
  rendered="${rendered//\{job_id\}/$quoted_job_id}"
  printf '%s\n' "$rendered"
}

loop_build_codex_command() {
  loop_build_command_from_template "$(loop_command_template)" "$1" "$2" "${3:-}"
}

loop_write_job_launcher() {
  local job_id="$1"
  local runner_script="$2"
  local launcher_path state_dir logs_dir jobs_file command_template timeout_seconds stale_seconds
  local quoted_runner quoted_job_id quoted_state_dir quoted_logs_dir quoted_jobs_file
  local quoted_command_template quoted_timeout quoted_stale quoted_home quoted_path

  launcher_path="$(loop_launcher_path_from_id "$job_id")"
  state_dir="$(loop_state_dir)"
  logs_dir="$(loop_logs_dir)"
  jobs_file="$(loop_jobs_file)"
  command_template="$(loop_command_template)"
  timeout_seconds="$(loop_lock_timeout_seconds)"
  stale_seconds="$(loop_lock_stale_seconds)"

  quoted_runner="$(printf '%q' "$runner_script")"
  quoted_job_id="$(printf '%q' "$job_id")"
  quoted_state_dir="$(printf '%q' "$state_dir")"
  quoted_logs_dir="$(printf '%q' "$logs_dir")"
  quoted_jobs_file="$(printf '%q' "$jobs_file")"
  quoted_command_template="$(printf '%q' "$command_template")"
  quoted_timeout="$(printf '%q' "$timeout_seconds")"
  quoted_stale="$(printf '%q' "$stale_seconds")"
  quoted_home="$(printf '%q' "$HOME")"
  quoted_path="$(printf '%q' "${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}")"

  cat >"$launcher_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export HOME=$quoted_home
export PATH=$quoted_path
export LOOP_STATE_DIR=$quoted_state_dir
export LOOP_LOG_DIR=$quoted_logs_dir
export LOOP_JOBS_FILE=$quoted_jobs_file
export LOOP_COMMAND_TEMPLATE=$quoted_command_template
export LOOP_LOCK_TIMEOUT_SECONDS=$quoted_timeout
export LOOP_LOCK_STALE_SECONDS=$quoted_stale
exec bash $quoted_runner --job-id $quoted_job_id --trigger scheduled --check-due
EOF
  chmod 755 "$launcher_path"
}

loop_windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -aw "$path"
  else
    printf '%s\n' "$path"
  fi
}

loop_write_windows_wrapper() {
  local job_id="$1"
  local launcher_path="$2"
  local wrapper_path bash_path bash_windows launcher_windows

  wrapper_path="$(loop_task_wrapper_path_from_id "$job_id")"
  bash_path="$(command -v bash 2>/dev/null || true)"
  if [[ -z "$bash_path" ]]; then
    loop_error "bash is required for the task-scheduler backend"
  fi

  bash_windows="$(loop_windows_path "$bash_path")"
  launcher_windows="$(loop_windows_path "$launcher_path")"

  cat >"$wrapper_path" <<EOF
@echo off
"$bash_windows" "$launcher_windows"
EOF
  chmod 755 "$wrapper_path"
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
  local launcher_path="$2"
  local log_path="$3"
  local err_path="$4"
  local label plist_path state_dir logs_dir path_env home_dir dispatch_interval

  label="$(loop_label_from_id "$job_id")"
  plist_path="$(loop_plist_path_from_id "$job_id")"
  state_dir="$(loop_state_dir)"
  logs_dir="$(loop_logs_dir)"
  path_env="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
  home_dir="$HOME"
  dispatch_interval="$(loop_dispatch_interval_seconds)"

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
      <string>$(loop_xml_escape "$launcher_path")</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$(loop_xml_escape "$state_dir")</string>
    <key>StartInterval</key>
    <integer>${dispatch_interval}</integer>
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
      <string>$(loop_xml_escape "$(loop_jobs_file)")</string>
      <key>LOOP_COMMAND_TEMPLATE</key>
      <string>$(loop_xml_escape "$(loop_command_template)")</string>
    </dict>
  </dict>
</plist>
EOF
}

loop_read_crontab() {
  if ! command -v crontab >/dev/null 2>&1; then
    loop_error "crontab is required for the cron backend"
  fi
  crontab -l 2>/dev/null || true
}

loop_write_crontab() {
  local content="$1"
  if ! command -v crontab >/dev/null 2>&1; then
    loop_error "crontab is required for the cron backend"
  fi
  printf '%s\n' "$content" | crontab -
}

loop_register_cron_job() {
  local job_id="$1"
  local launcher_path="$2"
  local tag line existing

  tag="$(loop_cron_tag_from_id "$job_id")"
  line="* * * * * /bin/bash $(printf '%q' "$launcher_path") >/dev/null 2>&1 ${tag}"
  existing="$(loop_read_crontab | grep -Fv "$tag" || true)"

  if [[ -n "$existing" ]]; then
    loop_write_crontab "${existing}"$'\n'"${line}"
  else
    loop_write_crontab "$line"
  fi
}

loop_unregister_cron_job() {
  local job_id="$1"
  local tag existing

  tag="$(loop_cron_tag_from_id "$job_id")"
  existing="$(loop_read_crontab | grep -Fv "$tag" || true)"
  loop_write_crontab "$existing"
}

loop_register_task_scheduler_job() {
  local job_id="$1"
  local wrapper_path="$2"
  local task_name wrapper_windows

  if ! command -v schtasks >/dev/null 2>&1; then
    loop_error "schtasks is required for the task-scheduler backend"
  fi

  task_name="$(loop_task_name_from_id "$job_id")"
  wrapper_windows="$(loop_windows_path "$wrapper_path")"
  schtasks /Create /F /SC MINUTE /MO 1 /TN "$task_name" /TR "\"$wrapper_windows\"" >/dev/null
}

loop_unregister_task_scheduler_job() {
  local task_name="$1"

  if ! command -v schtasks >/dev/null 2>&1; then
    loop_error "schtasks is required for the task-scheduler backend"
  fi

  schtasks /Delete /F /TN "$task_name" >/dev/null
}
