#!/usr/bin/env bash
# Post-release: prove a *new process* sees the readiness probe.
# CI uses --dry-run (no Orca). Live: orca terminal in the current worktree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$ROOT/skills/grok-search/scripts/check_readiness.py"
SKILL="$ROOT/skills/grok-search/skills/grok-search/SKILL.md"
MODE="${1:-}"
if [[ -z "$MODE" ]]; then
  if [[ "${GROK_SEARCH_ORCA_LIVE:-}" == "1" ]]; then
    MODE=--live-probe
  else
    MODE=--dry-run
  fi
fi

fail() { printf '%s\n' "$1" >&2; exit 1; }

[[ -f "$PROBE" ]] || fail "missing $PROBE"
[[ -f "$SKILL" ]] || fail "missing $SKILL"
grep -q "check_readiness.py" "$SKILL" || fail "SKILL.md must instruct running check_readiness.py first"

ORCA_BIN="${ORCA_CLI_COMMAND:-orca}"

dry_run() {
  printf 'dry-run orca new-session probe:\n'
  printf '  %s status --json\n' "$ORCA_BIN"
  printf "  %s terminal create --worktree active --title grok-search-readiness --command 'python3 %s --json' --json\n" \
    "$ORCA_BIN" "$PROBE"
  printf '  %s terminal wait --terminal <handle> --for exit --timeout-ms 15000 --json\n' "$ORCA_BIN"
  printf '  %s terminal read --terminal <handle> --json\n' "$ORCA_BIN"
  printf 'test-grok-search-orca-new-session: dry-run ok\n'
}

live_probe() {
  command -v "$ORCA_BIN" >/dev/null || fail "orca CLI not found: $ORCA_BIN"
  local status
  status="$("$ORCA_BIN" status --json 2>/dev/null || true)"
  echo "$status" | python3 -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if d.get("ok") else 1)' \
    || fail "orca status not ok; start Orca or use --dry-run"
  local created handle
  created="$("$ORCA_BIN" terminal create --worktree active --title grok-search-readiness \
    --command "python3 $PROBE --json" --json)"
  handle="$(printf '%s' "$created" | python3 -c 'import json,sys
d=json.load(sys.stdin)
r=d.get("result") or d
term=r.get("terminal") or r.get("startupTerminal") or r
print(term.get("handle") or r.get("handle") or "")')"
  [[ -n "$handle" ]] || fail "orca terminal create returned no handle: $created"
  "$ORCA_BIN" terminal wait --terminal "$handle" --for exit --timeout-ms 15000 --json >/dev/null || true
  local body
  body="$("$ORCA_BIN" terminal read --terminal "$handle" --json)"
  printf '%s' "$body" | python3 -c 'import json,sys,re
raw=sys.stdin.read()
if "missing_prereq" not in raw and "in_sync" not in raw:
    raise SystemExit("orca terminal output missing probe verdict")
'
  printf 'test-grok-search-orca-new-session: live-probe ok handle=%s\n' "$handle"
}

case "$MODE" in
  --dry-run) dry_run ;;
  --live-probe) live_probe ;;
  *) fail "usage: $0 [--dry-run|--live-probe]" ;;
esac
