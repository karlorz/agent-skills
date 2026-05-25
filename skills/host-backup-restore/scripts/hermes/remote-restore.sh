#!/bin/bash
# ============================================================================
# remote-restore.sh — Remote Hermes restore via official hermes import CLI
# Part of host-backup-restore/scripts/hermes/ module
# ============================================================================
# Usage:
#   bash remote-restore.sh <archive> --target <host>
#   bash remote-restore.sh ~/Desktop/backups/sg01/hermes-20260516-full.zip --target sg01
# ============================================================================

set -euo pipefail

ARCHIVE=""
TARGET=""
NON_ROOT_USER=""

require_value() {
  local flag="$1"
  if [ $# -lt 2 ] || [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
    echo "ERROR: $flag requires a value" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      require_value "$1" "${2:-}"
      TARGET="$2"
      shift 2
      ;;
    --non-root-user)
      require_value "$1" "${2:-}"
      NON_ROOT_USER="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: remote-restore.sh <archive> --target <host> [--non-root-user <user>]" >&2
      exit 0 ;;
    -*)
      echo "ERROR: Unknown option $1" >&2; exit 1 ;;
    *)
      ARCHIVE="$1"; shift ;;
  esac
done

[ -z "$ARCHIVE" ] && { echo "ERROR: <archive> is required" >&2; exit 1; }
[ -z "$TARGET" ] && { echo "ERROR: --target <host> is required" >&2; exit 1; }
[ ! -f "$ARCHIVE" ] && { echo "ERROR: Not found: $ARCHIVE" >&2; exit 1; }
if [ -n "$NON_ROOT_USER" ] && ! echo "$NON_ROOT_USER" | grep -qxE '[a-z_][a-z0-9_-]*\$?'; then
  echo "ERROR: Invalid --non-root-user '$NON_ROOT_USER'" >&2
  exit 1
fi

echo "=== Hermes Remote Restore ==="
echo "  Archive: $ARCHIVE"
echo "  Target:  $TARGET"
[ -n "$NON_ROOT_USER" ] && echo "  Non-root user: $NON_ROOT_USER"
echo ""

SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"
CONTROL_PATH="$HOME/.ssh/controlmasters/%r@%h:%p"
mkdir -p "$HOME/.ssh/controlmasters" 2>/dev/null || true
SSH_OPTS="$SSH_OPTS -o ControlMaster=auto -o ControlPath=$CONTROL_PATH -o ControlPersist=10m"

cleanup_ssh() {
  ssh -O exit -o ControlPath="$CONTROL_PATH" "$TARGET" 2>/dev/null || true
}
trap cleanup_ssh EXIT

ssh $SSH_OPTS "$TARGET" "hostname" &>/dev/null || {
  echo "ERROR: Cannot SSH to $TARGET" >&2; exit 1
}

# Transfer and import — rsync for resumable WAN transfer
REMOTE_ZIP="/tmp/hermes-restore-$(basename "$ARCHIVE")"
rsync -avP --partial-dir=.rsync-partial --timeout=300 \
  -e "ssh $SSH_OPTS" \
  "$ARCHIVE" "$TARGET:$REMOTE_ZIP" || {
  echo "ERROR: Failed to transfer archive to $TARGET:$REMOTE_ZIP" >&2
  exit 1
}

# Stop services before restore
echo "  Stopping services..."
ssh $SSH_OPTS "$TARGET" "
  systemctl --user stop hermes-gateway.service 2>/dev/null || true
  sudo systemctl stop hermes-dashboard.service 2>/dev/null || true
" 2>/dev/null

# Import (support non-root targets via HERMES_HOME override)
echo "  Running hermes import..."
if [ -n "$NON_ROOT_USER" ]; then
  # Resolve non-root user's home directory
  USER_HOME=$(ssh $SSH_OPTS "$TARGET" "getent passwd '$NON_ROOT_USER' | cut -d: -f6" 2>/dev/null || echo "/home/$NON_ROOT_USER")
  HERMES_HOME="${USER_HOME}/.hermes"
  echo "  HERMES_HOME=$HERMES_HOME (non-root user: $NON_ROOT_USER)"
  ssh $SSH_OPTS "$TARGET" "HERMES_HOME='$HERMES_HOME' hermes import --force '$REMOTE_ZIP'" 2>&1 || {
    echo "ERROR: hermes import failed" >&2
    ssh $SSH_OPTS "$TARGET" "rm -f '$REMOTE_ZIP'" 2>/dev/null || true
    exit 1
  }
  # Chown imported files to non-root user
  echo "  Setting ownership to $NON_ROOT_USER..."
  ssh $SSH_OPTS "$TARGET" "chown -R '${NON_ROOT_USER}:${NON_ROOT_USER}' '${HERMES_HOME}'" 2>/dev/null || {
    echo "  WARNING: chown failed (non-fatal, may need manual fix)"
  }
else
  ssh $SSH_OPTS "$TARGET" "hermes import --force '$REMOTE_ZIP'" 2>/dev/null || {
    echo "ERROR: hermes import failed" >&2
    echo "  Retry without --force: ssh $TARGET \"hermes import $REMOTE_ZIP\"" >&2
    ssh $SSH_OPTS "$TARGET" "rm -f '$REMOTE_ZIP'" 2>/dev/null || true
    exit 1
  }
fi

# Clean up remote
ssh $SSH_OPTS "$TARGET" "rm -f '$REMOTE_ZIP'"

# Start services
echo "  Starting services..."
ssh $SSH_OPTS "$TARGET" "
  sudo systemctl start hermes-dashboard.service 2>/dev/null || true
  systemctl --user start hermes-gateway.service 2>/dev/null || true
" 2>/dev/null

echo ""
echo "=== Restore Complete ==="
echo "  Target: $TARGET"
echo ""
echo "  Verify:"
echo "    ssh $TARGET \"hermes --version\""
echo "    ssh $TARGET \"systemctl --user status hermes-gateway.service\""
