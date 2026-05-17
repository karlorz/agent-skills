#!/bin/bash
# =============================================================================
# pre-inspect.sh — Restore target readiness check (SSH or devsh exec)
# =============================================================================
# Usage:
#   bash pre-inspect.sh --mode ssh --host sg02
#   bash pre-inspect.sh --mode devsh --vm-id pvelxc-XXXX
#   bash pre-inspect.sh --mode ssh --host sg02 --json-only
# =============================================================================

set -euo pipefail

MODE=""
HOST=""
VM_ID=""
JSON_ONLY=false

require_value() {
  local flag="$1"
  if [ $# -lt 2 ] || [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
    echo "ERROR: $flag requires a value" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      require_value "$1" "${2:-}"
      MODE="$2"
      shift 2
      ;;
    --host)
      require_value "$1" "${2:-}"
      HOST="$2"
      shift 2
      ;;
    --vm-id)
      require_value "$1" "${2:-}"
      VM_ID="$2"
      shift 2
      ;;
    --json-only) JSON_ONLY=true; shift ;;
    --help|-h)
      echo "Usage: pre-inspect.sh --mode ssh|devsh --host <host>|--vm-id <id> [--json-only]"
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
    out=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" "$1" 2>&1) || rc=$?
  else
    out=$(devsh exec "$VM_ID" "$1" 2>&1) || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    echo "__ERROR__:$rc:${out}"
    return 0
  fi
  echo "$out"
}

_check_connectivity() {
  local rc=0
  if [ "$MODE" = "ssh" ]; then
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" "hostname" &>/dev/null || rc=$?
  else
    devsh exec "$VM_ID" "hostname" &>/dev/null || rc=$?
  fi
  [ "$rc" -eq 0 ] && echo "ok" || echo "FAIL"
  return "$rc"
}

PASS=0
FAIL=0
WARN=0
RESULTS="[]"

_record() {
  local check="$1" status="$2" value="$3"
  RESULTS=$(echo "$RESULTS" | jq -c \
    --arg check "$check" --arg status "$status" --arg value "$value" \
    '. + [{"check": $check, "status": $status, "value": $value}]' 2>/dev/null || echo "$RESULTS")
  case "$status" in
    pass) PASS=$((PASS + 1)) ;;
    fail) FAIL=$((FAIL + 1)) ;;
    warn) WARN=$((WARN + 1)) ;;
  esac
}

echo "=== Target Pre-Inspection ==="
echo "  Mode: $MODE"
[ -n "$HOST" ] && echo "  Host: $HOST"
[ -n "$VM_ID" ] && echo "  VM:   $VM_ID"
echo ""

# 1. Connectivity
CONN=$(_check_connectivity)
if [ "$CONN" = "ok" ]; then
  _record "connectivity" "pass" "reachable"
  [ "$JSON_ONLY" = false ] && echo "  ✅ Connectivity: reachable"
else
  _record "connectivity" "fail" "unreachable"
  [ "$JSON_ONLY" = false ] && echo "  ❌ Connectivity: UNREACHABLE"
  echo "ERROR: Cannot reach target — aborting." >&2
  echo ""
  echo "$RESULTS" | jq '{summary: {pass: $pass, fail: $fail, warn: $warn}, checks: .}' \
    --argjson pass "$PASS" --argjson fail "$FAIL" --argjson warn "$WARN" 2>/dev/null || echo "$RESULTS"
  exit 1
fi

# 2. Architecture
ARCH=$(_run "uname -m")
case "$ARCH" in
  x86_64|aarch64|arm64)
    _record "architecture" "pass" "$ARCH"
    [ "$JSON_ONLY" = false ] && echo "  ✅ Architecture: $ARCH" ;;
  armv7l|armv6l)
    _record "architecture" "warn" "$ARCH (32-bit ARM)"
    [ "$JSON_ONLY" = false ] && echo "  ⚠️  Architecture: $ARCH (32-bit — Hermes may not work)" ;;
  __ERROR__:*)
    _record "architecture" "fail" "$ARCH"
    [ "$JSON_ONLY" = false ] && echo "  ❌ Architecture: $ARCH" ;;
  *)
    _record "architecture" "warn" "$ARCH (unexpected)"
    [ "$JSON_ONLY" = false ] && echo "  ⚠️  Architecture: $ARCH" ;;
esac

# 3. Python3
PYTHON=$(_run "python3 --version 2>/dev/null || echo 'not_found'")
if echo "$PYTHON" | grep -q "^__ERROR__:"; then
  _record "python3" "fail" "$PYTHON"
  [ "$JSON_ONLY" = false ] && echo "  ❌ Python: probe failed"
elif echo "$PYTHON" | grep -qE "^Python 3\.(1[0-9]|[2-9][0-9])"; then
  _record "python3" "pass" "$PYTHON"
  [ "$JSON_ONLY" = false ] && echo "  ✅ Python: $PYTHON"
elif echo "$PYTHON" | grep -q "^Python"; then
  _record "python3" "fail" "$PYTHON (version too old — need 3.10+)"
  [ "$JSON_ONLY" = false ] && echo "  ❌ Python: $PYTHON (need 3.10+)"
else
  _record "python3" "fail" "not_found"
  [ "$JSON_ONLY" = false ] && echo "  ❌ Python: NOT FOUND"
fi

# 4. curl
CURL=$(_run "curl --version 2>/dev/null | head -1 || echo 'not_found'")
if echo "$CURL" | grep -q "^__ERROR__:"; then
  _record "curl" "fail" "$CURL"
  [ "$JSON_ONLY" = false ] && echo "  ❌ curl: probe failed"
elif echo "$CURL" | grep -q "^curl"; then
  _record "curl" "pass" "$CURL"
  [ "$JSON_ONLY" = false ] && echo "  ✅ curl: $(echo "$CURL" | awk '{print $2}')"
else
  _record "curl" "fail" "not_found"
  [ "$JSON_ONLY" = false ] && echo "  ❌ curl: NOT FOUND (required for Hermes install and file transfer)"
fi

# 5. Disk space
DISK=$(_run "df -h / 2>/dev/null | tail -1 | awk '{print \$4}' || echo 'unknown'")
DISK_GB=$(_run "df / 2>/dev/null | tail -1 | awk '{print \$4}' || echo '0'")
if echo "$DISK_GB" | grep -q "^__ERROR__:"; then
  _record "disk_space" "warn" "probe_failed"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  Disk: probe failed"
elif echo "$DISK_GB" | grep -qxE '[0-9]+'; then
  if [ "$DISK_GB" -lt 5242880 ]; then
    _record "disk_space" "warn" "${DISK} free (<5GB)"
    [ "$JSON_ONLY" = false ] && echo "  ⚠️  Disk: $DISK free (minimum 5GB recommended)"
  else
    _record "disk_space" "pass" "${DISK} free"
    [ "$JSON_ONLY" = false ] && echo "  ✅ Disk: $DISK free"
  fi
else
  _record "disk_space" "warn" "unknown"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  Disk: unknown"
fi

# 6. Memory
MEM=$(_run "free -h 2>/dev/null | grep '^Mem:' | awk '{print \$7}' || echo 'unknown'")
MEM_KB=$(_run "free 2>/dev/null | grep '^Mem:' | awk '{print \$7}' || echo '0'")
if echo "$MEM_KB" | grep -q "^__ERROR__:"; then
  _record "memory" "warn" "probe_failed"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  Memory: probe failed"
elif echo "$MEM_KB" | grep -qxE '[0-9]+'; then
  if [ "$MEM_KB" -lt 2097152 ]; then
    _record "memory" "warn" "${MEM} available (<2GB)"
    [ "$JSON_ONLY" = false ] && echo "  ⚠️  Memory: $MEM available (minimum 2GB recommended)"
  else
    _record "memory" "pass" "${MEM} available"
    [ "$JSON_ONLY" = false ] && echo "  ✅ Memory: $MEM available"
  fi
else
  _record "memory" "warn" "unknown"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  Memory: unknown"
fi

# 7. Wiki S3 mount (fail if not fuse.rclone)
WIKI_FS=$(_run "df -T ~/wiki 2>/dev/null | tail -1 | awk '{print \$2}' || echo 'unknown'")
if [ "$WIKI_FS" = "fuse.rclone" ]; then
  _record "wiki_s3_mount" "pass" "fuse.rclone"
  [ "$JSON_ONLY" = false ] && echo "  ✅ ~/wiki S3 mount: fuse.rclone"
elif [ "$WIKI_FS" = "unknown" ] || echo "$WIKI_FS" | grep -q "^__ERROR__:"; then
  _record "wiki_s3_mount" "warn" "unknown (~/wiki may not exist)"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  ~/wiki: unknown (directory may not exist)"
else
  _record "wiki_s3_mount" "fail" "${WIKI_FS} (expected fuse.rclone)"
  [ "$JSON_ONLY" = false ] && echo "  ❌ ~/wiki S3 mount: ${WIKI_FS} (expected fuse.rclone — files may silently diverge from S3!)"
fi

# 8. Hermes installed
HERMES_VER=$(_run "hermes --version 2>/dev/null || echo 'not_installed'")
if [ "$HERMES_VER" != "not_installed" ] && ! echo "$HERMES_VER" | grep -q "^__ERROR__:"; then
  _record "hermes_installed" "pass" "$HERMES_VER"
  [ "$JSON_ONLY" = false ] && echo "  ✅ Hermes: $HERMES_VER"
else
  _record "hermes_installed" "warn" "not_installed (will need install)"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  Hermes: NOT INSTALLED (will install)"
fi

# 8. systemd (system level)
SYSTEMD=$(_run "systemctl is-system-running 2>/dev/null || echo 'not_found'")
if [ "$SYSTEMD" = "running" ] || [ "$SYSTEMD" = "degraded" ]; then
  _record "systemd_system" "pass" "$SYSTEMD"
  [ "$JSON_ONLY" = false ] && echo "  ✅ systemd (system): $SYSTEMD"
elif [ "$SYSTEMD" = "not_found" ] || echo "$SYSTEMD" | grep -q "^__ERROR__:"; then
  _record "systemd_system" "warn" "not_found (container without systemd)"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  systemd: not found"
else
  _record "systemd_system" "warn" "$SYSTEMD"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  systemd: $SYSTEMD"
fi

# 9. systemd user bus (for --user services)
USER_BUS=$(_run "systemctl --user status 2>&1 | head -1 || echo 'no_bus'")
if echo "$USER_BUS" | grep -q "Failed to connect to bus"; then
  _record "systemd_user_bus" "warn" "no_user_bus (LXC container — use system service)"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  systemd --user: NOT AVAILABLE (use system service instead)"
elif echo "$USER_BUS" | grep -q "^__ERROR__:"; then
  _record "systemd_user_bus" "warn" "probe_failed"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  systemd --user: probe failed"
else
  _record "systemd_user_bus" "pass" "available"
  [ "$JSON_ONLY" = false ] && echo "  ✅ systemd --user: available"
fi

# 10. sudo NOPASSWD
SUDO=$(_run "sudo -n true 2>&1 && echo 'ok' || echo 'needs_password'")
if [ "$SUDO" = "ok" ]; then
  _record "sudo_nopasswd" "pass" "yes"
  [ "$JSON_ONLY" = false ] && echo "  ✅ sudo NOPASSWD: yes"
else
  _record "sudo_nopasswd" "warn" "NOPASSWD_required"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  sudo NOPASSWD: no (may need password for install)"
fi

# 11. OS info
OS=$(_run "cat /etc/os-release 2>/dev/null | grep -E '^(PRETTY_NAME|VERSION_ID)=' | head -2 | tr '\n' ';' || uname -a | head -1")
if echo "$OS" | grep -q "^__ERROR__:"; then
  _record "os" "warn" "probe_failed"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  OS: probe failed"
else
  _record "os" "pass" "$OS"
  [ "$JSON_ONLY" = false ] && echo "  ✅ OS: $(echo "$OS" | sed 's/;.*VERSION_ID=/ /;s/VERSION_ID=//;s/\"//g' | head -c 80)"
fi

# 12. SSH key auth (SSH mode only)
if [ "$MODE" = "ssh" ]; then
  SSH_AUTH=$(_run "echo 'ssh_ok'")
  if [ "$SSH_AUTH" = "ssh_ok" ]; then
    _record "ssh_key_auth" "pass" "configured"
    [ "$JSON_ONLY" = false ] && echo "  ✅ SSH key auth: configured"
  else
    _record "ssh_key_auth" "fail" "not_configured"
    [ "$JSON_ONLY" = false ] && echo "  ❌ SSH key auth: FAILED"
  fi
fi

# 13. Git (required by Hermes installer)
GIT=$(_run "git --version 2>/dev/null || echo 'not_found'")
if echo "$GIT" | grep -q "^git"; then
  _record "git" "pass" "$GIT"
  [ "$JSON_ONLY" = false ] && echo "  ✅ Git: $(echo "$GIT" | awk '{print $3}')"
else
  _record "git" "fail" "not_found"
  [ "$JSON_ONLY" = false ] && echo "  ❌ Git: NOT FOUND (required by Hermes installer)"
fi

# 14. xz-utils (required by Hermes installer for Node.js tarball)
XZ=$(_run "xz --version 2>/dev/null | head -1 || echo 'not_found'")
if echo "$XZ" | grep -q "xz"; then
  _record "xz_utils" "pass" "$XZ"
  [ "$JSON_ONLY" = false ] && echo "  ✅ xz-utils: $(echo "$XZ" | awk '{print $4}')"
else
  _record "xz_utils" "warn" "not_found (may need install for Hermes Node.js setup)"
  [ "$JSON_ONLY" = false ] && echo "  ⚠️  xz-utils: not found (needed for Hermes Node.js install)"
fi

# 15. devsh exec (devsh mode only)
if [ "$MODE" = "devsh" ]; then
  DEVSH_OK=$(_run "echo 'devsh_ok'")
  if [ "$DEVSH_OK" = "devsh_ok" ]; then
    _record "devsh_exec" "pass" "working"
    [ "$JSON_ONLY" = false ] && echo "  ✅ devsh exec: working"
  else
    _record "devsh_exec" "fail" "not_working"
    [ "$JSON_ONLY" = false ] && echo "  ❌ devsh exec: FAILED"
  fi
fi

# Summary
echo ""
echo "=== Summary: $PASS passed, $WARN warnings, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  echo "  ❌ Target has critical issues — review above"
else
  echo "  ✅ Target is ready for restore test"
fi

echo ""
echo "$RESULTS" | jq '{mode: "'"$MODE"'", host: "'"$HOST"'", vm_id: "'"$VM_ID"'", summary: {pass: '"$PASS"', warn: '"$WARN"', fail: '"$FAIL"'}, checks: .}' 2>/dev/null || echo "$RESULTS"

exit $FAIL
