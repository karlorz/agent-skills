#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$SKILL_DIR/scripts/install-codex-home-hooks.sh"

PASS=0
FAIL=0

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autopilot-codex-home-hooks-smoke-XXXXXX")"
HOME_DIR="$TEST_DIR/home"
WORKSPACE="$TEST_DIR/plain-workspace"
SESSION_ID="codex-home-smoke-$$"
SESSION_WORKSPACE_FILE="/tmp/codex-session-workspace-root-${SESSION_ID}"
CURRENT_SESSION_FILE="/tmp/codex-current-session-id"
CURRENT_WORKSPACE_FILE="/tmp/codex-current-workspace-root"

cleanup() {
  rm -rf "$TEST_DIR"
  rm -f "$CURRENT_SESSION_FILE" "$CURRENT_WORKSPACE_FILE" "$SESSION_WORKSPACE_FILE"
  rm -f "/tmp/codex-autopilot-blocked-${SESSION_ID}"
  rm -f "/tmp/codex-autopilot-completed-${SESSION_ID}"
  rm -f "/tmp/codex-autopilot-idle-${SESSION_ID}"
  rm -f "/tmp/codex-autopilot-pid-${SESSION_ID}"
  rm -f "/tmp/codex-autopilot-state-${SESSION_ID}"
  rm -f "/tmp/codex-autopilot-stop-${SESSION_ID}"
  rm -f "/tmp/codex-autopilot-turns-${SESSION_ID}"
  rm -f "/tmp/codex-autopilot-wrapup-${SESSION_ID}"
}
trap cleanup EXIT

assert() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

mkdir -p "$WORKSPACE"
bash "$INSTALLER" --home "$HOME_DIR" >/dev/null
EXPECTED_WORKSPACE_ROOT="$(cd "$WORKSPACE" && pwd)"

echo "=== bundled codex managed home hooks smoke test ==="

SESSION_PAYLOAD="$(jq -nc \
  --arg cwd "$WORKSPACE" \
  --arg session_id "$SESSION_ID" \
  --arg source "startup" \
  '{
    session_id: $session_id,
    cwd: $cwd,
    source: $source,
    hook_event_name: "SessionStart"
  }')"

SESSION_OUTPUT="$(printf '%s' "$SESSION_PAYLOAD" | HOME="$HOME_DIR" bash "$HOME_DIR/.codex/hooks/managed-session-start.sh")"

assert "session-start falls back to managed home session-start in a plain workspace" grep -Fq "Session source: startup." <<<"$SESSION_OUTPUT"
assert "session-start records the latest global session id" grep -Fxq "$SESSION_ID" "$CURRENT_SESSION_FILE"
assert "session-start records the latest workspace root" grep -Fxq "$EXPECTED_WORKSPACE_ROOT" "$CURRENT_WORKSPACE_FILE"
assert "session-start records the per-session workspace root" grep -Fxq "$EXPECTED_WORKSPACE_ROOT" "$SESSION_WORKSPACE_FILE"

STOP_PAYLOAD="$(jq -nc \
  --arg cwd "$HOME_DIR" \
  --arg session_id "$SESSION_ID" \
  '{
    session_id: $session_id,
    turn_id: "turn-1",
    cwd: $cwd,
    hook_event_name: "Stop",
    stop_hook_active: false,
    last_assistant_message: ""
  }')"

STOP_OUTPUT="$(printf '%s' "$STOP_PAYLOAD" | HOME="$HOME_DIR" \
  CMUX_AUTOPILOT_ENABLED=1 \
  CMUX_CODEX_HOOKS_ENABLED=1 \
  AUTOPILOT_DELAY=0 \
  CMUX_AUTOPILOT_DELAY=0 \
  AUTOPILOT_MONITORING_THRESHOLD=999999 \
  CMUX_AUTOPILOT_MONITORING_THRESHOLD=999999 \
  bash "$HOME_DIR/.codex/hooks/cmux-stop-dispatch.sh")"

assert "stop falls back to the managed home autopilot hook in a plain workspace" jq -e '.decision == "block"' <<<"$STOP_OUTPUT"
assert "stop hook records the first turn for the latest global session" grep -Fxq '1' "/tmp/codex-autopilot-turns-${SESSION_ID}"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
