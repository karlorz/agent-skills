#!/usr/bin/env bash
# Reinstall KEEP plugins after a user GitHub marketplace re-pin.
# Tries CLI plugin install first; falls back to Dashboard InstallUserPlugin.
# Never prints tokens.
set -euo pipefail

# shellcheck source=resolve-cursor-agent.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-cursor-agent.sh"

DASHBOARD_BASE="${CURSOR_DASHBOARD_BASE:-https://api2.cursor.sh}"
SPECS=(
  skillwiki@llm-wiki
  vault-sync@llm-wiki
  grok-search@karlorz-agent-skills
  deep-research@karlorz-agent-skills
)

token_from_keychain() {
  if [[ -n "${CURSOR_AUTH_TOKEN:-}" ]]; then
    printf '%s' "$CURSOR_AUTH_TOKEN"
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]] && command -v security >/dev/null 2>&1; then
    /usr/bin/security find-generic-password -s cursor-access-token -a cursor-user -w 2>/dev/null || true
    return 0
  fi
  printf ''
}

try_cli_install() {
  local spec="$1"
  local out st
  set +e
  out="$("$AGENT" plugin install "$spec" 2>&1)"
  st=$?
  set -e
  if [[ $st -eq 0 ]]; then
    echo "CLI install ok: $spec"
    return 0
  fi
  if echo "$out" | grep -qi 'too many arguments'; then
    return 2
  fi
  echo "CLI install failed for $spec" >&2
  echo "$out" | grep -vi token >&2 || true
  return 1
}

dashboard_install() {
  local tok="$1"
  python3 - "$DASHBOARD_BASE" "$tok" "${SPECS[@]}" <<'PY'
import json, sys, urllib.request, urllib.error

base = sys.argv[1].rstrip("/")
tok = sys.argv[2]
if not tok:
    print("FAIL: no CURSOR_AUTH_TOKEN or keychain token", file=sys.stderr)
    raise SystemExit(1)

KEEP = {}
for spec in sys.argv[3:]:
    name, _, mkt = spec.partition("@")
    if not name or not mkt:
        print(f"FAIL: bad KEEP spec {spec!r}", file=sys.stderr)
        raise SystemExit(1)
    KEEP.setdefault(mkt, []).append(name)

def rpc(method, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{base}/aiserver.v1.DashboardService/{method}",
        data=data,
        headers={
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "x-cursor-client-type": "cli",
            "x-cursor-client-version": "cli-keep-install",
            "x-ghost-mode": "true",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        print(f"FAIL: {method} HTTP {e.code}", file=sys.stderr)
        print(raw[:300].replace(tok, "[redacted]"), file=sys.stderr)
        raise SystemExit(1)

markets = rpc("ListMarketplaces", {})
wanted = {m.get("name"): m for m in markets.get("marketplaces") or []}
installs = rpc("ListUserPluginInstalls", {})
installed = set()
for inst in installs.get("installs") or []:
    plugin = inst.get("plugin") or {}
    name = plugin.get("name")
    if name:
        installed.add(name)

for mkt, names in KEEP.items():
    row = wanted.get(mkt)
    if not row:
        print(f"FAIL: marketplace {mkt} not in ListMarketplaces", file=sys.stderr)
        raise SystemExit(1)
    plist = rpc("ListMarketplacePlugins", {"marketplaceId": str(row["id"]), "pageSize": 100})
    by_name = {p.get("name"): p for p in plist.get("plugins") or []}
    for name in names:
        p = by_name.get(name)
        if not p:
            print(f"FAIL: {name} not in {mkt} catalog (finish rempin first)", file=sys.stderr)
            raise SystemExit(1)
        if name in installed:
            print(f"already installed: {name}")
            continue
        resp = rpc("InstallUserPlugin", {"pluginId": str(p["id"])})
        inst = (resp.get("install") or {})
        plugin = inst.get("plugin") or {}
        print(f"installed {plugin.get('name') or name} enabled={inst.get('isEnabled')}")
PY
}

echo "KEEP plugin reinstall via $AGENT"

for spec in "${SPECS[@]}"; do
  set +e
  try_cli_install "$spec"
  st=$?
  set -e
  if [[ $st -eq 0 ]]; then
    continue
  fi
  if [[ $st -eq 2 ]]; then
    echo "CLI has no plugin install; using Dashboard API"
    TOK="$(token_from_keychain)"
    dashboard_install "$TOK"
    exit 0
  fi
  echo "FAIL: CLI install error for $spec" >&2
  exit 1
done
exit 0
