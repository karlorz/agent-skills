#!/bin/bash
# research-host.sh — Post-discovery research on detected services
# Reads manifest and generates research queries for deep-research skill
# Usage: bash research-host.sh <manifest.json> [--output DIR]
set -euo pipefail

MANIFEST="${1:-}"
OUTPUT_DIR=""

shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "Usage: $0 <manifest.json> [--output DIR]" >&2
  exit 1
fi

HOST=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['hostname'])")
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/host-backup-${HOST}-research}"

mkdir -p "$OUTPUT_DIR"

echo "=== Post-Discovery Research: $HOST ==="
echo "Manifest: $MANIFEST"
echo "Output:   $OUTPUT_DIR"
echo ""

# Generate research queries from manifest
python3 -c "
import json, os

manifest = json.load(open('$MANIFEST'))
host = manifest['hostname']
output_dir = '$OUTPUT_DIR'
queries = []

# Hermes version research
hermes = manifest.get('hermes', {})
if hermes.get('version'):
    ver = hermes['version']
    queries.append({
        'topic': f'Hermes Agent v{ver} changelog and known issues',
        'query': f'hermes-agent {ver} release notes changelog breaking changes',
        'purpose': 'Check for known issues, security patches, or upgrade recommendations',
        'priority': 'medium'
    })

# Caddy version/config research
domains = manifest.get('caddy_domains', [])
if domains:
    domain_list = [d.get('domain', '') for d in domains[:5]]
    queries.append({
        'topic': f'Caddy reverse proxy best practices for {len(domains)} domains',
        'query': 'caddy reverse proxy performance tuning security headers 2025 2026',
        'purpose': 'Recommend security headers, caching, and performance optimizations',
        'priority': 'low'
    })

# Database research
dbs = manifest.get('databases', {})
for db_type, items in dbs.items():
    if items:
        queries.append({
            'topic': f'{db_type.title()} backup best practices',
            'query': f'{db_type} backup restore best practices production',
            'purpose': f'Validate {db_type} backup approach and identify risks',
            'priority': 'medium' if db_type in ('postgres', 'mysql') else 'low'
        })

# OS research
os_id = manifest.get('os', '')
os_ver = manifest.get('os_version', '')
if os_id:
    queries.append({
        'topic': f'{os_id} {os_ver} security advisories',
        'query': f'{os_id} {os_ver} security update advisory CVE',
        'purpose': 'Check for critical security patches that should be applied before/after restore',
        'priority': 'high'
    })

# Write queries to files
for i, q in enumerate(queries):
    filename = os.path.join(output_dir, f'query-{i+1}-{q[\"priority\"]}.json')
    with open(filename, 'w') as f:
        json.dump(q, f, indent=2)
    print(f'  [{q[\"priority\"]}] {q[\"topic\"]}')
    print(f'    Query: {q[\"query\"]}')
    print(f'    File:  {filename}')
    print()

print(f'Total: {len(queries)} research queries generated')
print(f'Output: {output_dir}')
" 2>/dev/null

echo ""
echo "=== Research queries generated ==="
echo "Run with deep-research skill:"
echo "  /deep-research \"$(cat "$OUTPUT_DIR"/query-*.json 2>/dev/null | python3 -c "import json,sys; [print(json.loads(l)['topic']) for l in sys.stdin if l.strip().startswith('{')]" 2>/dev/null | head -1)\""
echo ""
echo "Or invoke the deep-research skill for each query in $OUTPUT_DIR/"
