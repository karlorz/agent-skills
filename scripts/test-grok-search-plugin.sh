#!/usr/bin/env bash
# Grok-search-specific HTTP MCP pin, env interpolation, skill tools, and secret scan.
# Catalog/manifest inventory is covered by scripts/test-dev-loop-release-tooling.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="$ROOT/skills/grok-search"

python3 - "$PLUGIN_ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
mcp_path = root / ".mcp.json"
skill_path = root / "skills" / "grok-search" / "SKILL.md"
readme_path = root / "README.md"
manifest_path = root / ".claude-plugin" / "plugin.json"
example_path = root / "cursor-cli-mcp.example.json"
changelog_path = root / "CHANGELOG.md"

# 1. Non-existence of removed stdio / legacy files in live plugin tree
http_example = root / "cursor-cli-http.example.json"
if http_example.exists():
    raise SystemExit(f"{http_example}: cursor-cli-http.example.json must not exist in live plugin tree")

for legacy_script in ("run-grok-search.sh", "migrate-from-user-mcp.py"):
    legacy_path = root / "scripts" / legacy_script
    if legacy_path.exists():
        raise SystemExit(f"{legacy_path}: {legacy_script} must not exist in skills/grok-search/scripts/")

texts = {}
for path in (mcp_path, skill_path, readme_path, manifest_path, example_path, changelog_path):
    try:
        texts[path] = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"missing {path}") from None

# 2. Plugin .mcp.json contract
data = json.loads(texts[mcp_path])
servers = data.get("mcpServers")
if not isinstance(servers, dict) or set(servers.keys()) != {"grok-search"}:
    raise SystemExit(f"{mcp_path}: mcpServers must contain exactly one key: grok-search")

server = servers["grok-search"]
if server.get("type") != "http":
    raise SystemExit(f"{mcp_path}: type must be http")
if server.get("url") != "${GROK_SEARCH_MCP_URL}":
    raise SystemExit(f"{mcp_path}: url must be exactly ${{GROK_SEARCH_MCP_URL}}")

headers = server.get("headers")
if not isinstance(headers, dict) or headers.get("Authorization") != "Bearer ${GROK_SEARCH_MCP_TOKEN}":
    raise SystemExit(f"{mcp_path}: headers.Authorization must be exactly Bearer ${{GROK_SEARCH_MCP_TOKEN}}")

for forbidden in ("command", "args", "env"):
    if forbidden in server:
        raise SystemExit(f"{mcp_path}: server must not contain {forbidden!r}")
if "grok-search-http" in servers:
    raise SystemExit(f"{mcp_path}: must not contain grok-search-http key")

# 3. Example config cursor-cli-mcp.example.json contract
ex = json.loads(texts[example_path])
ex_servers = ex.get("mcpServers")
if not isinstance(ex_servers, dict) or set(ex_servers.keys()) != {"grok-search"}:
    raise SystemExit(f"{example_path}: mcpServers must contain exactly one key: grok-search")

ex_server = ex_servers["grok-search"]
if ex_server.get("type") != "http":
    raise SystemExit(f"{example_path}: type must be http")
if ex_server.get("url") != "${GROK_SEARCH_MCP_URL}":
    raise SystemExit(f"{example_path}: url must be exactly ${{GROK_SEARCH_MCP_URL}}")
ex_headers = ex_server.get("headers")
if not isinstance(ex_headers, dict) or ex_headers.get("Authorization") != "Bearer ${GROK_SEARCH_MCP_TOKEN}":
    raise SystemExit(f"{example_path}: headers.Authorization must be exactly Bearer ${{GROK_SEARCH_MCP_TOKEN}}")
for forbidden in ("command", "args", "env"):
    if forbidden in ex_server:
        raise SystemExit(f"{example_path}: server must not contain {forbidden!r}")

# 4. JSON configs must not have hardcoded IPs or domains
for json_path in (mcp_path, example_path, manifest_path):
    json_text = texts[json_path]
    if "100.76.134.104" in json_text:
        raise SystemExit(f"{json_path}: must not contain hardcoded IP 100.76.134.104")
    if "search.termolo.com" in json_text:
        raise SystemExit(f"{json_path}: must not contain domain search.termolo.com")
    if "search.karldigi.dev" in json_text:
        raise SystemExit(f"{json_path}: must not contain domain search.karldigi.dev")

# 5. Manifest (.claude-plugin/plugin.json)
manifest = json.loads(texts[manifest_path])
if manifest.get("version") != "0.1.7":
    raise SystemExit(f"{manifest_path}: version must be 0.1.7")
manifest_desc = manifest.get("description", "")
if "HTTP" not in manifest_desc and "http" not in manifest_desc:
    raise SystemExit(f"{manifest_path}: description must mention HTTP MCP")
if "stdio" in manifest_desc.lower():
    raise SystemExit(f"{manifest_path}: description must not mention stdio-as-default")

# 6. CHANGELOG.md
changelog_text = texts[changelog_path]
if "0.1.7" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must mention version 0.1.7")
if "2026-08-25" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must mention release date 2026-08-25")

# 7. SKILL.md contract
skill_text = texts[skill_path]
if not skill_text.startswith("---\n"):
    raise SystemExit(f"{skill_path}: missing frontmatter")
end = skill_text.find("\n---", 4)
if end < 0:
    raise SystemExit(f"{skill_path}: missing frontmatter terminator")
fm = skill_text[4:end]
body = skill_text[end + 4 :]

if not re.search(r"^name:\s*grok-search\s*$", fm, re.M):
    raise SystemExit(f"{skill_path}: name must be grok-search")
if "This skill should be used when" not in fm:
    raise SystemExit(f"{skill_path}: description must use third-person trigger")

for tool in ("plan_intent", "web_search", "get_sources", "web_fetch", "web_map"):
    if tool not in body:
        raise SystemExit(f"{skill_path}: missing tool {tool}")

if "mcp__plugin_" in body:
    raise SystemExit(f"{skill_path}: must not hard-code mcp__plugin_ prefixes")

if len(skill_text.split()) > 1500:
    raise SystemExit(f"{skill_path}: too long ({len(skill_text.split())} words > 1500)")

if "GROK_SEARCH_MCP_URL" not in body or "GROK_SEARCH_MCP_TOKEN" not in body:
    raise SystemExit(f"{skill_path}: must mention GROK_SEARCH_MCP_URL and GROK_SEARCH_MCP_TOKEN")
if "https://search.karldigi.dev/mcp" not in body:
    raise SystemExit(f"{skill_path}: must mention production URL https://search.karldigi.dev/mcp")
if "check_readiness.py" not in body:
    raise SystemExit(f"{skill_path}: must require check_readiness.py before MCP tools")
if "HTTP" not in body and "http" not in body:
    raise SystemExit(f"{skill_path}: must mention HTTP MCP")
if "first-run" not in body.lower() and "first run" not in body.lower():
    raise SystemExit(f"{skill_path}: must mention first-run setup / ask if URL or token missing")
if "grok-search-http" not in body:
    raise SystemExit(f"{skill_path}: must mention leftover grok-search-http alias note")
if "never dual-call" not in body.lower() and "do not dual-call" not in body.lower():
    raise SystemExit(f"{skill_path}: must advise never dual-calling grok-search-http alias")
if "stdio (default)" in body.lower() or "stdio as default" in body.lower() or "via stdio mcp" in body.lower():
    raise SystemExit(f"{skill_path}: must not present stdio as default")

# 8. README.md contract
readme_text = texts[readme_path]
if "GROK_SEARCH_MCP_URL" not in readme_text or "GROK_SEARCH_MCP_TOKEN" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention GROK_SEARCH_MCP_URL and GROK_SEARCH_MCP_TOKEN")

if "https://search.karldigi.dev/mcp" not in readme_text:
    raise SystemExit(f"{readme_path}: must document production endpoint https://search.karldigi.dev/mcp")
if "gateway-keys" not in readme_text:
    raise SystemExit(f"{readme_path}: must document gateway-keys bearer tokens")
if "http://100.76.134.104:8800/mcp" not in readme_text:
    raise SystemExit(f"{readme_path}: must document Tailscale endpoint http://100.76.134.104:8800/mcp")
if "https://search.termolo.com/mcp" not in readme_text:
    raise SystemExit(f"{readme_path}: must document Cloudflare Access endpoint https://search.termolo.com/mcp")

if "plugin-chain" not in readme_text and "plugin-grok-search-grok-search" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention plugin-chain or plugin-grok-search-grok-search")
if "agent mcp list" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention agent mcp list diagnostic note")
if "not the proof of install" not in readme_text.lower() and "diagnostic gap" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must note agent mcp list is not proof of install / diagnostic gap")
if "required for `agent mcp list`" in readme_text or "required for agent mcp list" in readme_text:
    raise SystemExit(f"{readme_path}: mcp.json wrapper must not be marked required")
if "optional" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must describe wrapper as optional")

if "~/.config/grok-search/http-mcp.token" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention ~/.config/grok-search/http-mcp.token token path")
if "archive/skills/grok-search-stdio/" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention archive/skills/grok-search-stdio/")
if "0.0.0.0" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention never bind to 0.0.0.0")
if "inbound /mcp" not in readme_text.lower() and "/mcp is not" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must note inbound /mcp is not outbound httpx")
if "mcp.env" not in readme_text:
    raise SystemExit(f"{readme_path}: must note HTTP does not auto-source mcp.env")

# 9. Secret scan
blob = "".join(texts[p] for p in (manifest_path, mcp_path, skill_path, readme_path, example_path, changelog_path))
allowed_bearer = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
allowed_url = "${GROK_SEARCH_MCP_URL}"
allowed_prod = "https://search.karldigi.dev/mcp"
allowed_admin = "https://search.karldigi.dev/admin/gateway-keys"
scanned = (
    blob.replace(allowed_bearer, "")
    .replace(allowed_url, "")
    .replace(allowed_prod, "")
    .replace(allowed_admin, "")
    .replace("Bearer-only", "")
    .replace("Bearer is", "")
)

for needle in ("code.guda.studio", "gsk_", "tvly-", "Bearer "):
    if needle in scanned:
        raise SystemExit(f"forbidden token {needle!r} in plugin files")
if "search.karldigi.dev" in scanned:
    raise SystemExit(
        "forbidden leftover search.karldigi.dev outside the documented production/admin URLs"
    )

PY

printf 'test-grok-search-plugin: all checks passed\n'
