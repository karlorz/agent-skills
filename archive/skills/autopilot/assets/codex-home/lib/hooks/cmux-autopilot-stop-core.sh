#!/bin/bash
set -euo pipefail

PROVIDER="${CMUX_HOOK_PROVIDER:-generic}"
PROJECT_DIR="${CMUX_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_PREFIX="${CMUX_AUTOPILOT_STATE_PREFIX:-${PROVIDER}-autopilot}"
STATE_DIR="${CMUX_AUTOPILOT_STATE_DIR:-/tmp}"
CURRENT_SESSION_FILE="${CMUX_AUTOPILOT_CURRENT_SESSION_FILE:-/tmp/${PROVIDER}-current-session-id}"
SESSION_ACTIVITY_SCRIPT="${CMUX_SESSION_ACTIVITY_SCRIPT:-}"
INLINE_WRAPUP="${CMUX_AUTOPILOT_INLINE_WRAPUP:-0}"
ENABLE_REVIEW_WINDOW="${CMUX_AUTOPILOT_ENABLE_REVIEW_WINDOW:-0}"

RALPH_MODE="${CMUX_RALPH_MODE:-0}"
RALPH_PROMPT="${CMUX_RALPH_PROMPT:-}"
RALPH_COMPLETION_TAG="${CMUX_RALPH_COMPLETION_TAG:-DONE}"
RALPH_MAX_ITERATIONS="${CMUX_RALPH_MAX_ITERATIONS:-50}"

DEBUG_LOG="${CMUX_AUTOPILOT_DEBUG_LOG:-${STATE_DIR}/${STATE_PREFIX}-debug.log}"
DEBUG_FLAG_FILE="${CMUX_AUTOPILOT_DEBUG_FLAG_FILE:-${STATE_DIR}/${STATE_PREFIX}-debug-enabled}"
DEBUG_INPUT_FILE_TEMPLATE="${CMUX_AUTOPILOT_DEBUG_INPUT_FILE_TEMPLATE:-${STATE_DIR}/${STATE_PREFIX}-last-stop-input-%s.json}"
DEBUG_ENABLED="0"
if [ "${CMUX_AUTOPILOT_DEBUG:-0}" = "1" ] || [ -f "$DEBUG_FLAG_FILE" ]; then
  DEBUG_ENABLED="1"
fi

log_debug() {
  if [ "$DEBUG_ENABLED" = "1" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG"
  fi
}

first_set() {
  local value=""
  for value in "$@"; do
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done

  return 0
}

hash_git_state() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-8
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -c1-8
    return 0
  fi

  echo "missing-hash-tool-$(date +%s)"
}

case "${AUTOPILOT_KEEP_RUNNING_DISABLED:-}" in
  0)
    autopilot_enabled="1"
    ;;
  1)
    log_debug "autopilot disabled via AUTOPILOT_KEEP_RUNNING_DISABLED=1"
    exit 0
    ;;
  "")
    log_debug "autopilot disabled because AUTOPILOT_KEEP_RUNNING_DISABLED is unset"
    exit 0
    ;;
  *)
    log_debug "autopilot disabled because AUTOPILOT_KEEP_RUNNING_DISABLED has unsupported value: ${AUTOPILOT_KEEP_RUNNING_DISABLED}"
    exit 0
    ;;
esac

INPUT=$(cat)
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")"
SESSION_ID="${SESSION_ID:-default}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if [ "$DEBUG_ENABLED" = "1" ]; then
  DEBUG_INPUT_FILE=$(printf "$DEBUG_INPUT_FILE_TEMPLATE" "$SESSION_ID")
  printf '%s\n' "$INPUT" > "$DEBUG_INPUT_FILE"
fi

if [ "$RALPH_MODE" = "1" ]; then
  RALPH_STATE_DIR="${PROJECT_DIR}/.${PROVIDER}"
  mkdir -p "$RALPH_STATE_DIR"
  STATE_DIR="$RALPH_STATE_DIR"
  STATE_PREFIX="ralph-loop"
  log_debug "ralph: using project-local state at $RALPH_STATE_DIR"
fi

TURN_FILE="${STATE_DIR}/${STATE_PREFIX}-turns-${SESSION_ID}"
SESSION_STOP_FILE="${STATE_DIR}/${STATE_PREFIX}-stop-${SESSION_ID}"
BLOCKED_FILE="${STATE_DIR}/${STATE_PREFIX}-blocked-${SESSION_ID}"
COMPLETED_FILE="${STATE_DIR}/${STATE_PREFIX}-completed-${SESSION_ID}"
STATE_FILE="${STATE_DIR}/${STATE_PREFIX}-state-${SESSION_ID}"
IDLE_COUNT_FILE="${STATE_DIR}/${STATE_PREFIX}-idle-${SESSION_ID}"
WRAPUP_FILE="${STATE_DIR}/${STATE_PREFIX}-wrapup-${SESSION_ID}"
PID_FILE="${STATE_DIR}/${STATE_PREFIX}-pid-${SESSION_ID}"
if [ "$RALPH_MODE" = "1" ]; then
  MAX_TURNS="$RALPH_MAX_ITERATIONS"
else
  MAX_TURNS="$(first_set "${AUTOPILOT_MAX_TURNS:-}" "${CMUX_AUTOPILOT_MAX_TURNS:-}" "${CLAUDE_AUTOPILOT_MAX_TURNS:-20}")"
fi
IDLE_THRESHOLD="$(first_set "${AUTOPILOT_IDLE_THRESHOLD:-}" "${CMUX_AUTOPILOT_IDLE_THRESHOLD:-}" "${CLAUDE_AUTOPILOT_IDLE_THRESHOLD:-3}")"
MONITORING_THRESHOLD="$(first_set "${AUTOPILOT_MONITORING_THRESHOLD:-}" "${CMUX_AUTOPILOT_MONITORING_THRESHOLD:-}" "${CLAUDE_AUTOPILOT_MONITORING_THRESHOLD:-10}")"
BASE_DELAY="$(first_set "${AUTOPILOT_DELAY:-}" "${CMUX_AUTOPILOT_DELAY:-}" "${CLAUDE_AUTOPILOT_DELAY:-2}")"
EXTERNAL_STOP_FILE="$(first_set "${AUTOPILOT_STOP_FILE:-}" "${CMUX_AUTOPILOT_STOP_FILE:-}" "${CLAUDE_AUTOPILOT_STOP_FILE:-}")"

MONITORING_PHASE1_OFFSET="$(first_set "${AUTOPILOT_MONITORING_PHASE1_OFFSET:-}" "${CMUX_AUTOPILOT_MONITORING_PHASE1_OFFSET:-}" "${CLAUDE_AUTOPILOT_MONITORING_PHASE1_OFFSET:-5}")"
MONITORING_PHASE1_WAIT="$(first_set "${AUTOPILOT_MONITORING_PHASE1_WAIT:-}" "${CMUX_AUTOPILOT_MONITORING_PHASE1_WAIT:-}" "${CLAUDE_AUTOPILOT_MONITORING_PHASE1_WAIT:-30}")"
MONITORING_PHASE2_WAIT="$(first_set "${AUTOPILOT_MONITORING_PHASE2_WAIT:-}" "${CMUX_AUTOPILOT_MONITORING_PHASE2_WAIT:-}" "${CLAUDE_AUTOPILOT_MONITORING_PHASE2_WAIT:-60}")"
WAIT_PROMPT_PREFIX="Only if you are blocked on external work and are about to poll status, run: sleep"

cleanup_runtime_state() {
  rm -f "$BLOCKED_FILE" "$STATE_FILE" "$IDLE_COUNT_FILE" "$WRAPUP_FILE" "$PID_FILE"

  if [ -n "$SESSION_ACTIVITY_SCRIPT" ] && [ -f "$SESSION_ACTIVITY_SCRIPT" ]; then
    "$SESSION_ACTIVITY_SCRIPT" end "$SESSION_ID" 2>/dev/null || true
  fi
}

remove_owned_stop_files() {
  rm -f "$SESSION_STOP_FILE"

  if [ -n "${ALT_SESSION_STOP_FILE:-}" ]; then
    rm -f "$ALT_SESSION_STOP_FILE"
  fi
}

build_wrapup_reason() {
  cat <<'EOF'
Final turn (wrap up).
Stop starting large new work. Stabilize what you have, run quick checks if sensible, and write a final summary.

Output a "Self-Correction Session Summary" with:
- Completed tasks count
- PRs created (if any), with status
- Key findings (security/perf/tests)
- Remaining tasks (with why)
EOF
}

is_infinite_mode() {
  [ "$MAX_TURNS" -eq -1 ]
}

cleanup_ralph_state() {
  rm -f "$TURN_FILE" "$STATE_FILE" "$IDLE_COUNT_FILE"
  log_debug "ralph: cleaned up state files"
}

report_session_stop_blocked() {
  local reason="$1"
  local source="$2"
  local continuation_prompt="$3"

  if [ -z "${CMUX_CALLBACK_URL:-}" ] || [ -z "${CMUX_TASK_RUN_JWT:-}" ]; then
    log_debug "skip session event: missing CMUX_CALLBACK_URL or CMUX_TASK_RUN_JWT"
    return 0
  fi

  (
    curl -sf -X POST \
      "${CMUX_CALLBACK_URL}/api/autopilot/session-event" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${CMUX_TASK_RUN_JWT}" \
      -d "$(jq -cn \
        --arg eventType "session_stop_blocked" \
        --arg provider "$PROVIDER" \
        --arg reason "$reason" \
        --arg source "$source" \
        --arg continuationPrompt "$continuation_prompt" \
        --arg turnCount "$TURN_COUNT" \
        --arg maxTurns "$MAX_TURNS" \
        '{
          eventType: $eventType,
          provider: $provider,
          reason: $reason,
          source: $source,
          continuationPrompt: $continuationPrompt,
          metadata: {
            turnCount: ($turnCount | tonumber),
            maxTurns: (if $maxTurns == "-1" then -1 else ($maxTurns | tonumber) end),
            ralphMode: (env.RALPH_MODE == "1")
          }
        }')" \
      2>/dev/null || true
  ) &

  log_debug "session_stop_blocked event dispatched (background)"
}

check_ralph_completion() {
  if [ "$RALPH_MODE" != "1" ]; then
    return 1
  fi

  local completion_signal="<promise>${RALPH_COMPLETION_TAG}</promise>"
  local last_message
  last_message="$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")"

  if [ -n "$last_message" ] && echo "$last_message" | grep -qF "$completion_signal"; then
    log_debug "ralph: completion signal detected: $completion_signal"
    return 0
  fi

  return 1
}

cd "$PROJECT_DIR"
log_debug "provider=$PROVIDER project_dir=$PROJECT_DIR session_id=$SESSION_ID"

printf '%s\n' "${CMUX_SESSION_PID:-$PPID}" > "$PID_FILE"

if check_ralph_completion; then
  echo "[Ralph Loop] Completion signal detected, allowing stop" >&2
  cleanup_ralph_state
  exit 0
fi

rm -f "$COMPLETED_FILE"

STOP_REQUESTED=0
STOP_REASON=""
ALT_SESSION_STOP_FILE=""

if [ -f "$SESSION_STOP_FILE" ]; then
  STOP_REQUESTED=1
  STOP_REASON="session-stop"
fi

if [ "$STOP_REQUESTED" -eq 0 ] && [ -f "$CURRENT_SESSION_FILE" ]; then
  CURRENT_SID=$(tr -d '\n' < "$CURRENT_SESSION_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_SID" ] && [ "$CURRENT_SID" != "$SESSION_ID" ]; then
    ALT_SESSION_STOP_FILE="${STATE_DIR}/${STATE_PREFIX}-stop-${CURRENT_SID}"
    if [ -f "$ALT_SESSION_STOP_FILE" ]; then
      STOP_REQUESTED=1
      STOP_REASON="current-session-stop"
    fi
  fi
fi

if [ "$STOP_REQUESTED" -eq 0 ] && [ -n "$EXTERNAL_STOP_FILE" ] && [ -f "$EXTERNAL_STOP_FILE" ]; then
  STOP_REQUESTED=1
  STOP_REASON="external-stop"
fi

WRAPUP_SOURCE=""
if [ -f "$WRAPUP_FILE" ]; then
  WRAPUP_SOURCE=$(cat "$WRAPUP_FILE" 2>/dev/null || echo "")
fi

if [ "$STOP_REQUESTED" -eq 1 ]; then
  if [ "$INLINE_WRAPUP" = "1" ]; then
    if [ -n "$WRAPUP_SOURCE" ]; then
      log_debug "allowing stop after inline wrapup source=$WRAPUP_SOURCE"
      remove_owned_stop_files
      cleanup_runtime_state
      exit 0
    fi

    printf '%s\n' "$STOP_REASON" > "$WRAPUP_FILE"
    WRAPUP_SOURCE="$STOP_REASON"
    log_debug "inline wrapup requested source=$WRAPUP_SOURCE"
  else
    log_debug "allowing stop immediately source=$STOP_REASON"
    remove_owned_stop_files
    cleanup_runtime_state
    exit 0
  fi
elif [ "$INLINE_WRAPUP" = "1" ] && [ "$WRAPUP_SOURCE" = "max-turns" ]; then
  log_debug "allowing stop after max-turn inline wrapup"
  rm -f "$TURN_FILE"
  cleanup_runtime_state
  exit 0
fi

TURN_COUNT=0
if [ -f "$TURN_FILE" ]; then
  TURN_COUNT=$(cat "$TURN_FILE" 2>/dev/null || echo "0")
fi
TURN_COUNT=$((TURN_COUNT + 1))
printf '%s\n' "$TURN_COUNT" > "$TURN_FILE"

if [ -z "$WRAPUP_SOURCE" ]; then
  CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  HAS_UNCOMMITTED=$(git status --porcelain 2>/dev/null | grep -q . && echo "1" || echo "0")
  if [ "$HAS_UNCOMMITTED" = "1" ]; then
    DIRTY_HASH=$({ git diff 2>/dev/null; git diff --cached 2>/dev/null; } | hash_git_state)
  else
    DIRTY_HASH="clean"
  fi
  CURRENT_STATE="${CURRENT_HEAD}:${DIRTY_HASH}"

  PREV_STATE=""
  [ -f "$STATE_FILE" ] && PREV_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "")
  printf '%s\n' "$CURRENT_STATE" > "$STATE_FILE"

  IDLE_COUNT=0
  [ -f "$IDLE_COUNT_FILE" ] && IDLE_COUNT=$(cat "$IDLE_COUNT_FILE" 2>/dev/null || echo "0")

  if [ "$CURRENT_STATE" = "$PREV_STATE" ] && [ -n "$PREV_STATE" ]; then
    IDLE_COUNT=$((IDLE_COUNT + 1))
    printf '%s\n' "$IDLE_COUNT" > "$IDLE_COUNT_FILE"

    if [ "$IDLE_COUNT" -ge "$IDLE_THRESHOLD" ]; then
      echo "[Autopilot] No activity for $IDLE_COUNT turns, allowing stop" >&2
      log_debug "allowing stop after idle threshold"
      rm -f "$TURN_FILE"
      cleanup_runtime_state
      exit 0
    fi
  else
    rm -f "$IDLE_COUNT_FILE"
  fi
fi

if [ -z "$WRAPUP_SOURCE" ] && ! is_infinite_mode && [ "$TURN_COUNT" -ge "$MAX_TURNS" ]; then
  printf '%s\n' "$TURN_COUNT" > "$COMPLETED_FILE"

  if [ "$INLINE_WRAPUP" = "1" ] && [ "$MAX_TURNS" -gt 0 ]; then
    printf '%s\n' "max-turns" > "$WRAPUP_FILE"
    WRAPUP_SOURCE="max-turns"
    log_debug "inline wrapup requested after max turns"
  else
    rm -f "$TURN_FILE"
    cleanup_runtime_state
    echo "Autopilot max turns reached ($MAX_TURNS) for session ${SESSION_ID}" >&2
    exit 0
  fi
fi

WAIT_INSTRUCTION=""
MONITORING_SLEEP_SECONDS=""
PHASE="work"

if [ -z "$WRAPUP_SOURCE" ] && ! is_infinite_mode && [ "$TURN_COUNT" -gt "$MONITORING_THRESHOLD" ]; then
  if [ "$TURN_COUNT" -le $((MONITORING_THRESHOLD + MONITORING_PHASE1_OFFSET)) ]; then
    MONITORING_SLEEP_SECONDS="$MONITORING_PHASE1_WAIT"
    PHASE="monitoring-${MONITORING_PHASE1_WAIT}s"
  else
    MONITORING_SLEEP_SECONDS="$MONITORING_PHASE2_WAIT"
    PHASE="monitoring-${MONITORING_PHASE2_WAIT}s"
  fi
fi

if [ "$PROVIDER" != "codex" ] && [ -n "$MONITORING_SLEEP_SECONDS" ]; then
  WAIT_INSTRUCTION="${WAIT_PROMPT_PREFIX} ${MONITORING_SLEEP_SECONDS}"
fi

REVIEW_ENABLED=0
if [ "$ENABLE_REVIEW_WINDOW" = "1" ] && [ -z "$WRAPUP_SOURCE" ] && ! is_infinite_mode && [ "$MAX_TURNS" -gt 2 ]; then
  REVIEW_TURN=$((MAX_TURNS - 2))
  if [ "$TURN_COUNT" -eq "$REVIEW_TURN" ]; then
    REVIEW_ENABLED=1
    rm -f "$BLOCKED_FILE"
    log_debug "review window opened at turn=$TURN_COUNT"
  fi
fi

if [ "$REVIEW_ENABLED" != "1" ]; then
  printf '%s\n' "$TURN_COUNT" > "$BLOCKED_FILE"
fi

if ! is_infinite_mode && [ "$BASE_DELAY" -gt 0 ]; then
  sleep "$BASE_DELAY"
fi

if [ "$PROVIDER" = "codex" ] && [ -n "$MONITORING_SLEEP_SECONDS" ] && [ "$MONITORING_SLEEP_SECONDS" -gt 0 ]; then
  log_debug "codex monitoring sleep seconds=$MONITORING_SLEEP_SECONDS turn=$TURN_COUNT"
  sleep "$MONITORING_SLEEP_SECONDS"
fi

if is_infinite_mode; then
  TURN_STATUS="${TURN_COUNT}/∞"
else
  TURN_STATUS="${TURN_COUNT}/${MAX_TURNS}"
fi

if [ "$RALPH_MODE" = "1" ]; then
  echo "[Ralph Loop] Iteration $TURN_STATUS - continuing..." >&2
else
  echo "[Autopilot] Turn $TURN_STATUS ($PHASE) - continuing..." >&2
fi

if [ -n "$WRAPUP_SOURCE" ]; then
  REASON="$(build_wrapup_reason)"
elif [ "$RALPH_MODE" = "1" ] && [ -n "$RALPH_PROMPT" ]; then
  REASON="$RALPH_PROMPT

When you have completed the task, output <promise>${RALPH_COMPLETION_TAG}</promise> in your response to signal completion."
elif [ "$REVIEW_ENABLED" = "1" ]; then
  REASON="Code review is running. After review feedback, address any issues found. You have 2 turns remaining."
  if [ -n "$WAIT_INSTRUCTION" ]; then
    REASON="${REASON}
${WAIT_INSTRUCTION}"
  fi
  REASON="${REASON}
End with: Progress, Commands run, Files changed, Next."
else
  REASON="Continue from where you left off. Do not ask whether to continue."
  if [ -n "$WAIT_INSTRUCTION" ]; then
    REASON="${REASON}
${WAIT_INSTRUCTION}"
  fi
  REASON="${REASON}
End with: Progress, Commands run, Files changed, Next."
fi

if [ "$RALPH_MODE" = "1" ]; then
  report_session_stop_blocked "ralph_loop_continuation" "autopilot" "$REASON"
elif [ -n "$WRAPUP_SOURCE" ]; then
  report_session_stop_blocked "wrapup_phase" "autopilot" "$REASON"
else
  report_session_stop_blocked "turn_continuation" "autopilot" "$REASON"
fi

jq -cn --arg reason "$REASON" '{"decision":"block","reason":$reason}'
