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

# Build manifest parts with python3 (avoid bash JSON bugs)
python3 -c "
import json, subprocess, sys

host = sys.argv[1]
manifest = {
    'hostname': host,
    'timestamp': __import__('datetime').datetime.utcnow().isoformat() + 'Z',
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
# ============================================
caddyfile = ssh('cat /etc/caddy/Caddyfile 2>/dev/null', timeout=5, sudo=True)
if caddyfile:
    current_domain = None
    for line in caddyfile.split('\n'):
        line = line.strip()
        # Skip comments and blocks
        if line.startswith('#') or line.startswith('}') or line == '':
            continue
        # Domain lines (start with a hostname, end with {)
        skip_prefixes = ('http','/','reverse','respond','file_server','redir','basicauth','basic_auth','log','encode','tls','import','header','@','route','handle','{','acme','admin','common_name','debug','grace_period','grace_interval','issuer','key_type','ocsp_stapling','preferred_chains','protocol_name','renew_interval','trusted_roots','trusted_leaf_certificates')
        if not line.startswith(skip_prefixes):
            if '{' in line:
                current_domain = line.split()[0].strip().rstrip('{').strip()
                manifest['caddy_domains'].append({'domain': current_domain, 'upstream': ''})
            elif current_domain and line.startswith('reverse_proxy'):
                upstream = line.replace('reverse_proxy', '').strip()
                # Update the last domain's upstream
                if manifest['caddy_domains']:
                    manifest['caddy_domains'][-1]['upstream'] = upstream

    # Fallback: also try caddy validate --json for accurate parsing
    r = ssh('caddy validate --config /etc/caddy/Caddyfile --json 2>/dev/null', timeout=15, raw=True)
    if r:
        try:
            caddy_json = json.loads(r)
            if 'warnings' in caddy_json or 'errors' in caddy_json:
                pass  # Use our Caddyfile parsing above
        except json.JSONDecodeError:
            pass

# ============================================
# Hermes version and home directory
# ============================================
hermes_version = ssh('hermes --version 2>/dev/null', timeout=8)
if hermes_version:
    first_line = hermes_version.split('\n')[0]
    manifest['hermes']['version'] = first_line.strip()

hermes_home = ssh('echo \"\$HERMES_HOME\"', timeout=5)
if hermes_home:
    manifest['hermes']['home'] = hermes_home
else:
    # Default location
    test_home = ssh('test -d ~/.hermes && echo FOUND || echo NOTFOUND', timeout=5)
    if test_home == 'FOUND':
        manifest['hermes']['home'] = '~/.hermes'

# ============================================
# Databases — check common ports and sqlite
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
" "$HOST" | tee "$CACHE_FILE"
