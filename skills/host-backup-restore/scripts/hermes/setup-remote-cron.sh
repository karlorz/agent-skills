#!/bin/bash
# ============================================================================
# setup-remote-cron.sh — Install daily Hermes backup cron on remote host
# ============================================================================
# SSHs into the remote host and installs a cron job that runs
# `hermes backup --quick` daily. Optionally adds rclone sync to S3.
#
# This fills the "no routine/scheduled backup" gap identified in
# compound/hermes-backup-trigger-reference.
#
# Usage:
#   bash setup-remote-cron.sh <host> [options]
#
# Options:
#   --user <name>       SSH user (default: root, or use <host>-agent alias)
#   --time <HH:MM>      Daily backup time in 24h HKT/UTC+8 (default: 04:00)
#   --quick             Use hermes backup --quick (default)
#   --full              Use hermes backup (full) instead of --quick
#   --rclone-dest       Remote path for rclone sync, e.g. "cloud:hermes-backups/"
#   --retain-days <N>   Keep N days of local backups (default: 7)
#   --hermes-home       HERMES_HOME path (default: $HOME/.hermes)
#   --dry-run           Print what would be done, don't execute
#   --help, -h          Show this help
#
# Examples:
#   bash setup-remote-cron.sh sg02-agent --quick
#   bash setup-remote-cron.sh sg02-agent --full --rclone-dest "idrive:hermes-backups/sg02/"
#   bash setup-remote-cron.sh sg02-agent --dry-run
# ============================================================================

set -euo pipefail

HOST=""
SSH_USER=""
BACKUP_FLAG="--quick"
BACKUP_MODE="quick"
CRON_HOUR=4
CRON_MIN=0
RCLONE_DEST=""
RETAIN_DAYS=7
HERMES_HOME=""
DRY_RUN=false

require_value() {
  local flag="$1"
  if [ $# -lt 2 ] || [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
    echo "ERROR: $flag requires a value" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      require_value "$1" "${2:-}"
      SSH_USER="$2"
      shift 2
      ;;
    --time)
      require_value "$1" "${2:-}"
      CRON_HOUR="${2%%:*}"
      CRON_MIN="${2##*:}"
      shift 2
      if ! echo "$CRON_HOUR" | grep -qxE '[0-9]{1,2}' || [ "$((10#$CRON_HOUR))" -gt 23 ] 2>/dev/null; then
        echo "ERROR: Invalid --time hour: $CRON_HOUR (must be 0-23)" >&2; exit 1
      fi
      if ! echo "$CRON_MIN" | grep -qxE '[0-9]{1,2}' || [ "$((10#$CRON_MIN))" -gt 59 ] 2>/dev/null; then
        echo "ERROR: Invalid --time minute: $CRON_MIN (must be 0-59)" >&2; exit 1
      fi
      ;;
    --quick)     BACKUP_FLAG="--quick"; BACKUP_MODE="quick"; shift ;;
    --full)      BACKUP_FLAG=""; BACKUP_MODE="full"; shift ;;
    --rclone-dest)
      require_value "$1" "${2:-}"
      RCLONE_DEST="$2"
      shift 2
      ;;
    --retain-days)
      require_value "$1" "${2:-}"
      RETAIN_DAYS="$2"
      shift 2
      if ! echo "$RETAIN_DAYS" | grep -qxE '[0-9]+' || [ "$RETAIN_DAYS" -lt 1 ] || [ "$RETAIN_DAYS" -gt 365 ] 2>/dev/null; then
        echo "ERROR: --retain-days must be 1-365, got: $RETAIN_DAYS" >&2; exit 1
      fi
      ;;
    --hermes-home)
      require_value "$1" "${2:-}"
      HERMES_HOME="$2"
      shift 2
      ;;
    --dry-run)   DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: setup-remote-cron.sh <host> [--quick|--full] [--rclone-dest <path>] [--time HH:MM]"
      exit 0 ;;
    -*)
      echo "ERROR: Unknown option $1" >&2; exit 1 ;;
    *)
      if [ -z "$HOST" ]; then
        HOST="$1"
      else
        echo "ERROR: Unexpected arg: $1" >&2
        exit 1
      fi
      shift ;;
  esac
done

[ -z "$HOST" ] && { echo "ERROR: <host> is required" >&2; exit 1; }
if [ -n "$SSH_USER" ]; then
  HOST="${SSH_USER}@${HOST}"
fi

echo "=== Remote Cron Setup ==="
echo "  Host:        $HOST"
echo "  Backup mode: $BACKUP_MODE"
echo "  Schedule:    ${CRON_HOUR}:${CRON_MIN} HKT (UTC+8) daily"
[ -n "$RCLONE_DEST" ] && echo "  Rclone dest: $RCLONE_DEST"
echo "  Retention:   $RETAIN_DAYS days"
echo ""

# ── Preflight ────────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo "  [DRY-RUN] Would check SSH connectivity to $HOST"
  echo "  [DRY-RUN] Would check hermes CLI on remote"
  if [ -n "$RCLONE_DEST" ]; then
    echo "  [DRY-RUN] Would check rclone config on remote"
  fi
  echo "  [DRY-RUN] Would install cron: $CRON_MIN $CRON_HOUR * * * <command>"
  echo ""
  echo "=== Dry-run complete ==="
  exit 0
fi

echo "--- Checking SSH connectivity ---"
ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" "hostname" &>/dev/null || {
  echo "ERROR: Cannot SSH to $HOST" >&2; exit 1
}
echo "  OK"

# ── Check Hermes CLI ─────────────────────────────────────────────────────────

echo "--- Checking Hermes CLI ---"
HERMES_PATH=$(ssh "$HOST" "command -v hermes 2>/dev/null || echo NOT_FOUND" 2>/dev/null)
if [ "$HERMES_PATH" = "NOT_FOUND" ]; then
  echo "ERROR: hermes CLI not found on $HOST" >&2
  exit 1
fi
echo "  Found: $HERMES_PATH"

# ── Check rclone (if needed) ─────────────────────────────────────────────────

if [ -n "$RCLONE_DEST" ]; then
  echo "--- Checking rclone ---"
  RCLONE_OK=$(ssh "$HOST" "command -v rclone && rclone lsd ${RCLONE_DEST%%:*} 2>/dev/null || echo FAIL" 2>/dev/null)
  if echo "$RCLONE_OK" | grep -q "FAIL"; then
    echo "  WARNING: rclone or remote '$RCLONE_DEST' not accessible"
    echo "  Cron will be installed but rclone step will fail until configured"
  else
    echo "  rclone OK, remote accessible"
  fi
fi

# ── Build cron command ───────────────────────────────────────────────────────

# Determine remote home directory (works for root and non-root users)
REMOTE_HOME=$(ssh "$HOST" "echo \$HOME" 2>/dev/null)
REMOTE_SCRIPTS="${HERMES_HOME:-${REMOTE_HOME}/.hermes}/scripts"
CRON_SCRIPT="${REMOTE_SCRIPTS}/hermes-auto-backup.sh"
REMOTE_LOG="${REMOTE_HOME}/hermes-auto-backup.log"

# Build the cron script content
CRON_CMDS="#!/bin/bash
# Auto-generated by host-backup-restore/scripts/hermes/setup-remote-cron.sh
# Daily backup: ${BACKUP_MODE} mode at ${CRON_HOUR}:${CRON_MIN} HKT
# Retention: ${RETAIN_DAYS} days

set -euo pipefail

BACKUP_DIR=\${HERMES_HOME:-\$HOME/.hermes}/backups
TIMESTAMP=\$(date +%Y%m%d-%H%M%S)
mkdir -p \"\$BACKUP_DIR\"

# Run hermes backup
hermes backup ${BACKUP_FLAG} -o \"\$BACKUP_DIR/hermes-auto-\${TIMESTAMP}.zip\"

# Prune local backups older than ${RETAIN_DAYS} days
find \"\$BACKUP_DIR\" -name \"hermes-auto-*.zip\" -mtime +${RETAIN_DAYS} -delete 2>/dev/null || true
"

if [ -n "$RCLONE_DEST" ]; then
  CRON_CMDS="$CRON_CMDS
# Sync to cloud via rclone
rclone sync \"\$BACKUP_DIR/\" \"${RCLONE_DEST}\" --backup-dir \"${RCLONE_DEST%/*}/archive\" 2>/dev/null || echo \"rclone sync failed\" >&2
"
fi

CRON_LINE="${CRON_MIN} ${CRON_HOUR} * * * bash ${CRON_SCRIPT} >> ${REMOTE_LOG} 2>&1"

# ── Install cron script ─────────────────────────────────────────────────────

echo "--- Installing cron script ---"
ssh "$HOST" "mkdir -p '$REMOTE_SCRIPTS'" 2>/dev/null

# Write the cron script via heredoc
ssh "$HOST" "cat > '$CRON_SCRIPT' << 'CRONEOF'
$CRON_CMDS
CRONEOF
chmod +x '$CRON_SCRIPT'
echo 'INSTALLED'" 2>/dev/null || {
  echo "ERROR: Failed to install cron script" >&2
  exit 1
}
echo "  Cron script: $CRON_SCRIPT"

# ── Install crontab entry ───────────────────────────────────────────────────

echo "--- Installing crontab entry ---"
INSTALL_CRON=$(cat <<CMD
# Install cron if not present
(crontab -l 2>/dev/null | grep -v 'hermes-auto-backup'; echo '${CRON_LINE}') | crontab -
echo 'DONE'
CMD
)

CRON_RESULT=$(ssh "$HOST" "$INSTALL_CRON" 2>/dev/null || echo "FAILED")
if [ "$CRON_RESULT" = "DONE" ]; then
  echo "  Cron: ${CRON_MIN} ${CRON_HOUR} * * * bash $CRON_SCRIPT"
  echo "  Log:  $REMOTE_LOG"
else
  echo "WARNING: Cron install may have failed: $CRON_RESULT" >&2
fi

# ── Verify ───────────────────────────────────────────────────────────────────

echo "--- Verifying ---"
VERIFY=$(ssh "$HOST" "crontab -l 2>/dev/null | grep hermes-auto-backup || echo MISSING" 2>/dev/null)
if [ "$VERIFY" = "MISSING" ]; then
  echo "WARNING: Cron job not found after install" >&2
else
  echo "  OK: cron job installed"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Setup Complete ==="
echo "  Host:        $HOST"
echo "  Script:      $CRON_SCRIPT"
echo "  Schedule:    ${CRON_HOUR}:${CRON_MIN} HKT daily"
echo "  Log:         $REMOTE_LOG"
echo "  Retention:   $RETAIN_DAYS days (local)"
echo ""
echo "  To verify:"
echo "    ssh $HOST \"crontab -l\""
echo "    ssh $HOST \"tail -20 $REMOTE_LOG\""
