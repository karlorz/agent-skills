#!/bin/bash
# =============================================================================
# restore-validate.sh — Post-restore validation (SSH or devsh exec)
# =============================================================================
# Usage:
#   bash restore-validate.sh --mode ssh --host sg02
#   bash restore-validate.sh --mode devsh --vm-id pvelxc-XXXX
#   bash restore-validate.sh --mode ssh --host sg02 --json-only
# =============================================================================

set -euo pipefail

MODE=""
HOST=""
VM_ID=""
JSON_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --vm-id) VM_ID="$2"; shift 2 ;;
    --json-only) JSON_ONLY=true; shift ;;
    --help|-h)
      echo "Usage: restore-validate.sh --mode ssh|devsh --host <host>|--vm-id <id> [--json-only]"
      exit 0 ;;
    *) echo "ERROR: Unknown option $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  ssh)
    [ -z "$HOST" ] && { echo "ERROR: --host required for ssh mode" >&2; exit 1; }
    ;;
  devsh)
    [ -z "$VM_ID" ] && { echo "ERROR: --vm-id required for devsh mode" >&2; exit 1; }
    ;;
  "")
    echo "ERROR: --mode ssh|devsh is required" >&2; exit 1 ;;
  *)
    echo "ERROR: --mode must be ssh or devsh" >&2; exit 1 ;;
esac

_run() {
  local rc=0
  local out
  if [ "$MODE" = "ssh" ]; then
    out=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$HOST" "$1" 2>&1) || rc=$?
  else
    out=$(devsh exec "$VM_ID" "$1" 2>&1) || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: command failed (exit $rc)${out:+: $out}" >&2
    return "$rc"
  fi
  echo "$out"
}

PASS=0
FAIL=0
WARN=0

check() {
  local desc="$1" label="$2"
  shift 2
  local out rc=0
  # Use "$@" directly (NOT eval) to preserve argument quoting
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    [ "$JSON_ONLY" = false ] && echo "  ✅ $desc"
    return 0
  else
    FAIL=$((FAIL + 1))
    if [ "$JSON_ONLY" = false ]; then
      echo "  ❌ $desc"
      # Show first 3 lines of error output (indented for readability)
      echo "$out" | head -3 | sed 's/^/       | /'
    fi
    return "$rc"
  fi
}

echo "=== Restore Validation ==="
echo "  Mode: $MODE"
[ -n "$HOST" ] && echo "  Host: $HOST"
[ -n "$VM_ID" ] && echo "  VM:   $VM_ID"
echo ""

# 1. Hermes CLI works
check "hermes --version" "cli_works" _run "hermes --version"

# 2. hermes doctor (no critical errors)
check "hermes doctor (no critical)" "doctor_ok" \
  _run "hermes doctor >/dev/null 2>&1"

# 3. State DB exists (warn-only — fresh installs won't have one)
_state_db_ok() {
  local out
  out=$(_run "test -f ~/.hermes/state.db && test -s ~/.hermes/state.db" 2>&1) && return 0
  return 1
}
if _state_db_ok; then
  PASS=$((PASS + 1))
  [ "$JSON_ONLY" = false ] && echo "  ✅ state.db exists and non-empty"
else
  WARN=$((WARN + 1))
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  state.db: not found (expected on fresh installs without sessions)"
fi

# 4. Config exists
check "config.yaml exists" "config_exists" \
  _run "test -f ~/.hermes/config.yaml"

# 5. .env exists
check ".env exists" "env_exists" \
  _run "test -f ~/.hermes/.env"

# 6. Skills directory non-empty
check "skills directory non-empty" "skills_exist" \
  _run "ls ~/.hermes/skills/ 2>/dev/null | head -1 | grep -q ."

# 7. Cron jobs.json (warn-only — fresh installs won't have one)
_cron_ok() {
  _run "test -f ~/.hermes/cron/jobs.json" 2>/dev/null && return 0
  return 1
}
if _cron_ok; then
  PASS=$((PASS + 1))
  [ "$JSON_ONLY" = false ] && echo "  ✅ cron/jobs.json exists"
else
  WARN=$((WARN + 1))
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  cron/jobs.json: not found (expected on fresh installs)"
fi

# 8. Health endpoint (warn-only — gateway not started after import)
_health_ok() {
  _run "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:8642/health 2>/dev/null | grep -q 200" 2>/dev/null && return 0
  return 1
}
if _health_ok; then
  PASS=$((PASS + 1))
  [ "$JSON_ONLY" = false ] && echo "  ✅ health endpoint (localhost:8642/health)"
else
  WARN=$((WARN + 1))
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  health endpoint: not responding (start gateway: hermes gateway --replace --accept-hooks &)"
fi

# 9. Gateway is running (warn-only — same reason)
_gw_ok() {
  _run "curl -s --connect-timeout 3 http://127.0.0.1:8642/health 2>/dev/null | grep -qiE '(ok|healthy|true)' || pgrep -f 'hermes.*gateway' 2>/dev/null | head -1 | grep -q ." 2>/dev/null && return 0
  return 1
}
if _gw_ok; then
  PASS=$((PASS + 1))
  [ "$JSON_ONLY" = false ] && echo "  ✅ hermes gateway is running"
else
  WARN=$((WARN + 1))
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  hermes gateway: not running (start manually after restore)"
fi

# 10. API /v1/models endpoint (warn-only — gateway must be running)
_models_ok() {
  _run "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 http://127.0.0.1:8642/v1/models 2>/dev/null | grep -q '^200$'" 2>/dev/null && return 0
  return 1
}
if _models_ok; then
  PASS=$((PASS + 1))
  [ "$JSON_ONLY" = false ] && echo "  ✅ API /v1/models endpoint reachable"
else
  WARN=$((WARN + 1))
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  /v1/models: not reachable (start gateway first)"
fi

# 11. Wiki S3 mount (warn-only — mount failure doesn't mean restore failed)
_wiki_mount_ok() {
  local fstype
  fstype=$(_run "df -T ~/wiki 2>/dev/null | tail -1 | awk '{print \$2}'" 2>/dev/null) || return 1
  [ "$fstype" = "fuse.rclone" ] && return 0 || return 1
}
if _wiki_mount_ok; then
  PASS=$((PASS + 1))
  [ "$JSON_ONLY" = false ] && echo "  ✅ ~/wiki S3 mount: fuse.rclone"
else
  WARN=$((WARN + 1))
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  ~/wiki S3 mount: NOT fuse.rclone (files may silently diverge from S3)"
fi

# 12. Auth file exists (optional — warn-only)
_auth_ok() {
  _run "test -f ~/.hermes/auth.json" 2>/dev/null && return 0
  return 1
}
if _auth_ok; then
  PASS=$((PASS + 1))
  [ "$JSON_ONLY" = false ] && echo "  ✅ auth.json present"
else
  WARN=$((WARN + 1))
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  auth.json: not found (optional — can be re-created)"
fi

# Summary
echo ""
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "=== ✅ ALL $PASS CHECKS PASSED ==="
elif [ "$FAIL" -eq 0 ]; then
  echo "=== ✅ $PASS passed, $WARN warnings ==="
else
  echo "=== $PASS passed, $WARN warnings, $FAIL failed ==="
fi

# JSON output
jq -n \
  --arg mode "$MODE" \
  --arg host "${HOST:-}" \
  --arg vm_id "${VM_ID:-}" \
  --argjson pass "$PASS" \
  --argjson warn "$WARN" \
  --argjson fail "$FAIL" \
  '{
    mode: $mode,
    host: $host,
    vm_id: $vm_id,
    summary: {pass: $pass, warn: $warn, fail: $fail},
    status: (if $fail == 0 then "verified" else "degraded" end)
  }' 2>/dev/null || true

exit $FAIL
