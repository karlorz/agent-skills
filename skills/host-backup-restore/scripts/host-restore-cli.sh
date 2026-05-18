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

# Compose SSH target — resolve user from ~/.ssh/config if available
# Priority: --user flag > user@host text > *-agent alias > SSH config User directive > agent@ default
if [ -n "$RESTORE_USER" ]; then
  SSH_TARGET="${RESTORE_USER}@${TARGET}"
elif [[ "$TARGET" == *@* ]]; then
  SSH_TARGET="$TARGET"
elif [[ "$TARGET" == *-agent ]]; then
  SSH_TARGET="$TARGET"
else
  # Check ~/.ssh/config for User directive matching this host
  ssh_config_user=$(awk -v host="$TARGET" '
    /^Host / { match_host=0; for(i=2;i<=NF;i++) if($i==host) match_host=1 }
    match_host && /^[[:space:]]+User / { print $2; exit }
  ' ~/.ssh/config 2>/dev/null)
  if [ -n "$ssh_config_user" ]; then
    SSH_TARGET="${ssh_config_user}@${TARGET}"
    echo "Using SSH config user: ${ssh_config_user}@${TARGET}"
  else
    SSH_TARGET="agent@${TARGET}"
  fi
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
# wiki available if rclone.conf present in backup
[ -f "$BACKUP_CONTENT_DIR/rclone.conf" ] && AVAILABLE_GROUPS="$AVAILABLE_GROUPS wiki"

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
      # Check if Caddy binary exists on target — offer to install if missing
      caddy_exists=$(ssh "$TARGET" "which caddy 2>/dev/null || echo MISSING" 2>/dev/null || echo "MISSING")
      if [ "$caddy_exists" = "MISSING" ]; then
        echo "  Caddy not installed on target. Attempting to install..."
        caddy_install=$(ssh "$TARGET" "sudo apt-get install -y caddy 2>&1" 2>/dev/null || echo "INSTALL_FAILED")
        if [[ "$caddy_install" == *"INSTALL_FAILED"* ]] || [[ "$caddy_install" == *"Unable to locate package"* ]]; then
          echo "  ⚠ Caddy install failed. Install it manually to serve restored domains."
          echo "    Debian/Ubuntu: sudo apt-get install caddy"
          echo "    Other: https://caddyserver.com/docs/install"
        else
          echo "  Caddy installed successfully."
          ssh "$TARGET" "sudo systemctl daemon-reload; sudo systemctl enable caddy; sudo systemctl restart caddy || sudo service caddy restart || true" 2>/dev/null || true
        fi
      else
        ssh "$TARGET" "sudo systemctl daemon-reload 2>/dev/null; sudo systemctl enable caddy 2>/dev/null; sudo systemctl restart caddy 2>/dev/null || sudo service caddy restart 2>/dev/null || true" 2>/dev/null || true
      fi
      ;;
    hermes)
      if [ -f "$BACKUP_CONTENT_DIR/hermes-backup.zip" ]; then
        # Use ~/ (real disk) instead of /tmp (small tmpfs) for large backups
        hermes_size=$(stat -f%z "$BACKUP_CONTENT_DIR/hermes-backup.zip" 2>/dev/null || echo 0)
        remote_path="/tmp/hermes-restore.zip"
        if [ "$hermes_size" -gt 1073741824 ]; then  # >1GB
          remote_path="~/hermes-restore.zip"
          echo "  Large backup ($((hermes_size/1024/1024))MB), using home dir for transfer..."
        fi
        scp "$BACKUP_CONTENT_DIR/hermes-backup.zip" "${TARGET}:${remote_path}" 2>/dev/null || {
          echo "  ⚠ SCP failed — check disk space on target"
          return
        }
        ssh "$TARGET" "hermes import --force ${remote_path} 2>/dev/null || hermes import ${remote_path} 2>/dev/null || true"
        ssh "$TARGET" "rm -f ${remote_path}" 2>/dev/null || true
        # Re-install gateway + dashboard services (source unit files may have wrong paths)
        echo "  Re-installing Hermes gateway and dashboard services..."
        ssh "$TARGET" "
          # Remove stale system-level unit files from source host
          sudo rm -f /etc/systemd/system/hermes-gateway.service /etc/systemd/system/hermes-dashboard.service 2>/dev/null
          sudo systemctl daemon-reload 2>/dev/null
          # Re-install using local hermes binary (writes correct paths)
          hermes gateway install 2>/dev/null || true
          hermes dashboard install --system 2>/dev/null || true
          systemctl --user start hermes-gateway.service 2>/dev/null || true
          sudo systemctl start hermes-dashboard.service 2>/dev/null || true
        " 2>/dev/null || true
      fi
      ;;
    other_services)
      [ -f "$BACKUP_CONTENT_DIR/services.txt" ] && scp "$BACKUP_CONTENT_DIR/services.txt" "${TARGET}:/tmp/" 2>/dev/null || true
      # Systemd daemon-reload in case unit files were deployed
      echo "  Reloading systemd..."
      ssh "$TARGET" "systemctl daemon-reload 2>/dev/null || true"
      ssh "$TARGET" "systemctl --user daemon-reload 2>/dev/null || true"
      # List backed-up services that need packages installed on target
      if [ -f "$BACKUP_CONTENT_DIR/services.txt" ]; then
        svc_list=$(grep -oE 'alertmanager|prometheus|grafana-server|filebrowser|tailscaled|komari|komari-agent|claude-ingress' "$BACKUP_CONTENT_DIR/services.txt" | sort -u | tr '\n' ' ' || true)
        if [ -n "$svc_list" ]; then
          echo "  Services requiring package install on target: $svc_list"
          echo "  Install with: apt-get install <packages> then systemctl enable --now <service>"
        fi
      fi
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
    wiki)
      # Check if rclone S3 wiki mount is configured
      wiki_fs=$(ssh "$TARGET" "df -T ~/wiki 2>/dev/null | tail -1 | awk '{print \$2}' || echo 'missing'" 2>/dev/null || echo "missing")
      if [ "$wiki_fs" = "fuse.rclone" ]; then
        echo "  Wiki S3 mount already active: fuse.rclone"
      else
        fuse_ok=$(ssh "$TARGET" "test -c /dev/fuse && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
        if [ "$fuse_ok" = "yes" ]; then
          echo "  FUSE available. Setting up rclone wiki mount..."
          # Copy rclone.conf from backup archive
          if [ -f "$BACKUP_CONTENT_DIR/rclone.conf" ]; then
            ssh "$TARGET" "mkdir -p ~/.config/rclone" 2>/dev/null || true
            scp "$BACKUP_CONTENT_DIR/rclone.conf" "${TARGET}:~/.config/rclone/rclone.conf" 2>/dev/null || {
              echo "  ⚠ Failed to copy rclone.conf"
              return
            }
            echo "  rclone.conf restored."
          fi
          # Check rclone binary
          rclone_ok=$(ssh "$TARGET" "which rclone 2>/dev/null || echo MISSING" 2>/dev/null || echo "MISSING")
          if [ "$rclone_ok" = "MISSING" ]; then
            echo "  rclone not installed. Install it: curl https://rclone.org/install.sh | sudo bash"
            return
          fi
          # Mount wiki
          ssh "$TARGET" "
            mkdir -p ~/wiki
            fusermount -uz ~/wiki 2>/dev/null || true
            rclone mount cloud:cloud/wiki ~/wiki --vfs-cache-mode writes --vfs-cache-max-age 168h --allow-other --daemon 2>&1
          " 2>/dev/null || echo "  ⚠ rclone mount failed"
        else
          echo "  ⚠ FUSE not available. Skipping wiki S3 mount."
          echo "     LXC: enable fuse=1 in PVE template or use tmpfiles.d:"
          echo "     echo 'c /dev/fuse 0666 root root - 10:229' > /etc/tmpfiles.d/fuse.conf"
        fi
      fi
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
