#!/usr/bin/env bash
set -euo pipefail

emit_allow() {
  jq -nc '{}'
}

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
  local template="${CMUX_CODEX_SESSION_WORKSPACE_FILE_TEMPLATE:-/tmp/codex-session-workspace-root-%s}"

  printf "$template" "$session_id"
}

read_session_workspace_root() {
  local session_id="$1"
  local workspace_file=""
  local candidate=""
  local current_file="${CMUX_CODEX_CURRENT_WORKSPACE_FILE:-/tmp/codex-current-workspace-root}"

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

route_to_workspace_hook() {
  local workspace_root="$1"
  local relative_hook_path="$2"
  local hook_path="${workspace_root}/${relative_hook_path}"

  if [[ ! -f "$hook_path" ]]; then
    return 1
  fi

  printf '%s' "$HOOK_INPUT" | bash "$hook_path"
}

route_to_home_hook() {
  local hook_name="$1"
  local hook_path=""

  hook_path="$(codex_home_dir)/hooks/${hook_name}"
  if [[ ! -f "$hook_path" ]]; then
    return 1
  fi

  printf '%s' "$HOOK_INPUT" | bash "$hook_path"
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

RALPH_STATE_FILE="${WORKSPACE_ROOT}/.codex/ralph-loop-state.json"

if [[ -f "$RALPH_STATE_FILE" ]]; then
  if route_to_workspace_hook "$WORKSPACE_ROOT" ".codex/hooks/ralph-loop-stop.sh"; then
    exit 0
  fi

  if route_to_home_hook "ralph-loop-stop.sh"; then
    exit 0
  fi

  emit_allow
  exit 0
fi

if [[ "${CMUX_AUTOPILOT_ENABLED:-0}" = "1" ]] || [[ "${CMUX_CODEX_HOOKS_ENABLED:-0}" = "1" ]]; then
  if route_to_workspace_hook "$WORKSPACE_ROOT" ".codex/hooks/autopilot-stop.sh"; then
    exit 0
  fi

  if route_to_home_hook "autopilot-stop.sh"; then
    exit 0
  fi

  emit_allow
  exit 0
fi

emit_allow
