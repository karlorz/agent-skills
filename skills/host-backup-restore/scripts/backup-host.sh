#!/bin/bash
# backup-host.sh — Mechanical backup script
# Reads manifest and backs up selected groups
# Usage: BACKUP_DIR=/path bash backup-host.sh <manifest.json> [groups...]
# Groups: base caddy_domains hermes databases other_services apt
# Default: all groups
set -euo pipefail

MANIFEST="${1:-}"
shift || true
SELECTED_GROUPS="${*:-all}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Desktop/backups/}"
HOST=""

if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "Usage: BACKUP_DIR=/path $0 <manifest.json> [groups...]" >&2
  echo "  Groups: base caddy_domains hermes databases other_services apt" >&2
  echo "  Default: all groups" >&2
  exit 1
fi

# Extract hostname and timestamp from manifest
HOST=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['hostname'])")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_BASE="${BACKUP_DIR%/}"
if [ "$(basename "$BACKUP_BASE")" = "$HOST" ]; then
  BACKUP_DIR="${BACKUP_BASE}/backup-${TIMESTAMP}"
else
  BACKUP_DIR="${BACKUP_BASE}/${HOST}/backup-${TIMESTAMP}"
fi
mkdir -p "$BACKUP_DIR"
FILE_COUNT=0

echo "=== Host Backup: $HOST ==="
echo "Destination: $BACKUP_DIR"
echo "Started: $(date)"
echo ""

backup_group() {
  local group="$1"
  echo "--- Backing up: $group ---"

  case "$group" in
    base)
      # SSH config, hostname, hosts
      ssh "$HOST" "sudo cat /etc/hostname" > "$BACKUP_DIR/hostname" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      ssh "$HOST" "sudo cat /etc/hosts" > "$BACKUP_DIR/hosts" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      ssh "$HOST" "sudo cat /etc/ssh/sshd_config" > "$BACKUP_DIR/sshd_config" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      ssh "$HOST" "sudo cat /etc/os-release" > "$BACKUP_DIR/os-release" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      # rclone config (for wiki S3 mount restore)
      ssh "$HOST" "cat ~/.config/rclone/rclone.conf 2>/dev/null" > "$BACKUP_DIR/rclone.conf" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      echo "$(date -Iseconds)" > "$BACKUP_DIR/BACKUP_TIMESTAMP"
      ;;
    caddy_domains)
      # Caddy config
      ssh "$HOST" "sudo tar czf - /etc/caddy/ 2>/dev/null" > "$BACKUP_DIR/caddy-config.tar.gz" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      # SSL certs (manual, not auto-renewed Let's Encrypt)
      ssh "$HOST" "sudo tar czf - /etc/ssl/certs/ 2>/dev/null" > "$BACKUP_DIR/ssl-certs.tar.gz" 2>/dev/null || true
      # Caddy data dir (auto-TLS state)
      ssh "$HOST" "sudo tar czf - /var/lib/caddy/.local/share/caddy/ 2>/dev/null" > "$BACKUP_DIR/caddy-data.tar.gz" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      # Caddy validate
      ssh "$HOST" "sudo caddy validate --config /etc/caddy/Caddyfile 2>&1" > "$BACKUP_DIR/caddy-validate.txt" 2>/dev/null || echo "caddy validate failed" > "$BACKUP_DIR/caddy-validate.txt"
      # Extract per-domain listing
      python3 -c "
import json
m = json.load(open('$MANIFEST'))
domains = m.get('caddy_domains', [])
with open('$BACKUP_DIR/domains.txt', 'w') as f:
    for d in domains:
        domain = d.get('domain', '')
        upstream = d.get('upstream', '')
        f.write(f'{domain} -> {upstream}\n')
      " 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      ;;
    hermes)
      # Use hermes built-in backup (handles SQLite WAL mode)
      # IMPORTANT: hermes backup does NOT support --tier flag
      # Use --quick for minimal, no flag for full
      echo "Creating Hermes backup on $HOST..."
      BACKUP_MODE=""
      HERMES_TIER="${HERMES_TIER:-full}"
      if [ "$HERMES_TIER" = "minimal" ]; then
        BACKUP_MODE="--quick"
      fi

      # Precheck /tmp space: clean old backup zips and warn on small tmpfs
      ssh "$HOST" "
        tmp_avail=\$(df -m /tmp 2>/dev/null | tail -1 | awk '{print \$4}')
        tmp_fstype=\$(df -T /tmp 2>/dev/null | tail -1 | awk '{print \$2}')
        echo \"  /tmp: \${tmp_avail}MB available on \${tmp_fstype:-unknown}\"
        old_count=\$(ls -1 /tmp/hermes-backup-*.zip 2>/dev/null | wc -l)
        if [ \"\$old_count\" -gt 0 ]; then
          echo \"  Cleaning \$old_count old hermes backup zips from /tmp...\"
          rm -f /tmp/hermes-backup-*.zip
        fi
        if [ \"\${tmp_fstype}\" = \"tmpfs\" ] && [ \"\$tmp_avail\" -lt 3072 ]; then
          echo \"  WARNING: /tmp is tmpfs with <3GB — Hermes backup may fail. Set --hermes-tier minimal or use ~/ instead.\"
        fi
      " 2>&1 || true

      # shellcheck disable=SC2086
      ssh "$HOST" "hermes backup $BACKUP_MODE -o /tmp/hermes-backup-$TIMESTAMP.zip 2>&1" > "$BACKUP_DIR/hermes-backup-log.txt" 2>/dev/null || {
        echo "hermes backup failed (may not be installed)"
        echo "hermes backup failed" > "$BACKUP_DIR/hermes-backup-status.txt"
        return
      }
      scp "$HOST:/tmp/hermes-backup-$TIMESTAMP.zip" "$BACKUP_DIR/hermes-backup.zip" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      ssh "$HOST" "rm -f /tmp/hermes-backup-$TIMESTAMP.zip" 2>/dev/null || true
      echo "hermes backup OK" > "$BACKUP_DIR/hermes-backup-status.txt"
      # Also capture hermes --version output
      ssh "$HOST" "hermes --version" > "$BACKUP_DIR/hermes-version.txt" 2>/dev/null || true
      ;;
    databases)
      # sqlite files from manifest
      python3 -c "
import json
m = json.load(open('$MANIFEST'))
dbs = m.get('databases', {})
with open('$BACKUP_DIR/databases-summary.txt', 'w') as f:
    for db_type, items in dbs.items():
        if isinstance(items, list):
            f.write(f'{db_type}: {len(items)} files\n')
            for item in items:
                f.write(f'  {item}\n')
        else:
            f.write(f'{db_type}: {items}\n')
      " 2>/dev/null || true

      # Copy sqlite files using python3 for safe handling
      python3 -c "
import json, subprocess, sys, os
m = json.load(open('$MANIFEST'))
host = m['hostname']
backup_dir = '$BACKUP_DIR'
count = 0
sqlite_files = m.get('databases', {}).get('sqlite', [])
for f in sqlite_files:
    try:
        result = subprocess.run(['scp', f'{host}:{f}', backup_dir + '/'],
                              capture_output=True, timeout=30)
        if result.returncode == 0:
            count += 1
            basename = os.path.basename(f)
            src = os.path.join(backup_dir, basename)
            dst = os.path.join(backup_dir, 'sqlite_' + basename)
            # Avoid name collisions
            if os.path.exists(src) and not os.path.exists(dst):
                os.rename(src, dst)
    except Exception:
        pass
print(f'Copied {count} sqlite files')
      " 2>/dev/null || true
      ;;
    other_services)
      # Systemd service inventory
      ssh "$HOST" "sudo systemctl list-units --type=service --no-pager --no-legend 2>/dev/null" > "$BACKUP_DIR/services.txt" 2>/dev/null || true
      # User services
      ssh "$HOST" "systemctl --user list-units --type=service --no-pager --no-legend 2>/dev/null" > "$BACKUP_DIR/user-services.txt" 2>/dev/null || true
      # Unit files
      ssh "$HOST" "for s in \$(sudo systemctl list-units --type=service --no-pager --no-legend 2>/dev/null | awk '{print \$1}'); do sudo systemctl cat \"\$s\" 2>/dev/null; done" > "$BACKUP_DIR/service-unit-files.txt" 2>/dev/null || true
      FILE_COUNT=$((FILE_COUNT + 3))
      ;;
    apt)
      # Package selections
      ssh "$HOST" "sudo dpkg --get-selections 2>/dev/null" > "$BACKUP_DIR/dpkg-selections.txt" 2>/dev/null || true
      # Apt sources
      ssh "$HOST" "sudo cat /etc/apt/sources.list 2>/dev/null; echo '---'; for f in /etc/apt/sources.list.d/*.list 2>/dev/null; do echo \"=== \$f ===\"; sudo cat \"\$f\"; done" > "$BACKUP_DIR/apt-sources.txt" 2>/dev/null || true
      # Installed package count
      ssh "$HOST" "sudo dpkg -l 2>/dev/null | wc -l" > "$BACKUP_DIR/pkg-count.txt" 2>/dev/null || true
      FILE_COUNT=$((FILE_COUNT + 3))
      ;;
  esac

  echo "--- Done: $group ---"
  echo ""
}

if [ "$SELECTED_GROUPS" = "all" ]; then
  for g in base caddy_domains hermes databases other_services apt; do
    backup_group "$g"
  done
else
  for g in $SELECTED_GROUPS; do
    # Check if the group is recognized
    case "$g" in
      base|caddy_domains|hermes|databases|other_services|apt) backup_group "$g" ;;
      *) echo "Warning: Unknown group '$g', skipping" ;;
    esac
  done
fi

# Write manifest copy
cp "$MANIFEST" "$BACKUP_DIR/manifest.json"
FILE_COUNT=$((FILE_COUNT + 1))

# Create archive
echo "=== Creating archive ==="
BACKUP_NAME="${HOST}-backup-${TIMESTAMP}.tar.gz"
tar czf "$BACKUP_DIR/../$BACKUP_NAME" -C "$BACKUP_DIR/.." "$(basename "$BACKUP_DIR")" 2>/dev/null || {
  # Fallback
  tar czf "${BACKUP_DIR}.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")" 2>/dev/null || true
}

echo "Files backed up: $FILE_COUNT"
echo "Archive: $(dirname "$BACKUP_DIR")/$BACKUP_NAME"
if [ -f "$(dirname "$BACKUP_DIR")/$BACKUP_NAME" ]; then
  du -sh "$(dirname "$BACKUP_DIR")/$BACKUP_NAME"
else
  du -sh "${BACKUP_DIR}.tar.gz" 2>/dev/null || ls -lh "${BACKUP_DIR}.tar.gz"
fi
echo "=== Backup complete: $(date) ==="
