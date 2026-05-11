#!/bin/bash
set -euo pipefail

PROVIDER="${AUTOPILOT_PROVIDER:-claude}"

if [ "${1:-}" = "--provider" ]; then
  PROVIDER="${2:-}"
  shift 2
fi

MODE="${1:-reset}"

case "$PROVIDER" in
  claude)
    STATE_PREFIX="claude-autopilot"
    CURRENT_SESSION_FILE="/tmp/claude-current-session-id"
    ;;
  codex)
    STATE_PREFIX="codex-autopilot"
    CURRENT_SESSION_FILE="/tmp/codex-current-session-id"
    ;;
  *)
    echo "Unsupported provider: $PROVIDER" >&2
    exit 1
    ;;
esac

MAX_TURNS="${AUTOPILOT_MAX_TURNS:-${CMUX_AUTOPILOT_MAX_TURNS:-${CLAUDE_AUTOPILOT_MAX_TURNS:-20}}}"
DEBUG_FLAG_FILE="/tmp/${STATE_PREFIX}-debug-enabled"
DEBUG_LOG="/tmp/${STATE_PREFIX}-debug.log"

read_optional_file() {
  local path="$1"
  if [ -f "$path" ]; then
    tr -d '\n' < "$path"
  fi
}

current_session_id() {
  read_optional_file "$CURRENT_SESSION_FILE"
}

pid_file_for_session() {
  local sid="$1"
  printf '/tmp/%s-pid-%s\n' "$STATE_PREFIX" "$sid"
}

session_pid() {
  local sid="$1"
  read_optional_file "$(pid_file_for_session "$sid")"
}

provider_command_pattern() {
  printf '(^|[[:space:]/])%s([[:space:]]|$)\n' "$PROVIDER"
}

session_is_live() {
  local sid="$1"
  local pid
  pid="$(session_pid "$sid")"
  [ -n "$pid" ] || return 1

  local cmd
  cmd="$(ps -p "$pid" -o command= 2>/dev/null)" || return 1
  [ -n "$cmd" ] || return 1

  printf '%s\n' "$cmd" | grep -Eq "$(provider_command_pattern)"
}

prune_stale_runtime_state() {
  local sid="$1"
  local runtime_files=(
    "/tmp/${STATE_PREFIX}-blocked-${sid}"
    "/tmp/${STATE_PREFIX}-stop-${sid}"
    "/tmp/${STATE_PREFIX}-state-${sid}"
    "/tmp/${STATE_PREFIX}-idle-${sid}"
    "/tmp/${STATE_PREFIX}-wrapup-${sid}"
    "$(pid_file_for_session "$sid")"
  )

  session_is_live "$sid" && return 1

  rm -f "${runtime_files[@]}" 2>/dev/null
  return 0
}

debug_status() {
  if [ "${CMUX_AUTOPILOT_DEBUG:-0}" = "1" ]; then
    printf 'on (env)\n'
    return 0
  fi

  if [ -f "$DEBUG_FLAG_FILE" ]; then
    printf 'on (flag)\n'
    return 0
  fi

  printf 'off\n'
}

session_status_text() {
  local sid="$1"
  local has_run="$2"
  local stale_runtime="$3"

  if [ -f "/tmp/${STATE_PREFIX}-stop-${sid}" ]; then
    printf 'stop-pending'
  elif [ -f "/tmp/${STATE_PREFIX}-blocked-${sid}" ]; then
    printf 'blocked-live'
  elif [ "$has_run" = "0" ]; then
    printf 'idle'
  elif [ "$stale_runtime" -eq 1 ]; then
    printf 'ready-exited'
  else
    printf 'ready-available'
  fi
}

status_current() {
  local sid
  local has_run
  sid="$(current_session_id)"

  if [ -z "$sid" ]; then
    echo "Recorded latest session ID: (not set - restart session to enable)"
    exit 0
  fi

  local turns_file="/tmp/${STATE_PREFIX}-turns-${sid}"
  local stale_runtime=0
  if prune_stale_runtime_state "$sid"; then
    stale_runtime=1
  fi

  echo "Provider: $PROVIDER"
  echo "Recorded latest session ID: ${sid}"
  echo "Max turns: $MAX_TURNS"
  echo "Debug: $(debug_status)"
  echo "Debug log: $DEBUG_LOG"

  if [ -f "$turns_file" ]; then
    echo "Hook turn: $(cat "$turns_file")"
    has_run=1
  else
    echo "Hook turn: 0"
    has_run=0
  fi

  if [ -f "/tmp/${STATE_PREFIX}-stop-${sid}" ]; then
    echo "Status: STOP (will stop on next turn)"
  elif [ -f "/tmp/${STATE_PREFIX}-blocked-${sid}" ]; then
    echo "Status: BLOCKED (actively running)"
  elif [ "$has_run" = "0" ]; then
    echo "Status: idle (not started)"
  elif [ "$stale_runtime" -eq 1 ]; then
    echo "Status: ready (last session exited)"
  else
    echo "Status: ready (available)"
  fi
}

status_all() {
  local current_sid
  current_sid="$(current_session_id)"

  echo "Provider: $PROVIDER"
  echo "Max turns: $MAX_TURNS"
  echo "Debug: $(debug_status)"
  echo "Debug log: $DEBUG_LOG"
  echo "Recorded latest session: ${current_sid:-"(not set)"}"
  echo ""
  echo "Recorded sessions with hook state:"

  local found=0
  local f=""
  shopt -s nullglob 2>/dev/null || true
  for f in /tmp/${STATE_PREFIX}-turns-*; do
    [ -f "$f" ] || continue
    found=1
    local sid="${f#/tmp/${STATE_PREFIX}-turns-}"
    local stale_runtime=0
    if prune_stale_runtime_state "$sid"; then
      stale_runtime=1
    fi
    local turns
    turns="$(cat "$f")"
    local status_text
    status_text="$(session_status_text "$sid" "1" "$stale_runtime")"
    local current_marker=""
    if [ "$sid" = "$current_sid" ]; then
      current_marker=" recorded_current=yes"
    fi
    echo "  ${sid:0:20}...: hook_turn $turns status=$status_text$current_marker"
  done

  if [ "$found" -eq 0 ]; then
    echo "  (none)"
  fi
}

stop_current() {
  local sid
  sid="$(current_session_id)"

  if [ -z "$sid" ]; then
    echo "No session ID found. Restart session to enable."
    exit 1
  fi

  touch "/tmp/${STATE_PREFIX}-stop-${sid}"
  echo "Stop file created for latest recorded session: ${sid:0:20}..."
  echo "Autopilot will stop on next turn."
}

reset_session() {
  local sid="$1"
  rm -f \
    "/tmp/${STATE_PREFIX}-turns-${sid}" \
    "/tmp/${STATE_PREFIX}-stop-${sid}" \
    "/tmp/${STATE_PREFIX}-blocked-${sid}" \
    "/tmp/${STATE_PREFIX}-completed-${sid}" \
    "/tmp/${STATE_PREFIX}-wrapup-${sid}" \
    "/tmp/${STATE_PREFIX}-state-${sid}" \
    "/tmp/${STATE_PREFIX}-idle-${sid}" \
    "$(pid_file_for_session "$sid")"
}

reset_current() {
  local sid
  sid="$(current_session_id)"

  if [ -z "$sid" ]; then
    echo "No session ID found. Restart session to enable."
    exit 1
  fi

  reset_session "$sid"
  echo "Reset latest recorded session: ${sid:0:20}..."
  echo "Next cycle will start from turn 1/$MAX_TURNS"
}

reset_all() {
  local count=0
  local f=""
  shopt -s nullglob 2>/dev/null || true
  for f in /tmp/${STATE_PREFIX}-turns-*; do
    [ -f "$f" ] || continue
    local sid="${f#/tmp/${STATE_PREFIX}-turns-}"
    reset_session "$sid"
    echo "Reset: ${sid:0:20}..."
    count=$((count + 1))
  done

  echo "Reset $count session(s). Next cycle will start from turn 1/$MAX_TURNS"
}

debug_on() {
  touch "$DEBUG_FLAG_FILE"
  echo "Autopilot debug enabled for provider: $PROVIDER"
  echo "Debug log: $DEBUG_LOG"
}

debug_off() {
  rm -f "$DEBUG_FLAG_FILE"
  echo "Autopilot debug disabled for provider: $PROVIDER"
  echo "Debug log: $DEBUG_LOG"
}

case "$MODE" in
  status)
    status_current
    ;;
  status-all)
    status_all
    ;;
  stop)
    stop_current
    ;;
  reset)
    reset_current
    ;;
  all)
    reset_all
    ;;
  debug-on)
    debug_on
    ;;
  debug-off)
    debug_off
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: $0 [--provider claude|codex] [status|status-all|stop|reset|all|debug-on|debug-off]" >&2
    exit 1
    ;;
esac
