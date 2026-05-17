#!/bin/bash
# host-restore-cli.sh — Non-interactive CLI restore from backup archive
set -euo pipefail

ARCHIVE=""
BACKUP_GROUPS=""
TARGET=""
RESTORE_USER=""
ALL=false
DRY_RUN=false

usage() {
  echo "Usage: $0 --archive PATH [options]"
  echo "Options:"
  echo "  --archive PATH        Backup archive path (.tar.gz) (required)"
  echo "  --target HOST         Target hostname for restore (required)"
  echo "  --user USER           SSH user for target (default: agent; use root for root SSH)"
  echo "  --all                 Restore all groups"
  echo "  --groups 'g1,g2,...'  Specific groups to restore"
  echo "  --dry-run             Preview only"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --archive) ARCHIVE="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --user) RESTORE_USER="$2"; shift 2 ;;
    --all) ALL=true; shift ;;
    --groups) BACKUP_GROUPS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ -z "$ARCHIVE" ] || [ -z "$TARGET" ]; then
  echo "Error: --archive and --target are required"
  usage
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "Error: Archive not found: $ARCHIVE"
  exit 1
fi

# Compose SSH target — default to non-root agent user
if [ -n "$RESTORE_USER" ]; then
  SSH_TARGET="${RESTORE_USER}@${TARGET}"
elif [[ "$TARGET" == *@* ]]; then
  SSH_TARGET="$TARGET"
elif [[ "$TARGET" == *-agent ]]; then
  SSH_TARGET="$TARGET"
else
  SSH_TARGET="agent@${TARGET}"
fi
TARGET="$SSH_TARGET"

echo "=== Host Restore CLI ==="
echo "Target:  $TARGET"
echo "Dry run: $DRY_RUN"
echo ""

# Determine archive format and extract to temp
RESTORE_DIR=$(mktemp -d)
trap 'rm -rf "$RESTORE_DIR"' EXIT

case "$ARCHIVE" in
  *.tar.gz) tar xzf "$ARCHIVE" -C "$RESTORE_DIR" ;;
  *.tar)    tar xf "$ARCHIVE" -C "$RESTORE_DIR" ;;
  *.zip)    unzip -q "$ARCHIVE" -d "$RESTORE_DIR" ;;
  *)
    echo "Error: Unsupported archive format (use .tar.gz, .tar, or .zip)"
    exit 1
    ;;
esac

# Find the backup directory (may be nested under a timestamp dir)
BACKUP_CONTENT_DIR=$(find "$RESTORE_DIR" -maxdepth 2 -type f -name "hostname" -exec dirname {} \; 2>/dev/null | head -1)
if [ -z "$BACKUP_CONTENT_DIR" ]; then
  BACKUP_CONTENT_DIR=$(ls -d "$RESTORE_DIR"/*/ 2>/dev/null | head -1)
fi
BACKUP_CONTENT_DIR="${BACKUP_CONTENT_DIR:-$RESTORE_DIR}"

echo "Restore source: $BACKUP_CONTENT_DIR"
echo ""

# Detect available groups
AVAILABLE_GROUPS=""
[ -f "$BACKUP_CONTENT_DIR/hostname" ] && AVAILABLE_GROUPS="$AVAILABLE_GROUPS base"
[ -f "$BACKUP_CONTENT_DIR/caddy-config.tar.gz" ] && AVAILABLE_GROUPS="$AVAILABLE_GROUPS caddy_domains"
[ -f "$BACKUP_CONTENT_DIR/hermes-backup.zip" ] && AVAILABLE_GROUPS="$AVAILABLE_GROUPS hermes"
[ -f "$BACKUP_CONTENT_DIR/dpkg-selections.txt" ] && AVAILABLE_GROUPS="$AVAILABLE_GROUPS apt"
[ -f "$BACKUP_CONTENT_DIR/services.txt" ] && AVAILABLE_GROUPS="$AVAILABLE_GROUPS other_services"
# databases available if sqlite files present
ls "$BACKUP_CONTENT_DIR"/*.db &>/dev/null && AVAILABLE_GROUPS="$AVAILABLE_GROUPS databases"

echo "Available groups:${AVAILABLE_GROUPS:- none detected}"
echo ""

# ── OS/arch compatibility check ──────────────────────────────────────────
# Read backup OS info from manifest and compare with target
BACKUP_OS=""
BACKUP_OS_VER=""
BACKUP_ARCH=""
if [ -f "$BACKUP_CONTENT_DIR/manifest.json" ]; then
  BACKUP_OS=$(python3 -c "
import json
m = json.load(open('$BACKUP_CONTENT_DIR/manifest.json'))
print(m.get('os', ''))
" 2>/dev/null || echo "")
  BACKUP_OS_VER=$(python3 -c "
import json
m = json.load(open('$BACKUP_CONTENT_DIR/manifest.json'))
print(m.get('os_version', ''))
" 2>/dev/null || echo "")
  BACKUP_ARCH=$(python3 -c "
import json
m = json.load(open('$BACKUP_CONTENT_DIR/manifest.json'))
print(m.get('arch', ''))
" 2>/dev/null || echo "")
fi
# Fallback to os-release file
if [ -z "$BACKUP_OS" ] && [ -f "$BACKUP_CONTENT_DIR/os-release" ]; then
  BACKUP_OS=$(grep '^ID=' "$BACKUP_CONTENT_DIR/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
  BACKUP_OS_VER=$(grep '^VERSION_ID=' "$BACKUP_CONTENT_DIR/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
fi

TARGET_OS=""
TARGET_OS_VER=""
TARGET_ARCH=""
if [ -n "$TARGET" ] && ! $DRY_RUN; then
  TARGET_OS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET" "grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "")
  TARGET_OS_VER=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET" "grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "")
  TARGET_ARCH=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET" "uname -m" 2>/dev/null || echo "")
fi

if [ -n "$BACKUP_OS" ] && [ -n "$TARGET_OS" ]; then
  if [ "$BACKUP_OS" != "$TARGET_OS" ] || [ "$BACKUP_OS_VER" != "$TARGET_OS_VER" ]; then
    echo "⚠ WARNING: OS mismatch!"
    echo "  Backup source: $BACKUP_OS $BACKUP_OS_VER (${BACKUP_ARCH:-unknown})"
    echo "  Target:        $TARGET_OS $TARGET_OS_VER (${TARGET_ARCH:-unknown})"
    echo "  Restoring apt sources across different OS versions may break dependencies."
    echo "  Use --groups without 'apt' to skip package restores."
    echo ""
  fi
  if [ -n "$BACKUP_ARCH" ] && [ -n "$TARGET_ARCH" ] && [ "$BACKUP_ARCH" != "$TARGET_ARCH" ]; then
    echo "⚠ WARNING: Architecture mismatch!"
    echo "  Backup source: ${BACKUP_ARCH}"
    echo "  Target:        ${TARGET_ARCH}"
    echo "  Binary compatibility may be affected."
    echo ""
  fi
fi

restore_group() {
  local group="$1"

  if $DRY_RUN; then
    echo "[DRY RUN] Would restore: $group"
    return
  fi

  echo "--- Restoring: $group ---"

  case "$group" in
    base)
      [ -f "$BACKUP_CONTENT_DIR/hostname" ] && scp "$BACKUP_CONTENT_DIR/hostname" "${TARGET}:/etc/hostname" 2>/dev/null || true
      [ -f "$BACKUP_CONTENT_DIR/hosts" ] && scp "$BACKUP_CONTENT_DIR/hosts" "${TARGET}:/etc/hosts" 2>/dev/null || true
      ;;
    caddy_domains)
      [ -f "$BACKUP_CONTENT_DIR/caddy-config.tar.gz" ] && ssh "$TARGET" "tar xzf - -C /" < "$BACKUP_CONTENT_DIR/caddy-config.tar.gz" 2>/dev/null || true
      [ -f "$BACKUP_CONTENT_DIR/ssl-certs.tar.gz" ] && ssh "$TARGET" "tar xzf - -C /" < "$BACKUP_CONTENT_DIR/ssl-certs.tar.gz" 2>/dev/null || true
      ssh "$TARGET" "systemctl restart caddy 2>/dev/null || service caddy restart 2>/dev/null || true"
      ;;
    hermes)
      if [ -f "$BACKUP_CONTENT_DIR/hermes-backup.zip" ]; then
        scp "$BACKUP_CONTENT_DIR/hermes-backup.zip" "${TARGET}:/tmp/hermes-restore.zip" 2>/dev/null || true
        ssh "$TARGET" "hermes import /tmp/hermes-restore.zip 2>/dev/null || true"
        ssh "$TARGET" "rm -f /tmp/hermes-restore.zip" 2>/dev/null || true
      fi
      ;;
    other_services)
      [ -f "$BACKUP_CONTENT_DIR/services.txt" ] && scp "$BACKUP_CONTENT_DIR/services.txt" "${TARGET}:/tmp/" 2>/dev/null || true
      ;;
    apt)
      if [ -f "$BACKUP_CONTENT_DIR/dpkg-selections.txt" ]; then
        echo "Warning: apt restore across distro versions may break dependencies"
        scp "$BACKUP_CONTENT_DIR/dpkg-selections.txt" "${TARGET}:/tmp/" 2>/dev/null || true
      fi
      ;;
    databases)
      for db_file in "$BACKUP_CONTENT_DIR"/*.db; do
        [ -f "$db_file" ] && scp "$db_file" "${TARGET}:/tmp/$(basename "$db_file")" 2>/dev/null || true
      done
      ;;
  esac

  echo "--- Done: $group ---"
  echo ""
}

if $ALL; then
  for g in $AVAILABLE_GROUPS; do
    restore_group "$g"
  done
elif [ -n "$BACKUP_GROUPS" ]; then
  # Normalize: support both comma-separated and space-separated groups
  NORMALIZED=$(echo "$BACKUP_GROUPS" | tr ',' ' ')
  for g in $NORMALIZED; do
    if echo "$AVAILABLE_GROUPS" | grep -qw "$g"; then
      restore_group "$g"
    else
      echo "Warning: Group '$g' not found in archive, skipping"
    fi
  done
fi

echo "=== Restore complete ==="
