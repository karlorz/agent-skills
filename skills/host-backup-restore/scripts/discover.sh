#!/bin/bash
# discover.sh — SSH-based host service discovery
# Parses Caddyfile, detects databases/services, outputs JSON manifest
# Groups services into: base, caddy_domains, per-domain, hermes, databases, other_services, apt
# Cached at /tmp/host-backup-{hostname}-manifest.json
# Use --redetect to force re-run
set -euo pipefail

HOST="${1:-}"
REDETECT="${2:-}"
CACHE_FILE="/tmp/host-backup-${HOST}-manifest.json"

if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname> [--redetect]" >&2
  exit 1
fi

# Use cache unless --redetect
if [ "$REDETECT" != "--redetect" ] && [ -f "$CACHE_FILE" ]; then
  cat "$CACHE_FILE"
  exit 0
fi

# Build manifest parts with python3 (avoid bash JSON bugs).
# Keep the Python program in a single-quoted heredoc so shell expansion cannot
# corrupt grep anchors, awk fields, or embedded quotes before Python runs.
python3 - "$HOST" <<'PY' | tee "$CACHE_FILE"
import json, subprocess, sys
from datetime import datetime, timezone

host = sys.argv[1]
manifest = {
    'hostname': host,
    'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    'caddy_domains': [],
    'hermes': {},
    'databases': {'sqlite': []},
    'other_services': [],
    'apt_sources': []
}

def ssh(cmd, timeout=10, raw=False, sudo=False):
    '''Run a command on the remote host and return output.'''
    try:
        cmd_with_sudo = ('sudo ' + cmd) if sudo else cmd
        r = subprocess.run(
            ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', host, cmd_with_sudo],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return r.stdout if raw else r.stdout.strip()
    except Exception:
        return ''

# ============================================
# Caddy — parse Caddyfile for domain→upstream
# Strategy: caddy adapt + jq (robust), fallback to line-based (legacy)
# ============================================
caddyfile = ssh('cat /etc/caddy/Caddyfile 2>/dev/null', timeout=5, sudo=True)
if caddyfile:
    # Primary: use caddy adapt + jq for robust JSON-based domain extraction
    caddy_json_str = ssh(
        'caddy adapt --config /etc/caddy/Caddyfile 2>/dev/null',
        timeout=15, sudo=True, raw=True
    )
    if caddy_json_str:
        try:
            caddy_json = json.loads(caddy_json_str)
            # Extract domain→upstream pairs from adapted JSON
            servers = caddy_json.get('apps', {}).get('http', {}).get('servers', {})
            for srv_name, srv in servers.items():
                for route in srv.get('routes', []):
                    domains = []
                    upstreams = []
                    for match in route.get('match', []):
                        domains.extend(match.get('host', []))
                    # Recursive search for reverse_proxy handlers (handles subroutes)
                    def find_upstreams(obj):
                        if isinstance(obj, dict):
                            if obj.get('handler') == 'reverse_proxy':
                                for up in obj.get('upstreams', []):
                                    dial = up.get('dial', '')
                                    if dial:
                                        upstreams.append(dial)
                            for v in obj.values():
                                find_upstreams(v)
                        elif isinstance(obj, list):
                            for item in obj:
                                find_upstreams(item)
                    find_upstreams(route)
                    for domain in domains:
                        upstream = upstreams[0] if upstreams else ''
                        manifest['caddy_domains'].append({'domain': domain, 'upstream': upstream})
            # Deduplicate by domain
            seen = set()
            deduped = []
            for entry in manifest['caddy_domains']:
                if entry['domain'] not in seen:
                    seen.add(entry['domain'])
                    deduped.append(entry)
            manifest['caddy_domains'] = deduped
        except (json.JSONDecodeError, KeyError, TypeError):
            # Fall through to line-based parser
            caddy_json_str = None

    # Fallback: line-based Caddyfile parsing (legacy, for hosts without caddy adapt)
    if not caddy_json_str:
        current_domain = None
        for line in caddyfile.split('\n'):
            line = line.strip()
            # Skip comments and blocks
            if line.startswith('#') or line.startswith('}') or line == '':
                continue
            # Domain lines (start with a hostname, end with {)
            skip_prefixes = ('http','/','reverse','respond','file_server','redir','basicauth','basic_auth','log','encode','tls','import','header','@','route','handle','{','acme','admin','common_name','debug','grace_period','grace_interval','issuer','key_type','ocsp_stapling','preferred_chains','protocol_name','renew_interval','trusted_roots','trusted_leaf_certificates')
            # Handle reverse_proxy BEFORE skip_prefixes filter (reverse matches reverse_proxy)
            if current_domain and line.startswith('reverse_proxy'):
                upstream = line.replace('reverse_proxy', '').strip()
                if manifest['caddy_domains']:
                    manifest['caddy_domains'][-1]['upstream'] = upstream
                continue
            if not line.startswith(skip_prefixes):
                if '{' in line:
                    current_domain = line.split()[0].strip().rstrip('{').strip()
                    manifest['caddy_domains'].append({'domain': current_domain, 'upstream': ''})

# ============================================
# Hermes version and home directory
# ============================================
hermes_version = ssh('hermes --version 2>/dev/null', timeout=8)
if hermes_version:
    first_line = hermes_version.split('\n')[0]
    manifest['hermes']['version'] = first_line.strip()

hermes_home = ssh('echo "$HERMES_HOME"', timeout=5)
if hermes_home:
    manifest['hermes']['home'] = hermes_home
else:
    # Default location
    test_home = ssh('test -d ~/.hermes && echo FOUND || echo NOTFOUND', timeout=5)
    if test_home == 'FOUND':
        manifest['hermes']['home'] = '~/.hermes'

# ============================================
# Databases — check common ports, list DBs, and find sqlite
# ============================================
for cmd, db_type in [
    ('pg_isready 2>/dev/null && echo ALIVE || true', 'postgres'),
    ('mysqladmin ping 2>/dev/null && echo ALIVE || true', 'mysql'),
    ('redis-cli ping 2>/dev/null | grep -q PONG && echo ALIVE || true', 'redis'),
    ('mongosh --eval \"db.version()\" 2>/dev/null && echo ALIVE || true', 'mongodb'),
]:
    result = ssh(cmd, timeout=8)
    if result and 'ALIVE' in result:
        manifest['databases'].setdefault(db_type, [])

# List actual database names for dump-capable engines
pg_dbs = ssh("psql -U postgres -lbt 2>/dev/null | awk -F'|' '{print $1}' | grep -v '^$' | grep -v '^template' | grep -v '^postgres$'", timeout=10, sudo=True)
if pg_dbs:
    db_list = [d.strip() for d in pg_dbs.split('\n') if d.strip()]
    if db_list:
        manifest['databases']['postgres'] = db_list

mysql_dbs = ssh("mysql -u root -e 'SHOW DATABASES;' -N 2>/dev/null | grep -v -E '^(Database|information_schema|performance_schema|mysql|sys)$'", timeout=10)
if mysql_dbs:
    db_list = [d.strip() for d in mysql_dbs.split('\n') if d.strip()]
    if db_list:
        manifest['databases']['mysql'] = db_list

# sqlite files — find .db files in home and common locations
sqlite_files = ssh(
    'find /root /home /var/lib /etc -name \"*.db\" '
    '-not -path \"*/proc/*\" -not -path \"*/snap/*\" '
    '-not -path \"*/.git/*\" -not -path \"*/node_modules/*\" '
    '2>/dev/null | head -20',
    timeout=15, sudo=True
)
if sqlite_files:
    manifest['databases']['sqlite'] = [f.strip() for f in sqlite_files.split('\n') if f.strip()]

# ============================================
# Systemd services — full inventory
# ============================================
# System-level services
sys_services = ssh(
    'systemctl list-units --type=service --no-pager --no-legend 2>/dev/null | '
    'grep -v cmux | head -40',
    timeout=15, sudo=True
)
if sys_services:
    for line in sys_services.split('\n'):
        parts = line.strip().split()
        if parts:
            svc = parts[0].replace('.service', '')
            if svc:
                manifest['other_services'].append(svc)

# User-level services (hermes-gateway, obsidian, xvfb etc.)
user_services = ssh(
    'systemctl --user list-units --type=service --no-pager --no-legend 2>/dev/null | '
    'head -20',
    timeout=10
)
if user_services:
    for line in user_services.split('\n'):
        parts = line.strip().split()
        if parts:
            svc = parts[0].replace('.service', '')
            if svc and svc not in manifest['other_services']:
                manifest['other_services'].append(svc)

# ============================================
# Apt sources
# ============================================
sources = ssh(
    'cat /etc/apt/sources.list 2>/dev/null; cat /etc/apt/sources.list.d/*.list 2>/dev/null || true',
    timeout=10, sudo=True
)
if sources:
    for line in sources.split('\n'):
        line = line.strip()
        if line.startswith('deb ') or line.startswith('deb-src '):
            manifest['apt_sources'].append(line)

# ============================================
# OS release info (for restore compatibility)
# ============================================
os_release = ssh('cat /etc/os-release 2>/dev/null', timeout=5)
if os_release:
    os_info = {}
    for line in os_release.split('\n'):
        if '=' in line:
            k, v = line.split('=', 1)
            os_info[k.strip()] = v.strip().strip('\"')
    manifest['os'] = os_info.get('ID', '')
    manifest['os_version'] = os_info.get('VERSION_ID', '')

# ============================================
# Architecture detection (for restore compat)
# ============================================
arch = ssh('uname -m 2>/dev/null', timeout=5)
if arch:
    manifest['arch'] = arch.strip()

print(json.dumps(manifest, indent=2))
PY
