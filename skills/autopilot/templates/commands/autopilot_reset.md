---
description: Reset autopilot turn counter to allow session to run fresh
argument-hint: "[optional: stop|status|status-all|all]"
allowed-tools: Bash
---

Reset or control the autopilot turn counter for the current session.

Mode: $ARGUMENTS (default: reset)

## Auto-collected context

### Current session status
!`bash -c 'SID=$(cat /tmp/claude-current-session-id 2>/dev/null); if [ -z "$SID" ]; then echo "Session ID: (not set - restart session to enable)"; exit 0; fi; echo "Session ID: ${SID}"; MAX=${CLAUDE_AUTOPILOT_MAX_TURNS:-20}; echo "Max turns: $MAX"; TURNS_FILE="/tmp/claude-autopilot-turns-${SID}"; if [ -f "$TURNS_FILE" ]; then TURNS=$(cat "$TURNS_FILE"); echo "Current turn: $TURNS"; HAS_RUN=1; else echo "Current turn: 0"; HAS_RUN=0; fi; if [ -f "/tmp/claude-autopilot-stop-$SID" ]; then echo "Status: STOP (will stop on next turn)"; elif [ -f "/tmp/claude-autopilot-blocked-$SID" ]; then echo "Status: BLOCKED (actively running)"; elif [ "$HAS_RUN" = "0" ]; then echo "Status: idle (not started)"; else echo "Status: ready (available)"; fi; exit 0'`

## Actions

Based on mode `$ARGUMENTS`:

### reset (default)
Reset the turn counter to 0, allowing another full cycle of autopilot turns.

### stop
Create a stop file to immediately stop autopilot on next turn.

### status
Show current session ID and status only.

### status-all
Show all active sessions with their status.

## Instructions

1. If mode is `status`: Just report the auto-collected context above, no action needed.

2. If mode is `status-all`: Run this command via Bash tool to show all sessions:
```bash
MAX=${CLAUDE_AUTOPILOT_MAX_TURNS:-20}
CURRENT_SID=$(cat /tmp/claude-current-session-id 2>/dev/null)
echo "Max turns: $MAX"
echo "Current session: ${CURRENT_SID:-"(not set)"}"
echo ""
echo "All active sessions:"
found=0
for f in /tmp/claude-autopilot-turns-*; do
  [ -f "$f" ] || continue
  found=1
  SID="${f#/tmp/claude-autopilot-turns-}"
  TURNS=$(cat "$f")
  FLAGS=""
  [ -f "/tmp/claude-autopilot-stop-$SID" ] && FLAGS="$FLAGS [STOP]"
  [ -f "/tmp/claude-autopilot-blocked-$SID" ] && FLAGS="$FLAGS [BLOCKED]"
  [ "$SID" = "$CURRENT_SID" ] && FLAGS="$FLAGS [CURRENT]"
  echo "  ${SID:0:20}...: turn $TURNS$FLAGS"
done
[ $found -eq 0 ] && echo "  (none)"
exit 0
```

3. If mode is `stop`: Run this command via Bash tool (current session only):
```bash
SID=$(cat /tmp/claude-current-session-id 2>/dev/null)
if [ -z "$SID" ]; then
  echo "No session ID found. Restart session to enable."
  exit 1
fi
touch "/tmp/claude-autopilot-stop-${SID}"
echo "Stop file created for current session: ${SID:0:20}..."
echo "Autopilot will stop on next turn."
```

4. If mode is `reset` or empty: Run this command via Bash tool (current session only):
```bash
SID=$(cat /tmp/claude-current-session-id 2>/dev/null)
MAX_TURNS="${CLAUDE_AUTOPILOT_MAX_TURNS:-20}"
if [ -z "$SID" ]; then
  echo "No session ID found. Restart session to enable."
  exit 1
fi
rm -f "/tmp/claude-autopilot-turns-${SID}" "/tmp/claude-autopilot-stop-${SID}" "/tmp/claude-autopilot-blocked-${SID}"
echo "Reset current session: ${SID:0:20}..."
echo "Next cycle will start from turn 1/$MAX_TURNS"
```

5. If mode is `all`: Run this command via Bash tool (all sessions):
```bash
COUNT=0
MAX_TURNS="${CLAUDE_AUTOPILOT_MAX_TURNS:-20}"
shopt -s nullglob 2>/dev/null || true
for f in /tmp/claude-autopilot-turns-*; do
  [ -f "$f" ] || continue
  SID="${f#/tmp/claude-autopilot-turns-}"
  rm -f "/tmp/claude-autopilot-turns-${SID}" "/tmp/claude-autopilot-stop-${SID}" "/tmp/claude-autopilot-blocked-${SID}"
  echo "Reset: ${SID:0:20}..."
  COUNT=$((COUNT + 1))
done
echo "Reset $COUNT session(s). Next cycle will start from turn 1/$MAX_TURNS"
```

Report the result to the user.
