#!/bin/bash
# ============================================================================
# remote-backup.sh — Remote Hermes backup (macOS → Linux host)
# Part of host-backup-restore/scripts/hermes/ module
# Uses official hermes backup CLI only.
# ============================================================================
# Usage:
#   bash remote-backup.sh <host> [--mode quick|full] [--include-profiles] [--include-systemd] [--include-rclone-config] [--dest <path>] [--retain <N>] [--upload <remote>:<path>]
#
# Examples:
#   bash remote-backup.sh sg01 --mode full
#   bash remote-backup.sh sg01 --mode quick --dest ~/Desktop/backups
#   bash remote-backup.sh sg01 --mode full --include-profiles --include-systemd
#   bash remote-backup.sh sg01 --mode full --retain 7 --upload idrive:hermes-backups/sg01/
# ============================================================================

set -euo pipefail

HOST=""
MODE="full"
INCLUDE_PROFILES=false
INCLUDE_SYSTEMD=false
INCLUDE_RCLONE_CONFIG=false
DEST="$HOME/Desktop/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RETAIN=""
UPLOAD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --include-profiles) INCLUDE_PROFILES=true; shift ;;
    --include-systemd) INCLUDE_SYSTEMD=true; shift ;;
    --include-rclone-config) INCLUDE_RCLONE_CONFIG=true; shift ;;
    --dest) DEST="$2"; shift 2 ;;
    --retain) RETAIN="$2"; shift 2 ;;
    --upload) UPLOAD="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: remote-backup.sh <host> [--mode quick|full] [--include-profiles] [--include-systemd] [--dest <path>]"
      exit 0 ;;
    -*)
      echo "ERROR: Unknown option $1" >&2; exit 1 ;;
    *)
      HOST="$1"; shift ;;
  esac
done

[ -z "$HOST" ] && { echo "ERROR: <host> is required" >&2; exit 1; }
case "$MODE" in
  quick|full) ;;
  *) echo "ERROR: --mode must be quick or full" >&2; exit 1 ;;
esac

# ── Preflight ────────────────────────────────────────────────────────────────

echo "=== Hermes Remote Backup ==="
echo "  Host:  $HOST"
echo "  Mode:  $MODE"
echo "  Dest:  $DEST/$HOST"
echo ""

SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

ssh $SSH_OPTS "$HOST" "hostname" &>/dev/null || {
  echo "ERROR: Cannot SSH to $HOST" >&2; exit 1
}

mkdir -p "$DEST/$HOST"

# ── Phase 1: Official hermes backup ──────────────────────────────────────────

echo "--- Phase 1: hermes backup ---"
REMOTE_ZIP="/tmp/hermes-${TIMESTAMP}.zip"
QUICK_FLAG=""
[ "$MODE" = "quick" ] && QUICK_FLAG="--quick"

ssh $SSH_OPTS "$HOST" "hermes backup -o '$REMOTE_ZIP' $QUICK_FLAG" 2>/dev/null || {
  echo "ERROR: hermes backup failed" >&2; exit 1
}

SCP_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

scp $SCP_OPTS "$HOST:$REMOTE_ZIP" "$DEST/$HOST/hermes-${TIMESTAMP}-${MODE}.zip" 2>/dev/null || {
  echo "ERROR: Failed to transfer backup" >&2; exit 1
}

ssh "$HOST" "rm -f '$REMOTE_ZIP'"
RCVD="$DEST/$HOST/hermes-${TIMESTAMP}-${MODE}.zip"
echo "  Saved: $RCVD ($(du -sh "$RCVD" | cut -f1))"

# ── Phase 2 (optional): Profiles ─────────────────────────────────────────────

if $INCLUDE_PROFILES; then
  echo ""
  echo "--- Phase 2: Profiles ---"
  HERMES_HOME=$(ssh "$HOST" "echo \${HERMES_HOME:-\$HOME/.hermes}" 2>/dev/null)
  HAS_PROFILES=$(ssh "$HOST" "[ -d \"$HERMES_HOME/profiles\" ] && ls \"$HERMES_HOME/profiles/\" 2>/dev/null || echo ''" 2>/dev/null)

  if [ -n "$HAS_PROFILES" ]; then
    ssh "$HOST" "tar czf /tmp/hermes-profiles-${TIMESTAMP}.tar.gz -C \"$HERMES_HOME/profiles\" ." 2>/dev/null
    scp $SCP_OPTS "$HOST:/tmp/hermes-profiles-${TIMESTAMP}.tar.gz" "$DEST/$HOST/hermes-profiles-${TIMESTAMP}.tar.gz" 2>/dev/null
    ssh "$HOST" "rm -f /tmp/hermes-profiles-${TIMESTAMP}.tar.gz"

    PROF_TGZ="$DEST/$HOST/hermes-profiles-${TIMESTAMP}.tar.gz"
    echo "  Saved: $PROF_TGZ ($(du -sh "$PROF_TGZ" | cut -f1))"
    echo "  NOTE: hermes backup does NOT include profiles. Restore via:"
    echo "    ssh $HOST \"tar xzf - -C \$HERMES_HOME/profiles\" < $PROF_TGZ"
  else
    echo "  No profiles found on remote host"
  fi
fi

# ── Phase 3 (optional): Systemd ──────────────────────────────────────────────

if $INCLUDE_SYSTEMD; then
  echo ""
  echo "--- Phase 3: Systemd ---"
  SSH_TMP="/tmp/hermes-systemd-${TIMESTAMP}"
  ssh "$HOST" "
    mkdir -p '$SSH_TMP'
    for svc in /etc/systemd/system/hermes*.service \$HOME/.config/systemd/user/hermes*.service; do
      [ -f \"\$svc\" ] && cp \"\$svc\" '$SSH_TMP/'
    done
  " 2>/dev/null

  FOUND=$(ssh "$HOST" "ls '$SSH_TMP/' 2>/dev/null | wc -l" 2>/dev/null || echo "0")
  if [ "$FOUND" -gt 0 ] 2>/dev/null; then
    ssh "$HOST" "tar czf /tmp/hermes-systemd-${TIMESTAMP}.tar.gz -C '$SSH_TMP' ." 2>/dev/null
    scp $SCP_OPTS "$HOST:/tmp/hermes-systemd-${TIMESTAMP}.tar.gz" "$DEST/$HOST/hermes-systemd-${TIMESTAMP}.tar.gz" 2>/dev/null
    echo "  Saved: $DEST/$HOST/hermes-systemd-${TIMESTAMP}.tar.gz"
    ssh "$HOST" "rm -rf '$SSH_TMP' /tmp/hermes-systemd-${TIMESTAMP}.tar.gz"
  else
    echo "  No hermes systemd services found"
    ssh "$HOST" "rm -rf '$SSH_TMP'"
  fi
fi

# ── Phase 4 (optional): Rclone config ───────────────────────────────────────

if $INCLUDE_RCLONE_CONFIG; then
  echo ""
  echo "--- Phase 4: Rclone config ---"
  RCLONE_CONF=$(ssh "$HOST" "cat ~/.config/rclone/rclone.conf 2>/dev/null || echo NOT_FOUND" 2>/dev/null)
  if [ "$RCLONE_CONF" != "NOT_FOUND" ] && [ -n "$RCLONE_CONF" ]; then
    ssh "$HOST" "cat ~/.config/rclone/rclone.conf" > "$DEST/$HOST/rclone-${TIMESTAMP}.conf" 2>/dev/null
    echo "  Saved: $DEST/$HOST/rclone-${TIMESTAMP}.conf"
  else
    echo "  No rclone config found on remote host"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Backup Complete ==="
echo "  Host: $HOST"
echo "  Mode: $MODE"
echo "  Dest: $DEST/$HOST/"
echo ""

# ── Retention (optional): Prune old backups ─────────────────────────────────

if [ -n "$RETAIN" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  echo "--- Retention: Pruning to $RETAIN sets ---"
  bash "$SCRIPT_DIR/prune-backups.sh" "$DEST" --retain "$RETAIN" || echo "  WARNING: Prune failed (non-fatal)" >&2
  echo ""
fi

# ── Upload (optional): Rclone sync to cloud ─────────────────────────────────

if [ -n "$UPLOAD" ]; then
  echo "--- Upload: Syncing to $UPLOAD ---"
  if command -v rclone &>/dev/null; then
    rclone sync "$DEST/$HOST/" "$UPLOAD" --backup-dir "${UPLOAD%/}/archive" \
      --progress 2>&1 | tail -5 || echo "  WARNING: rclone sync failed (non-fatal)" >&2
    echo "  Synced to: $UPLOAD"
  else
    echo "  WARNING: rclone not found on macOS — install with: brew install rclone"
  fi
  echo ""
fi

echo "  Restore command:"
echo "    scp $RCVD $HOST:/tmp/"
echo "    ssh $HOST \"hermes import --force /tmp/hermes-${TIMESTAMP}-${MODE}.zip\""
echo ""
echo "  WARNING: Archive contains plaintext secrets. Encrypt if storing remotely:"
echo "    gpg --symmetric $RCVD"