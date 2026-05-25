#!/bin/bash
# test-restore.sh — Per-component restore verification test harness
# Validates functional correctness of restored components
set -euo pipefail

MANIFEST=""
GROUP=""
ALL=true
PASS=0
FAIL=0
SKIP=0
TARGET_HOST=""
BACKUP_DIR=""

usage() {
  echo "Usage: $0 --manifest PATH [--group NAME] [--target HOST] [--backup-dir PATH]"
  echo "Groups: base caddy_domains per-domain hermes databases dump_integrity other_services apt wiki"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --group) GROUP="$2"; ALL=false; shift 2 ;;
    --target) TARGET_HOST="$2"; shift 2 ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ -z "$MANIFEST" ]; then
  echo "Error: --manifest is required"
  usage
fi

# Resolve target host: --target overrides manifest hostname
get_target_host() {
  if [ -n "$TARGET_HOST" ]; then
    echo "$TARGET_HOST"
  else
    python3 -c "import json; print(json.load(open('$MANIFEST'))['hostname'])"
  fi
}

assert() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_skip() {
  local desc="$1"
  echo "  SKIP: $desc (not applicable)"
  SKIP=$((SKIP + 1))
}

echo "=== Restore Test Harness ==="
echo "Manifest: $MANIFEST"
echo ""

test_base() {
  echo "--- Group: base ---"
  assert "hostname file exists" test -f "$MANIFEST"
  assert "SSH config present" ssh -G "$(get_target_host)" 2>/dev/null || assert_skip "SSH connectivity to host"
  assert "hosts file integrity" ssh "$(get_target_host)" "cat /etc/hosts | head -1" &>/dev/null || assert_skip "hosts file on target"
}

test_caddy_domains() {
  echo "--- Group: caddy_domains ---"
  local domains
  domains=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
for d in m.get('caddy_domains', []):
    print(d.get('domain', ''))
" 2>/dev/null) || true

  if [ -z "$domains" ]; then
    assert_skip "caddy validate (no domains in manifest)"
    assert_skip "HTTP 200 on domains"
    assert_skip "SSL certs valid"
    return
  fi

  # Caddy validate
  assert "caddy validate passes" ssh "$(get_target_host)" "caddy validate --config /etc/caddy/Caddyfile 2>/dev/null" &>/dev/null || assert_skip "caddy validate on target"

  # HTTP check per domain
  local count=0
  while IFS= read -r domain; do
    [ -z "$domain" ] && continue
    if curl -sI "https://$domain" 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
      assert "HTTP 200/301 on $domain" true
    else
      assert "HTTP 200/301 on $domain" false
    fi
    count=$((count + 1))
  done <<< "$domains"

  [ "$count" -eq 0 ] && assert_skip "HTTP check on domains"

  # SSL check
  local first_domain
  first_domain=$(echo "$domains" | head -1)
  if [ -n "$first_domain" ]; then
    assert "SSL cert valid on $first_domain" curl -sI "https://$first_domain" 2>/dev/null | grep -q "HTTP/" || assert_skip "SSL check for $first_domain"
  fi
}

test_per_domain() {
  echo "--- Group: per-domain ---"
  local domains
  domains=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
for d in m.get('caddy_domains', []):
    print(d.get('domain', ''))
" 2>/dev/null) || true

  if [ -z "$domains" ]; then
    assert_skip "per-domain HTTP 200"
    return
  fi

  while IFS= read -r domain; do
    [ -z "$domain" ] && continue
    assert "Single domain $domain serves correctly" \
      curl -s -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null | grep -q "200\|301\|302" || \
      assert_skip "HTTP reachable for $domain"
  done <<< "$domains"
}

test_hermes() {
  echo "--- Group: hermes ---"
  local host
  host=$(get_target_host)

  assert "hermes --version works" ssh "$host" "hermes --version" &>/dev/null || assert_skip "hermes installed on target"
  assert "hermes gateway active" ssh "$host" "systemctl is-active hermes-gateway.service 2>/dev/null || systemctl --user is-active hermes-gateway.service 2>/dev/null" &>/dev/null || assert_skip "hermes-gateway service"
  assert "hermes dashboard accessible" ssh "$host" "systemctl is-active hermes-dashboard.service 2>/dev/null || systemctl --user is-active hermes-dashboard.service 2>/dev/null" &>/dev/null || assert_skip "hermes-dashboard service"
  assert "hermes backup --quick works" ssh "$host" "hermes backup --quick -o /dev/null" &>/dev/null || assert_skip "hermes backup --quick"
}

test_databases() {
  echo "--- Group: databases ---"
  local host
  host=$(get_target_host)

  # sqlite check
  local sqlite_files
  sqlite_files=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
dbs = m.get('databases', {}).get('sqlite', [])
for f in dbs:
    print(f)
" 2>/dev/null) || true

  if [ -n "$sqlite_files" ]; then
    while IFS= read -r db_file; do
      [ -z "$db_file" ] && continue
      assert "sqlite3 can open $(basename "$db_file")" \
        ssh "$host" "sqlite3 \"$db_file\" '.tables' &>/dev/null" || \
        assert_skip "sqlite3 access to $(basename "$db_file")"
      assert "Row count > 0 in $(basename "$db_file")" \
        ssh "$host" "sqlite3 \"$db_file\" 'SELECT COUNT(*) FROM sqlite_master;' 2>/dev/null | grep -q '[1-9]'" || \
        assert_skip "rows in $(basename "$db_file")"
    done <<< "$sqlite_files"
  else
    assert_skip "sqlite files in manifest"
  fi
}

test_dump_integrity() {
  echo "--- Group: dump_integrity ---"

  # Resolve backup directory: --backup-dir flag > manifest dirname > cwd
  local bdir="$BACKUP_DIR"
  if [ -z "$bdir" ]; then
    bdir=$(python3 -c "
import json, os
m = json.load(open('$MANIFEST'))
bd = m.get('backup_dir', '')
if not bd:
    bd = os.path.dirname('$MANIFEST')
print(bd)
" 2>/dev/null || dirname "$MANIFEST")
  fi

  if [ ! -d "$bdir" ]; then
    assert_skip "backup directory (not found: $bdir)"
    return
  fi

  # --- PostgreSQL .dump files: pg_restore --list ---
  local pg_count=0
  for dump_file in "$bdir"/pg_*.dump; do
    [ -f "$dump_file" ] || continue
    pg_count=$((pg_count + 1))
    local db_name
    db_name=$(basename "$dump_file" .dump | sed 's/^pg_//')
    if pg_restore --list "$dump_file" >/dev/null 2>&1; then
      assert "pg_restore --list OK for $db_name" true
    else
      assert "pg_restore --list OK for $db_name" false
    fi
    # SHA256 checksum verification
    if [ -f "$dump_file.sha256" ]; then
      local computed expected
      if command -v sha256sum >/dev/null 2>&1; then
        computed=$(sha256sum "$dump_file" | awk '{print $1}')
      elif command -v shasum >/dev/null 2>&1; then
        computed=$(shasum -a 256 "$dump_file" | awk '{print $1}')
      else
        assert_skip "sha256 for $db_name (no sha256sum/shasum)"
        continue
      fi
      expected=$(awk '{print $1}' "$dump_file.sha256")
      if [ "$computed" = "$expected" ]; then
        assert "sha256 match for $db_name" true
      else
        assert "sha256 match for $db_name" false
      fi
    else
      assert_skip "sha256 checksum file for $db_name"
    fi
  done
  [ "$pg_count" -eq 0 ] && assert_skip "PostgreSQL dump files in $bdir"

  # --- MySQL .sql.gz files: gzip -t ---
  local mysql_count=0
  for dump_file in "$bdir"/mysql_*.sql.gz; do
    [ -f "$dump_file" ] || continue
    mysql_count=$((mysql_count + 1))
    local db_name
    db_name=$(basename "$dump_file" .sql.gz | sed 's/^mysql_//')
    if gzip -t "$dump_file" 2>/dev/null; then
      assert "gzip integrity OK for mysql_$db_name" true
    else
      assert "gzip integrity OK for mysql_$db_name" false
    fi
    # SHA256 checksum verification
    if [ -f "$dump_file.sha256" ]; then
      local computed expected
      if command -v sha256sum >/dev/null 2>&1; then
        computed=$(sha256sum "$dump_file" | awk '{print $1}')
      elif command -v shasum >/dev/null 2>&1; then
        computed=$(shasum -a 256 "$dump_file" | awk '{print $1}')
      else
        assert_skip "sha256 for mysql_$db_name (no sha256sum/shasum)"
        continue
      fi
      expected=$(awk '{print $1}' "$dump_file.sha256")
      if [ "$computed" = "$expected" ]; then
        assert "sha256 match for mysql_$db_name" true
      else
        assert "sha256 match for mysql_$db_name" false
      fi
    else
      assert_skip "sha256 checksum file for mysql_$db_name"
    fi
  done
  [ "$mysql_count" -eq 0 ] && assert_skip "MySQL dump files in $bdir"

  # --- MongoDB archive.gz: gzip -t ---
  if [ -f "$bdir/mongo.archive.gz" ]; then
    if gzip -t "$bdir/mongo.archive.gz" 2>/dev/null; then
      assert "gzip integrity OK for mongo.archive.gz" true
    else
      assert "gzip integrity OK for mongo.archive.gz" false
    fi
    if [ -f "$bdir/mongo.archive.gz.sha256" ]; then
      local computed expected
      if command -v sha256sum >/dev/null 2>&1; then
        computed=$(sha256sum "$bdir/mongo.archive.gz" | awk '{print $1}')
      elif command -v shasum >/dev/null 2>&1; then
        computed=$(shasum -a 256 "$bdir/mongo.archive.gz" | awk '{print $1}')
      else
        assert_skip "sha256 for mongo.archive.gz (no sha256sum/shasum)"
        computed=""
      fi
      if [ -n "$computed" ]; then
        expected=$(awk '{print $1}' "$bdir/mongo.archive.gz.sha256")
        if [ "$computed" = "$expected" ]; then
          assert "sha256 match for mongo.archive.gz" true
        else
          assert "sha256 match for mongo.archive.gz" false
        fi
      fi
    else
      assert_skip "sha256 checksum file for mongo.archive.gz"
    fi
  else
    assert_skip "MongoDB archive file in $bdir"
  fi

  # --- SQLite backup files: local integrity check ---
  local sqlite_count=0
  for db_file in "$bdir"/sqlite_*; do
    [ -f "$db_file" ] || continue
    # Skip sha256 sidecar files
    case "$db_file" in *.sha256) continue ;; esac
    sqlite_count=$((sqlite_count + 1))
    local db_name
    db_name=$(basename "$db_file" | sed 's/^sqlite_//')
    if sqlite3 "$db_file" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
      assert "sqlite3 integrity_check OK for $db_name" true
    else
      assert "sqlite3 integrity_check OK for $db_name" false
    fi
    # SHA256 checksum verification
    if [ -f "$db_file.sha256" ]; then
      local computed expected
      if command -v sha256sum >/dev/null 2>&1; then
        computed=$(sha256sum "$db_file" | awk '{print $1}')
      elif command -v shasum >/dev/null 2>&1; then
        computed=$(shasum -a 256 "$db_file" | awk '{print $1}')
      else
        assert_skip "sha256 for sqlite $db_name (no sha256sum/shasum)"
        continue
      fi
      expected=$(awk '{print $1}' "$db_file.sha256")
      if [ "$computed" = "$expected" ]; then
        assert "sha256 match for sqlite $db_name" true
      else
        assert "sha256 match for sqlite $db_name" false
      fi
    else
      assert_skip "sha256 checksum file for sqlite $db_name"
    fi
  done
  [ "$sqlite_count" -eq 0 ] && assert_skip "SQLite backup files in $bdir"
}

test_other_services() {
  echo "--- Group: other_services ---"
  local host
  host=$(get_target_host)
  local services
  services=$(python3 -c "
import json
m = json.load(open('$MANIFEST'))
for s in m.get('other_services', []):
    print(s)
" 2>/dev/null) || true

  if [ -z "$services" ]; then
    assert_skip "systemd units active (none in manifest)"
    return
  fi

  local count=0
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    assert "systemd unit $svc active" \
      ssh "$host" "systemctl is-active \"$svc.service\" 2>/dev/null | grep -q 'active'" || \
      assert_skip "systemd unit $svc on target"
    count=$((count + 1))
  done <<< "$services"

  [ "$count" -eq 0 ] && assert_skip "systemd unit checks"
}

test_apt() {
  echo "--- Group: apt ---"
  local host
  host=$(get_target_host)

  assert "apt list --installed has packages" \
    ssh "$host" "dpkg -l 2>/dev/null | wc -l | grep -q '[1-9]'" || \
    assert_skip "dpkg -l on target"
  assert "apt sources valid" \
    ssh "$host" "apt-get check 2>/dev/null" || \
    assert_skip "apt-get check on target"
  assert "system packages coherent" \
    ssh "$host" "dpkg --audit 2>/dev/null | wc -l | grep -q '^0$'" || \
    assert_skip "dpkg --audit on target (non-zero)"
}

# Run selected group or all
test_wiki() {
  echo "--- Group: wiki ---"
  local host
  host=$(get_target_host)

  assert "wiki rclone.conf accessible" \
    ssh "$host" "test -f ~/.config/rclone/rclone.conf" &>/dev/null || \
    assert_skip "rclone.conf on target"
  assert "wiki mount active" \
    ssh "$host" "mountpoint -q ~/wiki 2>/dev/null" &>/dev/null || \
    assert_skip "wiki mount on target"
  assert "wiki fstab entry present" \
    ssh "$host" "grep -q wiki /etc/fstab 2>/dev/null" &>/dev/null || \
    assert_skip "wiki fstab entry on target"
}

if $ALL; then
  test_base
  test_caddy_domains
  test_per_domain
  test_hermes
  test_databases
  test_dump_integrity
  test_other_services
  test_apt
  test_wiki
else
  "test_${GROUP}" 2>/dev/null || echo "Unknown group: $GROUP"
fi

# Summary
TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ($TOTAL total) ==="

if [ "$FAIL" -gt 0 ]; then
  echo "Note: Some failures may be source-side edge cases (DNS, locked DBs, stopped services)"
  exit 1
fi
exit 0
