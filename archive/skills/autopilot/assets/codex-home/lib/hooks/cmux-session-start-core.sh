#!/bin/bash
set -euo pipefail

PROVIDER="${CMUX_HOOK_PROVIDER:-generic}"
PROJECT_DIR="${CMUX_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
OUTPUT_MODE="${CMUX_SESSION_START_OUTPUT_MODE:-text}"
STATE_PREFIX="${CMUX_SESSION_STATE_PREFIX:-${PROVIDER}-autopilot}"
SESSION_FILE="${CMUX_SESSION_FILE:-/tmp/${PROVIDER}-current-session-id}"
SESSION_WORKSPACE_FILE_TEMPLATE="${CMUX_SESSION_WORKSPACE_FILE_TEMPLATE:-${CMUX_CODEX_SESSION_WORKSPACE_FILE_TEMPLATE:-/tmp/${PROVIDER}-session-workspace-root-%s}}"
CURRENT_WORKSPACE_FILE="${CMUX_CURRENT_WORKSPACE_FILE:-${CMUX_CODEX_CURRENT_WORKSPACE_FILE:-/tmp/${PROVIDER}-current-workspace-root}}"
SESSION_ENV_NAME="${CMUX_SESSION_ENV_NAME:-}"
SESSION_ACTIVITY_SCRIPT="${CMUX_SESSION_ACTIVITY_SCRIPT:-}"

DEBUG_ENABLED="${SESSION_START_DEBUG:-0}"
DEBUG_LOG="${CMUX_SESSION_START_DEBUG_LOG:-/tmp/${PROVIDER}-session-start-debug.log}"

log_debug() {
  if [ "$DEBUG_ENABLED" = "1" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG"
  fi
}

session_workspace_file() {
  local session_id="$1"
  printf "$SESSION_WORKSPACE_FILE_TEMPLATE" "$session_id"
}

INPUT=$(cat)
read -r SESSION_ID SOURCE < <(echo "$INPUT" | jq -r '[.session_id // "default", .source // "startup"] | @tsv' 2>/dev/null || echo "default startup")
SESSION_ID="${SESSION_ID:-default}"
PID_FILE="${CMUX_SESSION_PID_FILE:-/tmp/${STATE_PREFIX}-pid-${SESSION_ID}}"
SESSION_PID="${CMUX_SESSION_PID:-$PPID}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
WORKSPACE_FILE="$(session_workspace_file "$SESSION_ID")"

log_debug "provider=$PROVIDER source=$SOURCE session_id=$SESSION_ID"

printf '%s\n' "$SESSION_ID" > "$SESSION_FILE"
log_debug "wrote session file: $SESSION_FILE"

printf '%s\n' "$SESSION_PID" > "$PID_FILE"
log_debug "wrote pid file: $PID_FILE pid=$SESSION_PID"

printf '%s\n' "$PROJECT_DIR" > "$WORKSPACE_FILE"
log_debug "wrote workspace file: $WORKSPACE_FILE root=$PROJECT_DIR"

printf '%s\n' "$PROJECT_DIR" > "$CURRENT_WORKSPACE_FILE"
log_debug "wrote current workspace file: $CURRENT_WORKSPACE_FILE root=$PROJECT_DIR"

if [ -n "$SESSION_ACTIVITY_SCRIPT" ] && [ -f "$SESSION_ACTIVITY_SCRIPT" ]; then
  "$SESSION_ACTIVITY_SCRIPT" start "$SESSION_ID" 2>/dev/null || true
fi

case "$OUTPUT_MODE" in
  claude-env)
    if [ -z "$SESSION_ENV_NAME" ]; then
      echo "CMUX_SESSION_ENV_NAME is required for claude-env mode" >&2
      exit 1
    fi
    jq -cn --arg key "$SESSION_ENV_NAME" --arg value "$SESSION_ID" '{env: {($key): $value}}'
    ;;
  codex-context)
    CONTEXT=$(cat <<EOF
Session source: ${SOURCE}.
Review AGENTS.md and follow repository instructions before making changes.
If this session was launched by cmux autopilot, the Stop hook may continue work automatically and later request a final wrap-up turn.
EOF
)
    jq -cn --arg additionalContext "$CONTEXT" '{additionalContext: $additionalContext}'
    ;;
  text)
    cat <<EOF
Session source: ${SOURCE}.
Review AGENTS.md and follow repository instructions before making changes.
EOF
    ;;
  *)
    echo "Unknown CMUX_SESSION_START_OUTPUT_MODE: $OUTPUT_MODE" >&2
    exit 1
    ;;
esac
