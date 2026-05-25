#!/bin/bash
# backup-host.sh — Mechanical backup script
# Reads manifest and backs up selected groups
# Usage: BACKUP_DIR=/path bash backup-host.sh <manifest.json> [groups...]
# Groups: base caddy_domains hermes databases other_services apt wiki
# Default: all groups
set -euo pipefail

# Portable checksum — macOS uses shasum, Linux uses sha256sum
_compute_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1"
  else
    echo "checksum_unavailable $(basename "$1")"
  fi
}

MANIFEST="${1:-}"
shift || true
SELECTED_GROUPS="${*:-all}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Desktop/backups/}"
HOST=""

if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "Usage: BACKUP_DIR=/path $0 <manifest.json> [groups...]" >&2
  echo "  Groups: base caddy_domains hermes databases other_services apt wiki" >&2
  echo "  Default: all groups" >&2
  echo "" >&2
  echo "Environment:" >&2
  echo "  BACKUP_DIR     Backup destination (default: ~/Desktop/backups/)" >&2
  echo "  HERMES_TIER    minimal|standard|full (default: full)" >&2
  echo "  DB_USER        Database username for pg_dump/mysqldump" >&2
  echo "  DB_PASS_FILE   Path to file with database password (secure)" >&2
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
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

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
      # rclone config is captured in wiki group
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
      rsync -avP --partial-dir=.rsync-partial --timeout=300 -e "ssh $SSH_OPTS" "$HOST:/tmp/hermes-backup-$TIMESTAMP.zip" "$BACKUP_DIR/hermes-backup.zip" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      ssh "$HOST" "rm -f /tmp/hermes-backup-$TIMESTAMP.zip" 2>/dev/null || true
      echo "hermes backup OK" > "$BACKUP_DIR/hermes-backup-status.txt"
      # Also capture hermes --version output
      ssh "$HOST" "hermes --version" > "$BACKUP_DIR/hermes-version.txt" 2>/dev/null || true
      ;;
    databases)
      # Write database summary from manifest
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

      # --- PostgreSQL dumps ---
      PG_DBS=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
dbs = m.get('databases', {})
pg = dbs.get('postgres', [])
if isinstance(pg, list):
    # Extract db names if manifest has structured data, else use detected flag
    print(' '.join(pg) if pg else '')
else:
    print(pg if pg and pg != 'not detected' else '')
      " 2>/dev/null || true)
      if [ -n "$PG_DBS" ]; then
        PG_USER="${DB_USER:-postgres}"
        for db in $PG_DBS; do
          echo "  Dumping PostgreSQL: $db"
          ssh "$HOST" "pg_dump -Fc -U '$PG_USER' '$db'" > "$BACKUP_DIR/pg_${db}.dump" 2>"$BACKUP_DIR/pg_${db}.err" && {
            FILE_COUNT=$((FILE_COUNT + 1))
            _compute_sha256 "$BACKUP_DIR/pg_${db}.dump" > "$BACKUP_DIR/pg_${db}.dump.sha256"
            echo "    OK: pg_${db}.dump ($(du -sh "$BACKUP_DIR/pg_${db}.dump" | cut -f1))"
          } || echo "    FAILED: pg_dump for $db (may need --db-user or DB_USER env)"
        done
      fi

      # --- MySQL dumps ---
      MYSQL_DBS=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
dbs = m.get('databases', {})
my = dbs.get('mysql', [])
if isinstance(my, list):
    print(' '.join(my) if my else '')
else:
    print(my if my and my != 'not detected' else '')
      " 2>/dev/null || true)
      if [ -n "$MYSQL_DBS" ]; then
        MYSQL_USER="${DB_USER:-root}"
        # Read DB_PASS from temp file if available (avoids env exposure)
        if [ -n "${DB_PASS_FILE:-}" ] && [ -f "$DB_PASS_FILE" ]; then
          MYSQL_PASS=$(cat "$DB_PASS_FILE")
        else
          MYSQL_PASS="${DB_PASS:-}"
        fi
        for db in $MYSQL_DBS; do
          echo "  Dumping MySQL: $db"
          # Use MYSQL_PWD env var to avoid password exposure in process table
          MYSQL_AUTH="-u'$MYSQL_USER'"
          MYSQL_DUMP_CMD="mysqldump $MYSQL_AUTH --single-transaction --routines --triggers --events '$db'"
          if [ -n "$MYSQL_PASS" ]; then
            MYSQL_DUMP_CMD="MYSQL_PWD='$MYSQL_PASS' $MYSQL_DUMP_CMD"
          fi
          # shellcheck disable=SC2086
          ssh "$HOST" "$MYSQL_DUMP_CMD 2>/dev/null | gzip" > "$BACKUP_DIR/mysql_${db}.sql.gz" && {
            FILE_COUNT=$((FILE_COUNT + 1))
            _compute_sha256 "$BACKUP_DIR/mysql_${db}.sql.gz" > "$BACKUP_DIR/mysql_${db}.sql.gz.sha256"
            echo "    OK: mysql_${db}.sql.gz ($(du -sh "$BACKUP_DIR/mysql_${db}.sql.gz" | cut -f1))"
          } || echo "    FAILED: mysqldump for $db (may need --db-user/--db-pass)"
        done
      fi

      # --- MongoDB dumps ---
      MONGO_DETECTED=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
dbs = m.get('databases', {})
mg = dbs.get('mongodb', 'not detected')
print(mg if mg and mg != 'not detected' else '')
      " 2>/dev/null || true)
      if [ -n "$MONGO_DETECTED" ]; then
        echo "  Dumping MongoDB..."
        MONGO_URI="${MONGO_URI:-}"
        if [ -n "$MONGO_URI" ]; then
          ssh "$HOST" "mongodump --uri='$MONGO_URI' --gzip --archive 2>/dev/null" > "$BACKUP_DIR/mongo.archive.gz" && {
            FILE_COUNT=$((FILE_COUNT + 1))
            _compute_sha256 "$BACKUP_DIR/mongo.archive.gz" > "$BACKUP_DIR/mongo.archive.gz.sha256"
            echo "    OK: mongo.archive.gz ($(du -sh "$BACKUP_DIR/mongo.archive.gz" | cut -f1))"
          } || echo "    FAILED: mongodump"
        else
          ssh "$HOST" "mongodump --gzip --archive 2>/dev/null" > "$BACKUP_DIR/mongo.archive.gz" && {
            FILE_COUNT=$((FILE_COUNT + 1))
            _compute_sha256 "$BACKUP_DIR/mongo.archive.gz" > "$BACKUP_DIR/mongo.archive.gz.sha256"
            echo "    OK: mongo.archive.gz ($(du -sh "$BACKUP_DIR/mongo.archive.gz" | cut -f1))"
          } || echo "    FAILED: mongodump (may need MONGO_URI env)"
        fi
      fi

      # --- SQLite dumps (WAL-safe via .backup command) ---
      SQLITE_FILES=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
dbs = m.get('databases', {})
sqlite = dbs.get('sqlite', [])
if isinstance(sqlite, list):
    print('\n'.join(sqlite))
      " 2>/dev/null || true)
      if [ -n "$SQLITE_FILES" ]; then
        echo "$SQLITE_FILES" | while read -r db_path; do
          [ -z "$db_path" ] && continue
          db_name=$(basename "$db_path" | tr -c '[:alnum:]._-' '_')
          echo "  Dumping SQLite (WAL-safe): $db_path"
          # Use sqlite3 .backup on remote host for WAL-safe copy, then rsync
          ssh "$HOST" "sqlite3 '$db_path' '.backup /tmp/host-backup-sqlite-${db_name}'" 2>/dev/null && {
            rsync -avP --partial-dir=.rsync-partial --timeout=300 -e "ssh $SSH_OPTS" "$HOST:/tmp/host-backup-sqlite-${db_name}" "$BACKUP_DIR/sqlite_${db_name}" 2>/dev/null && {
              FILE_COUNT=$((FILE_COUNT + 1))
              # Verify integrity
              ssh "$HOST" "sqlite3 '/tmp/host-backup-sqlite-${db_name}' 'PRAGMA integrity_check;'" 2>/dev/null | grep -q "ok" && echo "    OK (integrity verified): sqlite_${db_name}" || echo "    WARNING: integrity check failed for sqlite_${db_name}"
              _compute_sha256 "$BACKUP_DIR/sqlite_${db_name}" > "$BACKUP_DIR/sqlite_${db_name}.sha256"
            } || echo "    FAILED: rsync for $db_name"
            ssh "$HOST" "rm -f /tmp/host-backup-sqlite-${db_name}" 2>/dev/null || true
          } || echo "    FAILED: sqlite3 .backup for $db_path (may need sudo or database not accessible)"
        done
      fi
      ;;
    wiki)
      # Wiki vault S3 mount: capture rclone config and verify mount
      echo "  Backing up wiki S3 mount config..."
      ssh "$HOST" "cat ~/.config/rclone/rclone.conf 2>/dev/null" > "$BACKUP_DIR/wiki-rclone.conf" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      # Check wiki mount status
      ssh "$HOST" "mountpoint -q ~/wiki 2>/dev/null && echo 'wiki mount: active' || echo 'wiki mount: not mounted'" > "$BACKUP_DIR/wiki-mount-status.txt" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
      # Capture fstab entry if present
      ssh "$HOST" "grep wiki /etc/fstab 2>/dev/null || echo 'no wiki fstab entry'" > "$BACKUP_DIR/wiki-fstab.txt" 2>/dev/null && FILE_COUNT=$((FILE_COUNT + 1)) || true
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
  for g in base caddy_domains hermes databases other_services apt wiki; do
    backup_group "$g"
  done
else
  for g in $SELECTED_GROUPS; do
    # Check if the group is recognized
    case "$g" in
      base|caddy_domains|hermes|databases|other_services|apt|wiki) backup_group "$g" ;;
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
PRIMARY_ARCHIVE="$(dirname "$BACKUP_DIR")/$BACKUP_NAME"
FALLBACK_ARCHIVE="${BACKUP_DIR}.tar.gz"
if [ -f "$PRIMARY_ARCHIVE" ]; then
  echo "Archive: $PRIMARY_ARCHIVE"
  du -sh "$PRIMARY_ARCHIVE"
elif [ -f "$FALLBACK_ARCHIVE" ]; then
  echo "Archive: $FALLBACK_ARCHIVE"
  du -sh "$FALLBACK_ARCHIVE"
fi
echo "=== Backup complete: $(date) ==="
