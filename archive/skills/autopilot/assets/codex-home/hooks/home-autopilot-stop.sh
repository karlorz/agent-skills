#!/usr/bin/env bash
set -euo pipefail

trimmed_non_empty() {
  local value="$1"
  [[ -n "${value//[[:space:]]/}" ]]
}

codex_home_dir() {
  if [[ -n "${CODEX_HOME:-}" ]]; then
    printf '%s\n' "$CODEX_HOME"
  else
    printf '%s/.codex\n' "$HOME"
  fi
}

resolve_workspace_root() {
  local candidate="$1"

  if ! trimmed_non_empty "$candidate" || [[ ! -d "$candidate" ]]; then
    candidate="$(pwd)"
  fi

  git -C "$candidate" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$candidate"
}

session_workspace_file() {
  local session_id="$1"
  local template="${CMUX_SESSION_WORKSPACE_FILE_TEMPLATE:-${CMUX_CODEX_SESSION_WORKSPACE_FILE_TEMPLATE:-/tmp/codex-session-workspace-root-%s}}"

  printf "$template" "$session_id"
}

read_session_workspace_root() {
  local session_id="$1"
  local workspace_file=""
  local candidate=""
  local current_file="${CMUX_CURRENT_WORKSPACE_FILE:-${CMUX_CODEX_CURRENT_WORKSPACE_FILE:-/tmp/codex-current-workspace-root}}"

  if trimmed_non_empty "$session_id"; then
    workspace_file="$(session_workspace_file "$session_id")"
    if [[ -f "$workspace_file" ]]; then
      candidate="$(tr -d '\n' < "$workspace_file" 2>/dev/null || true)"
    fi
  fi

  if ! trimmed_non_empty "$candidate" && [[ -f "$current_file" ]]; then
    candidate="$(tr -d '\n' < "$current_file" 2>/dev/null || true)"
  fi

  if trimmed_non_empty "$candidate" && [[ -d "$candidate" ]]; then
    resolve_workspace_root "$candidate"
    return 0
  fi

  return 1
}

workspace_has_loop_hooks() {
  local workspace_root="$1"

  [[ -f "${workspace_root}/.codex/ralph-loop-state.json" ]] ||
    [[ -f "${workspace_root}/.codex/hooks/ralph-loop-stop.sh" ]] ||
    [[ -f "${workspace_root}/.codex/hooks/autopilot-stop.sh" ]]
}

HOOK_INPUT="$(cat)"
HOOK_CWD="$(jq -r '.cwd // empty' <<<"$HOOK_INPUT" 2>/dev/null || true)"
SESSION_ID="$(jq -r '.session_id // "default"' <<<"$HOOK_INPUT" 2>/dev/null || true)"
WORKSPACE_ROOT="$(resolve_workspace_root "$HOOK_CWD")"

if SESSION_WORKSPACE_ROOT="$(read_session_workspace_root "$SESSION_ID")"; then
  if [[ "$WORKSPACE_ROOT" = "$HOME" ]] || ! workspace_has_loop_hooks "$WORKSPACE_ROOT"; then
    WORKSPACE_ROOT="$SESSION_WORKSPACE_ROOT"
  fi
fi

AUTOPILOT_ROOT="${CMUX_AUTOPILOT_HOME_ROOT:-$(codex_home_dir)/autopilot}"

export CMUX_HOOK_PROVIDER="codex"
export CMUX_PROJECT_DIR="${CMUX_PROJECT_DIR:-$WORKSPACE_ROOT}"
export CMUX_AUTOPILOT_ENABLED="${CMUX_AUTOPILOT_ENABLED:-0}"
export CMUX_CODEX_HOOKS_ENABLED="${CMUX_CODEX_HOOKS_ENABLED:-0}"
export CMUX_AUTOPILOT_STATE_PREFIX="${CMUX_AUTOPILOT_STATE_PREFIX:-codex-autopilot}"
export CMUX_AUTOPILOT_CURRENT_SESSION_FILE="${CMUX_AUTOPILOT_CURRENT_SESSION_FILE:-/tmp/codex-current-session-id}"
export CMUX_AUTOPILOT_ENABLE_REVIEW_WINDOW="${CMUX_AUTOPILOT_ENABLE_REVIEW_WINDOW:-0}"
export CMUX_AUTOPILOT_INLINE_WRAPUP="${CMUX_AUTOPILOT_INLINE_WRAPUP:-1}"
export CMUX_AUTOPILOT_MONITORING_THRESHOLD="${CMUX_AUTOPILOT_MONITORING_THRESHOLD:-0}"
export CMUX_SESSION_ACTIVITY_SCRIPT="${CMUX_SESSION_ACTIVITY_SCRIPT:-$WORKSPACE_ROOT/.claude/hooks/session-activity-capture.sh}"

if [[ "$CMUX_AUTOPILOT_ENABLED" = "1" ]] || [[ "$CMUX_CODEX_HOOKS_ENABLED" = "1" ]]; then
  export AUTOPILOT_KEEP_RUNNING_DISABLED="${AUTOPILOT_KEEP_RUNNING_DISABLED:-0}"
else
  export AUTOPILOT_KEEP_RUNNING_DISABLED="1"
fi

printf '%s' "$HOOK_INPUT" | bash "$AUTOPILOT_ROOT/hooks/cmux-autopilot-stop-core.sh"
