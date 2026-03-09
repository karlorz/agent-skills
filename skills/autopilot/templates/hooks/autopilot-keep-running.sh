#!/bin/bash
# Stop hook that keeps Claude running in autopilot mode
# Blocks Stop event unless turn limit reached or stop file exists

set -euo pipefail

# Disable override: AUTOPILOT_KEEP_RUNNING_DISABLED=1 disables autopilot
if [ "${AUTOPILOT_KEEP_RUNNING_DISABLED:-}" = "1" ]; then
  exit 0
fi

# Autopilot is enabled by default when this hook is installed
# Note: CLAUDE_AUTOPILOT is set internally by Claude Code, don't use it

# Read hook stdin JSON
INPUT=$(cat)

# Parse session_id for session-scoped files
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID="${SESSION_ID:-default}"

# Note: we intentionally do NOT check stop_hook_active here. Autopilot is the
# first hook in the chain, so stop_hook_active=true can only mean Claude Code
# is signaling from a PREVIOUS stop event. Yielding on that would limit
# autopilot to ~1 effective block per cycle. MAX_TURNS provides sufficient
# loop protection instead.

# Helper: clean up the blocked flag so downstream hooks know autopilot is done
cleanup_blocked_flag() {
  rm -f "/tmp/claude-autopilot-blocked-${SESSION_ID}"
}

# Clean up any stale completed marker from a previous cycle where codex-review
# may not have run (e.g. hook disabled, timeout, or process killed).
rm -f "/tmp/claude-autopilot-completed-${SESSION_ID}"

# Session-scoped stop file (from hook input session_id)
SESSION_STOP_FILE="/tmp/claude-autopilot-stop-${SESSION_ID}"
if [ -f "$SESSION_STOP_FILE" ]; then
  rm -f "$SESSION_STOP_FILE"
  cleanup_blocked_flag
  echo "Autopilot stop file detected for session ${SESSION_ID}" >&2
  exit 0
fi

# Also check stop file for current-session-id (fallback for /autopilot_reset skill)
# This handles mismatch when skill writes stop file using /tmp/claude-current-session-id
# but hook receives different session_id in stdin JSON
CURRENT_SID_FILE="/tmp/claude-current-session-id"
if [ -f "$CURRENT_SID_FILE" ]; then
  CURRENT_SID=$(tr -d '\n' < "$CURRENT_SID_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_SID" ] && [ "$CURRENT_SID" != "$SESSION_ID" ]; then
    CURRENT_STOP_FILE="/tmp/claude-autopilot-stop-${CURRENT_SID}"
    if [ -f "$CURRENT_STOP_FILE" ]; then
      rm -f "$CURRENT_STOP_FILE"
      # Clean up blocked flags for BOTH session IDs to avoid stale flags
      cleanup_blocked_flag
      rm -f "/tmp/claude-autopilot-blocked-${CURRENT_SID}"
      echo "Autopilot stop file detected for current-session ${CURRENT_SID}" >&2
      exit 0
    fi
  fi
fi

# External stop file (for agent-autopilot.sh integration)
if [ -n "${CLAUDE_AUTOPILOT_STOP_FILE:-}" ] && [ -f "$CLAUDE_AUTOPILOT_STOP_FILE" ]; then
  cleanup_blocked_flag
  echo "Autopilot external stop file detected: $CLAUDE_AUTOPILOT_STOP_FILE" >&2
  exit 0
fi

# Session-scoped turn counter
TURN_FILE="/tmp/claude-autopilot-turns-${SESSION_ID}"
MAX_TURNS="${CLAUDE_AUTOPILOT_MAX_TURNS:-20}"

# Helper: check if running in infinite mode (MAX_TURNS=-1)
# Note: We use -1 (not 0) as the sentinel because agent-autopilot.sh can produce
# MAX_TURNS=0 for short sessions (MINUTES < TURN_MINUTES), which should stop immediately.
is_infinite_mode() { [ "$MAX_TURNS" -eq -1 ]; }

TURN_COUNT=0
if [ -f "$TURN_FILE" ]; then
  TURN_COUNT=$(cat "$TURN_FILE" 2>/dev/null || echo "0")
fi
TURN_COUNT=$((TURN_COUNT + 1))
echo "$TURN_COUNT" > "$TURN_FILE"

# Check turn limit
if ! is_infinite_mode && [ "$TURN_COUNT" -ge "$MAX_TURNS" ]; then
  # Write completed marker before deleting turn file so codex-review can detect autopilot ran
  echo "$TURN_COUNT" > "/tmp/claude-autopilot-completed-${SESSION_ID}"
  rm -f "$TURN_FILE"
  cleanup_blocked_flag
  echo "Autopilot max turns reached ($MAX_TURNS) for session ${SESSION_ID}" >&2
  exit 0
fi

# Smart delay escalation: early turns are fast (active work), later turns slow down
# (monitoring/polling phase). Infinite mode (MAX_TURNS=-1) always stays in the
# active work phase. The hook delay stays within the 10s timeout; for longer
# waits, we instruct Claude to sleep in a bash command so the wait is visible to the user.
MONITORING_THRESHOLD="${CLAUDE_AUTOPILOT_MONITORING_THRESHOLD:-10}"
MONITORING_PHASE1_OFFSET=5
MONITORING_PHASE1_WAIT=30
MONITORING_PHASE2_WAIT=60
BASE_DELAY="${CLAUDE_AUTOPILOT_DELAY:-2}"
WAIT_PROMPT_PREFIX="Only if you are blocked on external work and are about to poll status, run: sleep"
DELAY_SECONDS="$BASE_DELAY"
WAIT_INSTRUCTION=""
WAIT_SECONDS=""
PHASE="work"

if ! is_infinite_mode && [ "$TURN_COUNT" -gt "$MONITORING_THRESHOLD" ]; then
  if [ "$TURN_COUNT" -le $(( MONITORING_THRESHOLD + MONITORING_PHASE1_OFFSET )) ]; then
    # Monitoring phase 1: medium polling
    WAIT_SECONDS="$MONITORING_PHASE1_WAIT"
    PHASE="monitoring-${MONITORING_PHASE1_WAIT}s"
  else
    # Monitoring phase 2: slow polling for long-running tasks
    WAIT_SECONDS="$MONITORING_PHASE2_WAIT"
    PHASE="monitoring-${MONITORING_PHASE2_WAIT}s"
  fi
fi

if [ -n "$WAIT_SECONDS" ]; then
  WAIT_INSTRUCTION="$WAIT_PROMPT_PREFIX $WAIT_SECONDS"
fi

# At n-2 turns before max, allow codex-review to run by NOT writing the blocked file.
# This gives Claude 2 remaining turns to address any code review findings.
AUTOPILOT_BLOCKED_FILE="/tmp/claude-autopilot-blocked-${SESSION_ID}"
REVIEW_TURN=$((MAX_TURNS - 2))
REVIEW_ENABLED=0
if ! is_infinite_mode && [ "$TURN_COUNT" -eq "$REVIEW_TURN" ] && [ "$MAX_TURNS" -gt 2 ]; then
  REVIEW_ENABLED=1
  # Remove stale blocked flag so codex-review can run
  rm -f "$AUTOPILOT_BLOCKED_FILE"
  echo "[Autopilot] Code review enabled at turn $TURN_COUNT/$MAX_TURNS (n-2)" >&2
else
  # Signal to downstream hooks (codex-review) that autopilot is blocking this stop
  # IMPORTANT: Write this BEFORE the sleep to avoid race condition where parallel
  # hooks (codex-review) start before the flag exists.
  echo "$TURN_COUNT" > "$AUTOPILOT_BLOCKED_FILE"
fi

if [ "$DELAY_SECONDS" -gt 0 ]; then
  sleep "$DELAY_SECONDS"
fi

# Block stop - output JSON decision to stdout
if is_infinite_mode; then
  TURN_STATUS="${TURN_COUNT}/∞"
else
  TURN_STATUS="${TURN_COUNT}/${MAX_TURNS}"
fi

echo "[Autopilot] Turn $TURN_STATUS ($PHASE) - continuing..." >&2

if [ "$REVIEW_ENABLED" = "1" ]; then
  REASON="Code review is running. After review feedback, address any issues found. You have 2 turns remaining."
else
  REASON="Continue from where you left off. Do not ask whether to continue."
fi

if [ -n "$WAIT_INSTRUCTION" ]; then
  REASON="${REASON}\\n${WAIT_INSTRUCTION}"
fi

REASON="${REASON}\\nEnd with: Progress, Commands run, Files changed, Next."

printf '{"decision":"block","reason":"%s"}\n' "$REASON"
exit 0
