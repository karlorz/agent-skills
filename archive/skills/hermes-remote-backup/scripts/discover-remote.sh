#!/bin/bash
# ============================================================================
# discover-remote.sh — SSH-based remote host discovery
# ============================================================================
# Detects Caddy configs, systemd services, databases, credstore, Hermes state
# on a remote Linux host. Outputs JSON to stdout.
#
# Usage:
#   bash discover-remote.sh <host> [--verbose]
#
# Example:
#   bash discover-remote.sh sg01
#   bash discover-remote.sh sg01 --verbose
#   bash discover-remote.sh sg02-agent     # via ~/.ssh/config alias
# ============================================================================

set -euo pipefail

HOST="${1:-}"
VERBOSE=false
for arg in "$@"; do
  [ "$arg" = "--verbose" ] && VERBOSE=true
done

if [ -z "$HOST" ]; then
  echo '{"error":"Usage: discover-remote.sh <host>","status":"error"}' >&2
  exit 1
fi

# Test SSH connectivity
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" "hostname" &>/dev/null; then
  echo "ERROR: Cannot SSH to $HOST (check key-based auth)" >&2
  echo '{"error":"ssh_failed","host":"'"$HOST"'","status":"error"}'
  exit 1
fi

$VERBOSE && echo "=== Discovering $HOST ===" >&2

# ── Caddy ────────────────────────────────────────────────────────────────────

CADDY_DOMAINS="[]"
CADDYFILE=$(ssh "$HOST" "cat /etc/caddy/Caddyfile 2>/dev/null || cat /etc/caddy/caddy.json 2>/dev/null || echo ''")
if [ -n "$CADDYFILE" ]; then
  # Parse Caddyfile for domain names (lines before { that aren't comments/blocks)
  DOMAINS=$(echo "$CADDYFILE" | grep -E '^[a-zA-Z0-9._*-]+\s*\{' | sed 's/\s*{$//' | tr '\n' ' ' 2>/dev/null || echo "")
  if [ -n "$DOMAINS" ]; then
    CADDY_DOMAINS=$(echo "$DOMAINS" | jq -R -c 'split(" ") | map(select(length > 0))' 2>/dev/null || echo "[\"$DOMAINS\"]")
  fi
  $VERBOSE && echo "  Caddy: $(echo "$CADDY_DOMAINS" | jq '. | length') domains" >&2
else
  $VERBOSE && echo "  Caddy: not found" >&2
fi

# ── Systemd ──────────────────────────────────────────────────────────────────

SYSTEMD_SERVICES=$(ssh "$HOST" "
  for svc in /etc/systemd/system/hermes*.service; do
    [ -f \"\$svc\" ] && basename \"\$svc\"
  done
  for svc in \$HOME/.config/systemd/user/hermes*.service; do
    [ -f \"\$svc\" ] && basename \"\$svc\"
  done
" 2>/dev/null || echo "")

SYSTEMD_JSON="[]"
if [ -n "$SYSTEMD_SERVICES" ]; then
  SYSTEMD_JSON=$(echo "$SYSTEMD_SERVICES" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")
  $VERBOSE && echo "  Systemd services: $(echo "$SYSTEMD_JSON" | jq '. | length')" >&2
fi

# ── Databases ────────────────────────────────────────────────────────────────

DB_INFO=$(ssh "$HOST" '
  result="{}"
  # PostgreSQL
  if command -v psql &>/dev/null; then
    pg_dbs=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datistemplate=false" 2>/dev/null | tr -d " " | tr "\n" "," | sed "s/,$//" || echo "")
    [ -n "$pg_dbs" ] && result=$(echo "$result" | jq --arg dbs "$pg_dbs" ". + {postgres: \$dbs}")
  fi
  # MySQL/MariaDB
  if command -v mysql &>/dev/null; then
    mysql_dbs=$(sudo mysql -e "SHOW DATABASES" 2>/dev/null | tail -n +2 | tr "\n" "," | sed "s/,$//" || echo "")
    [ -n "$mysql_dbs" ] && result=$(echo "$result" | jq --arg dbs "$mysql_dbs" ". + {mysql: \$dbs}")
  fi
  # Redis
  if command -v redis-cli &>/dev/null; then
    redis_ping=$(redis-cli ping 2>/dev/null || echo "")
    [ "$redis_ping" = "PONG" ] && result=$(echo "$result" | jq ". + {redis: true}")
  fi
  # MongoDB
  if command -v mongosh &>/dev/null || command -v mongo &>/dev/null; then
    result=$(echo "$result" | jq ". + {mongodb: true}")
  fi
  # SQLite databases in HERMES_HOME
  hermes_home="${HERMES_HOME:-$HOME/.hermes}"
  sqlite_dbs=""
  for db in "$hermes_home"/state.db "$hermes_home"/kanban.db; do
    [ -f "$db" ] && sqlite_dbs="$sqlite_dbs $(basename "$db")"
  done
  [ -n "$sqlite_dbs" ] && result=$(echo "$result" | jq --arg dbs "$sqlite_dbs" ". + {sqlite: \$dbs}")
  echo "$result"
' 2>/dev/null || echo "{}")

$VERBOSE && echo "  Databases: $(echo "$DB_INFO" | jq -c '.' 2>/dev/null || echo "none")" >&2

# ── Credstore ────────────────────────────────────────────────────────────────

CRED_FILES=$(ssh "$HOST" '
  hermes_home="${HERMES_HOME:-$HOME/.hermes}"
  files=""
  for f in "$hermes_home"/.env "$hermes_home"/auth.json "$hermes_home"/.anthropic_oauth.json; do
    [ -f "$f" ] && files="$files $f"
  done
  [ -f "$hermes_home/auth/google_oauth.json" ] && files="$files $hermes_home/auth/google_oauth.json"
  [ -f "$hermes_home/shared/nous_auth.json" ] && files="$files $hermes_home/shared/nous_auth.json"
  echo "$files"
' 2>/dev/null || echo "")

CRED_COUNT=0
[ -n "$CRED_FILES" ] && CRED_COUNT=$(echo "$CRED_FILES" | wc -w | tr -d ' ')
$VERBOSE && echo "  Cred files: $CRED_COUNT" >&2

# ── Hermes Version ───────────────────────────────────────────────────────────

HERMES_VERSION=$(ssh "$HOST" "hermes --version 2>/dev/null || echo 'not_installed'" 2>/dev/null || echo "unknown")
HERMES_HOME_REMOTE=$(ssh "$HOST" "echo \${HERMES_HOME:-\$HOME/.hermes}" 2>/dev/null || echo "unknown")
HERMES_HOME_SIZE=$(ssh "$HOST" "du -sh \${HERMES_HOME:-\$HOME/.hermes} 2>/dev/null | cut -f1" 2>/dev/null || echo "unknown")

$VERBOSE && echo "  Hermes: v$HERMES_VERSION at $HERMES_HOME_REMOTE ($HERMES_HOME_SIZE)" >&2

# ── OS Info ──────────────────────────────────────────────────────────────────

OS_INFO=$(ssh "$HOST" "cat /etc/os-release 2>/dev/null | head -5 | tr '\n' ';' || uname -a" 2>/dev/null || echo "unknown")
UPTIME=$(ssh "$HOST" "uptime -p 2>/dev/null || uptime" 2>/dev/null || echo "unknown")

# ── Output JSON ──────────────────────────────────────────────────────────────

jq -n \
  --arg host "$HOST" \
  --argjson caddy_domains "$CADDY_DOMAINS" \
  --argjson systemd_services "$SYSTEMD_JSON" \
  --argjson databases "$DB_INFO" \
  --arg cred_files "$CRED_FILES" \
  --arg cred_count "$CRED_COUNT" \
  --arg hermes_version "$HERMES_VERSION" \
  --arg hermes_home "$HERMES_HOME_REMOTE" \
  --arg hermes_home_size "$HERMES_HOME_SIZE" \
  --arg os_info "$OS_INFO" \
  --arg uptime "$UPTIME" \
  '{
    host: $host,
    status: "ok",
    discovered_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    caddy: { domains: $caddy_domains, present: ($caddy_domains | length > 0) },
    systemd: { services: $systemd_services, count: ($systemd_services | length) },
    databases: $databases,
    credstore: { files: $cred_files, count: ($cred_count | tonumber) },
    hermes: { version: $hermes_version, home: $hermes_home, size: $hermes_home_size },
    os: $os_info,
    uptime: $uptime
  }' 2>/dev/null || echo '{"status":"error","error":"jq_output_failed"}'