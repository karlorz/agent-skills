#!/usr/bin/env bash
set -euo pipefail

trimmed_non_empty() {
  local value="$1"
  [[ -n "${value//[[:space:]]/}" ]]
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

  if [[ -n "${CODEX_HOME:-}" ]]; then
    hook_path="${CODEX_HOME}/hooks/${hook_name}"
  else
    hook_path="${HOME}/.codex/hooks/${hook_name}"
  fi

  if [[ ! -f "$hook_path" ]]; then
    return 1
  fi

  printf '%s' "$HOOK_INPUT" | bash "$hook_path"
}

HOOK_INPUT="$(cat)"
HOOK_CWD="$(jq -r '.cwd // empty' <<<"$HOOK_INPUT" 2>/dev/null || true)"
read -r SESSION_ID SOURCE < <(jq -r '[.session_id // "default", .source // "startup"] | @tsv' <<<"$HOOK_INPUT" 2>/dev/null || printf 'default\tstartup\n')
SESSION_ID="${SESSION_ID:-default}"
SOURCE="${SOURCE:-startup}"
WORKSPACE_ROOT="$(resolve_workspace_root "$HOOK_CWD")"
WORKSPACE_FILE="$(session_workspace_file "$SESSION_ID")"
CURRENT_FILE="${CMUX_CURRENT_WORKSPACE_FILE:-${CMUX_CODEX_CURRENT_WORKSPACE_FILE:-/tmp/codex-current-workspace-root}}"

printf '%s\n' "$WORKSPACE_ROOT" >"$WORKSPACE_FILE"
printf '%s\n' "$WORKSPACE_ROOT" >"$CURRENT_FILE"

if route_to_workspace_hook "$WORKSPACE_ROOT" ".codex/hooks/session-start.sh"; then
  exit 0
fi

if route_to_home_hook "session-start.sh"; then
  exit 0
fi

cat <<EOF
Session source: ${SOURCE}.
Review AGENTS.md and follow repository instructions before making changes.
EOF
