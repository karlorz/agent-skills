#!/bin/bash
# Exports CLAUDE_SESSION_ID to environment for slash commands
# This hook runs on SessionStart and persists the session ID

set -euo pipefail

# Debug logging is opt-in via SESSION_START_DEBUG=1 to avoid writing
# raw hook input to world-readable /tmp.
DEBUG_ENABLED="${SESSION_START_DEBUG:-0}"
DEBUG_LOG="/tmp/claude-session-start-debug.log"

log_debug() {
  if [ "$DEBUG_ENABLED" = "1" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG"
  fi
}

log_debug "=== session-start.sh START ==="

INPUT=$(cat)
log_debug "INPUT: $INPUT"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
log_debug "SESSION_ID: $SESSION_ID"

# Write session ID to a file that slash commands can read
echo "$SESSION_ID" > /tmp/claude-current-session-id
log_debug "Wrote session ID to /tmp/claude-current-session-id"

# Output environment variable for Claude to set
OUTPUT="{\"env\": {\"CLAUDE_SESSION_ID\": \"$SESSION_ID\"}}"
log_debug "OUTPUT: $OUTPUT"
log_debug "=== session-start.sh END ==="

echo "$OUTPUT"
