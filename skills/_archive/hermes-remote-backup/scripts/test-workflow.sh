#!/bin/bash
# =============================================================================
# test-workflow.sh — End-to-end backup/restore test orchestrator
# =============================================================================
# Tests the hermes-remote-backup restore workflow on a devsh VM or SSH host.
# Does NOT modify production scripts. For testing/debugging skill compatibility.
#
# Usage:
#   # Test restore on an existing stopped pve-lxc VM
#   bash test-workflow.sh --devsh --archive ~/Desktop/backups/test/hermes-test.zip
#
#   # Test restore on a specific VM by ID
#   bash test-workflow.sh --devsh --vm-id pvelxc-XXXX --archive ~/Desktop/backups/test/hermes-test.zip
#
#   # Test restore on an SSH host (sg02)
#   bash test-workflow.sh --host sg02 --archive ~/Desktop/backups/test/hermes-test.zip
#
#   # Create a brand new devsh VM, test, then delete
#   bash test-workflow.sh --devsh --create --delete --archive ~/Desktop/backups/test/hermes-test.zip
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE=""
MODE=""
HOST=""
VM_ID=""
CREATE_VM=false
DELETE_VM=false
KEEP_VM=false
SKIP_PREINSPECT=false
SKIP_VALIDATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) MODE="ssh"; HOST="$2"; shift 2 ;;
    --devsh) MODE="devsh"; shift ;;
    --vm-id) VM_ID="$2"; shift 2 ;;
    --archive) ARCHIVE="$2"; shift 2 ;;
    --create) CREATE_VM=true; shift ;;
    --delete) DELETE_VM=true; shift ;;
    --keep) KEEP_VM=true; shift ;;
    --skip-preinspect) SKIP_PREINSPECT=true; shift ;;
    --skip-validate) SKIP_VALIDATE=true; shift ;;
    --help|-h)
      echo "Usage: test-workflow.sh --devsh|--host <host> --archive <zip> [options]"
      echo ""
      echo "Modes:"
      echo "  --host <host>        Test on SSH host (uses scp + ssh)"
      echo "  --devsh              Test on devsh VM (uses devsh exec + HTTP transfer)"
      echo ""
      echo "Required:"
      echo "  --archive <path>     Path to hermes backup zip for testing"
      echo ""
      echo "VM options:"
      echo "  --vm-id <id>         Use specific VM (create/resume as needed)"
      echo "  --create             Create a new devsh VM (requires PVE_API_URL/PVE_API_TOKEN)"
      echo "  --delete             Delete the VM after test"
      echo "  --keep               Keep VM paused after test (default for existing VMs)"
      echo ""
      echo "Skip options:"
      echo "  --skip-preinspect    Skip pre-inspection step"
      echo "  --skip-validate      Skip post-restore validation step"
      echo ""
      echo "Examples:"
      echo "  bash test-workflow.sh --host sg02 --archive ~/Desktop/backups/test/test.zip"
      echo "  bash test-workflow.sh --devsh --archive ~/Desktop/backups/test/test.zip"
      echo "  bash test-workflow.sh --devsh --create --delete --archive test.zip"
      exit 0 ;;
    *) echo "ERROR: Unknown option $1" >&2; exit 1 ;;
  esac
done

# ── Preflight ────────────────────────────────────────────────────────────────

[ -z "$MODE" ] && { echo "ERROR: --host <host> or --devsh required" >&2; exit 1; }
[ -z "$ARCHIVE" ] && { echo "ERROR: --archive <path> required" >&2; exit 1; }
[ ! -f "$ARCHIVE" ] && { echo "ERROR: Archive not found: $ARCHIVE" >&2; exit 1; }

ARCHIVE_NAME=$(basename "$ARCHIVE")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=============================="
echo "Hermes Restore Test Workflow"
echo "=============================="
echo "  Mode:    $MODE"
echo "  Archive: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
[ -n "$HOST" ] && echo "  Host:    $HOST"
[ -n "$VM_ID" ] && echo "  VM:      $VM_ID"
echo ""

# ── Step 0: VM lifecycle (devsh mode) ───────────────────────────────────────

if [ "$MODE" = "devsh" ]; then
  if [ -z "$VM_ID" ]; then
    if [ "$CREATE_VM" = true ]; then
      echo "--- Step 0: Creating new devsh VM ---"
      # devsh start outputs plain text, not JSON. Parse ID from output.
      CREATE_OUTPUT=$(devsh start -p pve-lxc 2>&1) || {
        echo "ERROR: Failed to create devsh VM: $CREATE_OUTPUT" >&2
        exit 1
      }
      VM_ID=$(echo "$CREATE_OUTPUT" | grep -oE 'pvelxc-[a-f0-9]+' | head -1)
      if [ -z "$VM_ID" ]; then
        echo "ERROR: Could not parse VM ID from: $CREATE_OUTPUT" >&2
        exit 1
      fi
      echo "  Created VM: $VM_ID"
    else
      # Find the first stopped pve-lxc VM
      VM_ID=$(devsh ls 2>/dev/null | awk '/pvelxc-/ && $2 == "stopped" {print $1; exit}' || echo "")
      [ -z "$VM_ID" ] && { echo "ERROR: No stopped pve-lxc VM found. Use --vm-id or --create" >&2; exit 1; }
      echo "  Using existing VM: $VM_ID"
    fi
    echo ""
  fi

  echo "--- Step 0: Resuming VM ---"
  devsh resume "$VM_ID" 2>/dev/null || {
    echo "ERROR: Failed to resume VM $VM_ID" >&2
    exit 1
  }
  echo "  VM resumed"
  echo ""

  _devsh() { devsh exec "$VM_ID" "$1" 2>&1; }
  _devsh_skipable() { devsh exec "$VM_ID" "$1" 2>&1 || true; }

  # Determine MAC IP for HTTP transfer
  MAC_IP=$(ipconfig getifaddr en1 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
  [ -z "$MAC_IP" ] && { echo "ERROR: Cannot determine macOS local IP for HTTP transfer" >&2; exit 1; }
fi

if [ "$MODE" = "ssh" ]; then
  _ssh() { ssh -o ConnectTimeout=10 -o BatchMode=yes "$HOST" "$1" 2>&1; }
  _ssh_skipable() { ssh -o ConnectTimeout=10 -o BatchMode=yes "$HOST" "$1" 2>&1 || true; }
fi

# ── Step 1: Pre-inspection ──────────────────────────────────────────────────

if [ "$SKIP_PREINSPECT" = false ]; then
  echo "--- Step 1: Pre-inspection ---"
  PREINSPECT_ARGS="--json-only"
  if [ "$MODE" = "ssh" ]; then
    PREINSPECT_ARGS="$PREINSPECT_ARGS --mode ssh --host $HOST"
  else
    PREINSPECT_ARGS="$PREINSPECT_ARGS --mode devsh --vm-id $VM_ID"
  fi
  bash "$SCRIPT_DIR/pre-inspect.sh" $PREINSPECT_ARGS 2>&1 || true
  echo ""
fi

# ── Step 2: Install Hermes if needed ────────────────────────────────────────

echo "--- Step 2: Install Hermes (if needed) ---"
if [ "$MODE" = "devsh" ]; then
  HERMES_OK=$(_devsh_skipable "hermes --version >/dev/null 2>&1 && printf ok || printf not_found")
else
  HERMES_OK=$(_ssh_skipable "hermes --version >/dev/null 2>&1 && printf ok || printf not_found")
fi

if [ "$HERMES_OK" = "ok" ]; then
  echo "  Hermes already installed"
else
  echo "  Installing Hermes via official install script..."
  if [ "$MODE" = "devsh" ]; then
    _devsh "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash" 2>&1 | tail -3
  else
    _ssh "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash" 2>&1 | tail -3
  fi
  echo "  Hermes install attempted"
fi
echo ""

# ── Step 3: Transfer backup ─────────────────────────────────────────────────

echo "--- Step 3: Transfer backup ---"
if [ "$MODE" = "ssh" ]; then
  REMOTE_PATH="/tmp/hermes-test-${TIMESTAMP}.zip"
  scp "$ARCHIVE" "$HOST:$REMOTE_PATH" 2>/dev/null
  echo "  Transferred via SCP to $HOST:$REMOTE_PATH"
elif [ "$MODE" = "devsh" ]; then
  # HTTP serve from macOS
  ARCHIVE_DIR="$(cd "$(dirname "$ARCHIVE")" && pwd)"
  ARCHIVE_FILE="$(basename "$ARCHIVE")"
  REMOTE_PATH="/tmp/hermes-test-${TIMESTAMP}.zip"

  cd "$ARCHIVE_DIR"
  python3 -m http.server 19999 &
  HTTP_PID=$!
  trap "kill $HTTP_PID 2>/dev/null || true" EXIT

  # Wait for HTTP server to be ready (up to 5s)
  echo "  Waiting for HTTP server on port 19999..."
  for i in $(seq 1 25); do
    curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:19999/${ARCHIVE_FILE}" 2>/dev/null && break
    sleep 0.2
  done

  _devsh "curl -s -o '$REMOTE_PATH' --connect-timeout 10 http://${MAC_IP}:19999/${ARCHIVE_FILE}"
  echo "  Transferred via HTTP serve (macOS:19999) to VM:$REMOTE_PATH"

  # Verify transfer
  SIZE_REMOTE=$(_devsh_skipable "stat -c%s '$REMOTE_PATH' 2>/dev/null || stat -f%z '$REMOTE_PATH' 2>/dev/null || echo 0")
  SIZE_LOCAL=$(stat -f%z "$ARCHIVE" 2>/dev/null || stat -c%s "$ARCHIVE" 2>/dev/null || echo 0)
  if [ "$SIZE_REMOTE" != "$SIZE_LOCAL" ] || [ "$SIZE_REMOTE" = "0" ]; then
    echo "ERROR: Transfer size mismatch (local=$SIZE_LOCAL remote=$SIZE_REMOTE)" >&2
    kill $HTTP_PID 2>/dev/null || true
    exit 1
  fi
  echo "  Transfer verified: $SIZE_REMOTE bytes"
fi
echo ""

# ── Step 4: Stop services before restore ────────────────────────────────────

echo "--- Step 4: Stop services ---"
if [ "$MODE" = "ssh" ]; then
  _ssh_skipable "systemctl --user stop hermes-gateway.service 2>/dev/null || true"
  _ssh_skipable "sudo systemctl stop hermes-dashboard.service 2>/dev/null || true"
  echo "  Services stopped (ssh)"
else
  _devsh_skipable "pkill -f 'hermes.*gateway' 2>/dev/null || true"
  _devsh_skipable "systemctl stop hermes-dashboard.service 2>/dev/null || true"
  echo "  Gateway processes stopped (devsh)"
fi
echo ""

# ── Step 5: Restore ─────────────────────────────────────────────────────────

echo "--- Step 5: hermes import ---"
if [ "$MODE" = "ssh" ]; then
  _ssh "hermes import --force '$REMOTE_PATH'" 2>&1 || {
    echo "ERROR: hermes import failed on $HOST" >&2
    _ssh "rm -f '$REMOTE_PATH'" 2>/dev/null || true
    exit 1
  }
  _ssh "rm -f '$REMOTE_PATH'"
else
  _devsh "hermes import --force '$REMOTE_PATH'" 2>&1 || {
    echo "ERROR: hermes import failed in VM $VM_ID" >&2
    _devsh "rm -f '$REMOTE_PATH'" 2>/dev/null || true
    exit 1
  }
  _devsh "rm -f '$REMOTE_PATH'"
fi
echo "  Restore completed"
echo ""

if [ "$MODE" = "devsh" ]; then
  kill $HTTP_PID 2>/dev/null || true
  trap "" EXIT
fi

# ── Step 6: Validate ────────────────────────────────────────────────────────

if [ "$SKIP_VALIDATE" = false ]; then
  echo "--- Step 6: Post-restore validation ---"
  VALIDATE_ARGS=""
  if [ "$MODE" = "ssh" ]; then
    VALIDATE_ARGS="--mode ssh --host $HOST"
  else
    VALIDATE_ARGS="--mode devsh --vm-id $VM_ID"
  fi
  bash "$SCRIPT_DIR/restore-validate.sh" $VALIDATE_ARGS 2>&1 || true
  VALIDATE_STATUS=$?
  echo ""
fi

# ── Step 7: Cleanup ─────────────────────────────────────────────────────────

echo "--- Step 7: Cleanup ---"
if [ "$MODE" = "devsh" ]; then
  if [ "${DELETE_VM:-false}" = true ]; then
    echo "  Deleting VM $VM_ID..."
    devsh delete "$VM_ID" 2>/dev/null || true
  elif [ "${KEEP_VM:-false}" = false ]; then
    echo "  Pausing VM $VM_ID..."
    devsh pause "$VM_ID" 2>/dev/null || true
  else
    echo "  Keeping VM $VM_ID as requested"
  fi
fi
echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=============================="
echo "Test Workflow Complete"
echo "=============================="
echo "  Mode:    $MODE"
echo "  Target:  ${HOST:-$VM_ID}"
echo "  Archive: $ARCHIVE"

if [ "${SKIP_VALIDATE:-false}" = false ]; then
  if [ "${VALIDATE_STATUS:-1}" -eq 0 ]; then
    echo "  Result:  ✅ ALL CHECKS PASSED"
    echo ""
    echo "The restore workflow is working correctly on this target."
    exit 0
  else
    echo "  Result:  ❌ VALIDATION FAILED ($VALIDATE_STATUS checks failed)"
    echo ""
    echo "Review the failed checks above. Common issues:"
    echo "  - Gateway not started (run hermes gateway --replace --accept-hooks &)"
    echo "  - API key not set in .env"
    echo "  - Backup was created with different Hermes version"
    exit "$VALIDATE_STATUS"
  fi
else
  echo "  Result:  Restore completed (validation skipped)"
  exit 0
fi
