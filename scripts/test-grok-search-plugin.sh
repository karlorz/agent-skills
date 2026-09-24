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
repo_root = root.parent.parent
mcp_path = root / ".mcp.json"
skill_path = root / "skills" / "grok-search" / "SKILL.md"
readme_path = root / "README.md"
manifest_path = root / ".claude-plugin" / "plugin.json"
codex_manifest_path = root / ".codex-plugin" / "plugin.json"
example_path = root / "cursor-cli-mcp.example.json"
changelog_path = root / "CHANGELOG.md"
hooks_path = root / "claude-hooks" / "hooks.json"
hook_script_path = root / "claude-hooks" / "session-start.sh"
legacy_cursor_hook_path = root / "hooks" / "hooks.json"
cursor_manifest_path = root / ".cursor-plugin" / "plugin.json"
cursor_mcp_path = root / "mcp.json"
cursor_marketplace_path = repo_root / ".cursor-plugin" / "marketplace.json"
claude_marketplace_path = repo_root / ".claude-plugin" / "marketplace.json"
agents_marketplace_path = repo_root / ".agents" / "plugins" / "marketplace.json"
grok_search_web_path = repo_root / "skills" / "grok-search-web"

# 1. Non-existence of removed stdio / legacy files in live plugin tree
http_example = root / "cursor-cli-http.example.json"
if http_example.exists():
    raise SystemExit(f"{http_example}: cursor-cli-http.example.json must not exist in live plugin tree")

for legacy_script in ("run-grok-search.sh", "migrate-from-user-mcp.py"):
    legacy_path = root / "scripts" / legacy_script
    if legacy_path.exists():
        raise SystemExit(f"{legacy_path}: {legacy_script} must not exist in skills/grok-search/scripts/")
if legacy_cursor_hook_path.exists():
    raise SystemExit(f"{legacy_cursor_hook_path}: Cursor must not auto-discover Claude hook format")

# grok-search-web directory must be absent and not named in either marketplace json
if grok_search_web_path.exists():
    raise SystemExit(f"{grok_search_web_path}: grok-search-web must be deleted")

texts = {}
for path in (
    mcp_path,
    skill_path,
    readme_path,
    manifest_path,
    codex_manifest_path,
    example_path,
    changelog_path,
    hooks_path,
    hook_script_path,
    cursor_manifest_path,
    cursor_mcp_path,
    cursor_marketplace_path,
    claude_marketplace_path,
    agents_marketplace_path,
):
    try:
        texts[path] = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"missing {path}") from None

if "grok-search-web" in texts[claude_marketplace_path]:
    raise SystemExit(f"{claude_marketplace_path}: must not contain grok-search-web")
if "grok-search-web" in texts[agents_marketplace_path]:
    raise SystemExit(f"{agents_marketplace_path}: must not contain grok-search-web")

# 2. Plugin .mcp.json contract: no Authorization header, no bearer interpolation
data = json.loads(texts[mcp_path])
servers = data.get("mcpServers")
if not isinstance(servers, dict) or set(servers.keys()) != {"grok-search"}:
    raise SystemExit(f"{mcp_path}: mcpServers must contain exactly one key: grok-search")

server = servers["grok-search"]
if server.get("type") != "http":
    raise SystemExit(f"{mcp_path}: type must be http")
production_url = "https://search.karldigi.dev/mcp"
expected_shared_url = f"${{GROK_SEARCH_MCP_URL:-{production_url}}}"
if server.get("url") != expected_shared_url:
    raise SystemExit(f"{mcp_path}: url must be exactly {expected_shared_url}")

if "headers" in server:
    headers = server.get("headers")
    if isinstance(headers, dict) and "Authorization" in headers:
        raise SystemExit(f"{mcp_path}: must not have headers.Authorization in OAuth configuration")

for forbidden in ("command", "args", "env"):
    if forbidden in server:
        raise SystemExit(f"{mcp_path}: server must not contain {forbidden!r}")

# 3. Example config cursor-cli-mcp.example.json contract: unchanged headless bearer
ex = json.loads(texts[example_path])
ex_servers = ex.get("mcpServers")
if not isinstance(ex_servers, dict) or set(ex_servers.keys()) != {"grok-search"}:
    raise SystemExit(f"{example_path}: mcpServers must contain exactly one key: grok-search")

ex_server = ex_servers["grok-search"]
if ex_server.get("type") != "http":
    raise SystemExit(f"{example_path}: type must be http")
if ex_server.get("url") != production_url:
    raise SystemExit(f"{example_path}: url must be exactly {production_url}")
ex_headers = ex_server.get("headers")
if not isinstance(ex_headers, dict) or ex_headers.get("Authorization") != "Bearer ${env:GROK_SEARCH_MCP_TOKEN}":
    raise SystemExit(f"{example_path}: headers.Authorization must be exactly Bearer ${{env:GROK_SEARCH_MCP_TOKEN}}")
for forbidden in ("command", "args", "env"):
    if forbidden in ex_server:
        raise SystemExit(f"{example_path}: server must not contain {forbidden!r}")

# 4. Claude/Grok JSON must avoid preview endpoints and CF credentials.
for json_path in (mcp_path, example_path, manifest_path, codex_manifest_path):
    json_text = texts[json_path]
    if "100.76.134.104" in json_text:
        raise SystemExit(f"{json_path}: must not contain hardcoded IP 100.76.134.104")
    if "search.termolo.com" in json_text:
        raise SystemExit(f"{json_path}: must not contain domain search.termolo.com")
    for cf_header in ("CF-Access-Client-Id", "CF-Access-Client-Secret"):
        if cf_header in json_text:
            raise SystemExit(f"{json_path}: must not contain {cf_header}")

# Manifest version checks
claude_manifest = json.loads(texts[manifest_path])
cursor_manifest = json.loads(texts[cursor_manifest_path])
expected_version = "0.1.14"
if claude_manifest.get("version") != expected_version:
    raise SystemExit(f"{manifest_path}: version must be {expected_version}")
if cursor_manifest.get("version") != expected_version:
    raise SystemExit(f"{cursor_manifest_path}: version must be {expected_version}")

# Claude manifest: no userConfig, HTTP in description, hooks and skills kept
if "userConfig" in claude_manifest:
    raise SystemExit(f"{manifest_path}: userConfig must be removed")
if claude_manifest.get("hooks") != "./claude-hooks/hooks.json":
    raise SystemExit(f"{manifest_path}: Claude hooks must use isolated claude-hooks path")
if claude_manifest.get("skills") != "./skills/":
    raise SystemExit(f"{manifest_path}: skills must be ./skills/")
manifest_desc = claude_manifest.get("description", "")
if "HTTP" not in manifest_desc and "http" not in manifest_desc:
    raise SystemExit(f"{manifest_path}: description must mention HTTP MCP")
if "stdio" in manifest_desc.lower():
    raise SystemExit(f"{manifest_path}: description must not mention stdio-as-default")

# Cursor manifest: no variables, mcpServers: ./mcp.json, skills: ./skills/, no hooks, no userConfig
if "variables" in cursor_manifest:
    raise SystemExit(f"{cursor_manifest_path}: variables object must be removed")
if "userConfig" in cursor_manifest:
    raise SystemExit(f"{cursor_manifest_path}: userConfig must not exist in Cursor manifest")
if cursor_manifest.get("mcpServers") != "./mcp.json":
    raise SystemExit(f"{cursor_manifest_path}: mcpServers must point to ./mcp.json")
if cursor_manifest.get("hooks") is not None:
    raise SystemExit(f"{cursor_manifest_path}: Cursor package must not expose Claude hooks")
if cursor_manifest.get("skills") not in ("./skills/", "./skills/grok-search/SKILL.md"):
    raise SystemExit(f"{cursor_manifest_path}: skills must expose the shipped grok-search skill")

# Cursor mcp.json: type http, url production, no Authorization header
cursor_mcp = json.loads(texts[cursor_mcp_path])
cursor_servers = cursor_mcp.get("mcpServers")
if not isinstance(cursor_servers, dict) or set(cursor_servers) != {"grok-search"}:
    raise SystemExit(f"{cursor_mcp_path}: must contain only server key grok-search")
cursor_server = cursor_servers["grok-search"]
if cursor_server.get("type") != "http":
    raise SystemExit(f"{cursor_mcp_path}: type must be http")
if cursor_server.get("url") != production_url:
    raise SystemExit(f"{cursor_mcp_path}: must use production URL")
if "headers" in cursor_server and "Authorization" in (cursor_server.get("headers") or {}):
    raise SystemExit(f"{cursor_mcp_path}: must not have Authorization header")
for forbidden in ("grok-search-http", "CF-Access-Client-Id", "CF-Access-Client-Secret"):
    if forbidden in texts[cursor_manifest_path] or forbidden in texts[cursor_mcp_path]:
        raise SystemExit(f"Cursor-native package must not contain {forbidden}")

cursor_marketplace = json.loads(texts[cursor_marketplace_path])
if cursor_marketplace.get("name") != "karlorz-agent-skills":
    raise SystemExit(f"{cursor_marketplace_path}: marketplace name must be karlorz-agent-skills")
entries = cursor_marketplace.get("plugins")
if not isinstance(entries, list):
    raise SystemExit(f"{cursor_marketplace_path}: plugins must be an array")
cursor_entry = next((item for item in entries if item.get("name") == "grok-search"), None)
if not cursor_entry:
    raise SystemExit(f"{cursor_marketplace_path}: grok-search entry missing")
if cursor_entry.get("source") != "skills/grok-search":
    raise SystemExit(f"{cursor_marketplace_path}: grok-search source must be skills/grok-search")

# 5. Codex manifest: version 0.1.14, no bearer_token_env_var, no apps, type http, production url
codex_manifest = json.loads(texts[codex_manifest_path])
if codex_manifest.get("version") != expected_version:
    raise SystemExit(f"{codex_manifest_path}: version must be {expected_version}")
codex_servers = codex_manifest.get("mcpServers")
if not isinstance(codex_servers, dict) or set(codex_servers) != {"grok-search"}:
    raise SystemExit(
        f"{codex_manifest_path}: mcpServers must contain exactly one key: grok-search"
    )
if "hooks" in codex_manifest:
    raise SystemExit(f"{codex_manifest_path}: Codex manifest must not expose Claude hooks")
if "apps" in codex_manifest or ".app.json" in str(codex_manifest):
    raise SystemExit(f"{codex_manifest_path}: Codex manifest must not have apps or .app.json")
codex_interface = codex_manifest.get("interface")
if not isinstance(codex_interface, dict):
    raise SystemExit(f"{codex_manifest_path}: interface must be an object")
if codex_interface.get("displayName") != "Grok Search":
    raise SystemExit(f"{codex_manifest_path}: interface.displayName must be Grok Search")
if codex_interface.get("category") != "Research":
    raise SystemExit(f"{codex_manifest_path}: interface.category must be Research")
long_desc = codex_interface.get("longDescription", "")
if "MCP OAuth" not in long_desc or "no bearer is stored" not in long_desc.lower():
    raise SystemExit(f"{codex_manifest_path}: longDescription must mention MCP OAuth and that no bearer is stored in the plugin")

codex_server = codex_servers["grok-search"]
if codex_server.get("type") != "http":
    raise SystemExit(f"{codex_manifest_path}: Codex MCP type must be http")
if codex_server.get("url") != production_url:
    raise SystemExit(f"{codex_manifest_path}: Codex MCP url must be exactly {production_url}")
if "bearer_token_env_var" in codex_server:
    raise SystemExit(
        f"{codex_manifest_path}: Codex MCP server must not contain bearer_token_env_var"
    )
for forbidden in ("headers", "http_headers", "env_http_headers", "command", "args", "env"):
    if forbidden in codex_server:
        raise SystemExit(f"{codex_manifest_path}: Codex MCP server must not contain {forbidden!r}")

# 6. Root Claude marketplace entry for grok-search
claude_market = json.loads(texts[claude_marketplace_path])
claude_plugins = claude_market.get("plugins") or []
grok_entry = next((p for p in claude_plugins if p.get("name") == "grok-search"), None)
if not grok_entry:
    raise SystemExit(f"{claude_marketplace_path}: grok-search entry missing")
if grok_entry.get("version") != expected_version:
    raise SystemExit(f"{claude_marketplace_path}: grok-search version must be {expected_version}")
if expected_version in grok_entry.get("description", ""):
    raise SystemExit(f"{claude_marketplace_path}: description must not contain version marker {expected_version}")
if "chatgpt" in grok_entry.get("description", "").lower() and "install" in grok_entry.get("description", "").lower():
    raise SystemExit(f"{claude_marketplace_path}: description must not claim ChatGPT web install from GitHub")

# 7. CHANGELOG.md
changelog_text = texts[changelog_path]
release_heading = re.search(
    r"^## \[(?!Unreleased\])([^]]+)\] - (\d{4}-\d{2}-\d{2})$",
    changelog_text,
    re.MULTILINE,
)
if not release_heading:
    raise SystemExit(f"{changelog_path}: must contain a dated release heading")
if release_heading.group(1) != expected_version:
    raise SystemExit(f"{changelog_path}: latest release heading must match {expected_version}")

# 8. SKILL.md contract
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
if not re.search(r"^description:\s*This skill should be used when", fm, re.M):
    raise SystemExit(f"{skill_path}: description must start with 'This skill should be used when'")

for tool in (
    "plan_intent",
    "plan_complexity",
    "plan_sub_query",
    "plan_search_term",
    "plan_tool_mapping",
    "plan_execution",
    "web_search",
    "get_sources",
    "web_fetch",
    "web_map",
):
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
    raise SystemExit(f"{skill_path}: must describe check_readiness.py for hosts that expose a plugin root")
if "GROK_PLUGIN_ROOT" not in body or "CLAUDE_PLUGIN_ROOT" not in body:
    raise SystemExit(f"{skill_path}: readiness path must support Grok and Claude plugin roots")
if "Cursor-native" not in body or "does not run the probe" not in body:
    raise SystemExit(f"{skill_path}: must define Cursor-native readiness without a Claude/Grok probe path")
if "HTTP" not in body and "http" not in body:
    raise SystemExit(f"{skill_path}: must mention HTTP MCP")
if "first-run" not in body.lower() and "first run" not in body.lower():
    raise SystemExit(f"{skill_path}: must mention first-run setup / OAuth")
if "grok-search-http" not in body:
    raise SystemExit(f"{skill_path}: must mention leftover grok-search-http alias note")
if "Cursor-native" not in body or "pins production" not in body:
    raise SystemExit(f"{skill_path}: must state Cursor-native pins production")
if "not configurable in Cursor" not in body:
    raise SystemExit(f"{skill_path}: must not imply the URL override works in Cursor-native")
if "not a fallback" not in body.lower():
    raise SystemExit(f"{skill_path}: must state leftover grok-search-http is not a fallback")
if "sessionstart cannot" not in body.lower() and "sessionstart does not" not in body.lower():
    raise SystemExit(f"{skill_path}: must state SessionStart cannot inject Grok parent MCP env")
if "mcp.env" not in body or "auto-source" not in body.lower():
    raise SystemExit(f"{skill_path}: must state mcp.env is not auto-sourced")
if "never dual-call" not in body.lower() and "do not dual-call" not in body.lower():
    raise SystemExit(f"{skill_path}: must advise never dual-calling grok-search-http alias")
if "stdio (default)" in body.lower() or "stdio as default" in body.lower() or "via stdio mcp" in body.lower():
    raise SystemExit(f"{skill_path}: must not present stdio as default")
if "OAuth" not in body:
    raise SystemExit(f"{skill_path}: must describe OAuth for installed desktop plugin")
if "https://chatgpt.com/admin/apps" not in body or "Create App" not in body:
    raise SystemExit(f"{skill_path}: must mention ChatGPT web route via https://chatgpt.com/admin/apps Create App")
if "desktop-only" not in body.lower():
    raise SystemExit(f"{skill_path}: must explain GitHub marketplace import is desktop-only")
if re.search(r"`/grok-search`", body) or re.search(r"start (?:the skill|it) with (?:a )?`/grok-search`", body):
    raise SystemExit(f"{skill_path}: must not instruct users to invoke skill with a leading slash")

# 9. README.md contract
readme_text = texts[readme_path]
if "GROK_SEARCH_MCP_URL" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention GROK_SEARCH_MCP_URL")
if "https://search.karldigi.dev/mcp" not in readme_text:
    raise SystemExit(f"{readme_path}: must document production endpoint https://search.karldigi.dev/mcp")
if "http://100.76.134.104:8800/mcp" not in readme_text:
    raise SystemExit(f"{readme_path}: must document Tailscale endpoint http://100.76.134.104:8800/mcp")
if "https://search.termolo.com/mcp" not in readme_text:
    raise SystemExit(f"{readme_path}: must document Cloudflare Access endpoint https://search.termolo.com/mcp")
if "OAuth" not in readme_text:
    raise SystemExit(f"{readme_path}: must explain OAuth for the installed plugin")
if "cursor-cli-mcp.example.json" not in readme_text:
    raise SystemExit(f"{readme_path}: must explain cursor-cli-mcp.example.json for optional headless bearer")
if "https://chatgpt.com/admin/apps" not in readme_text or "Create App" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention ChatGPT web admin apps Create App")
if "desktop-only" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must explain GitHub import is desktop-only")
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
if "sessionstart cannot" not in readme_text.lower() and "sessionstart does not" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must explain SessionStart cannot inject Grok parent MCP env")
if "not a fallback" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must state grok-search-http is not a fallback")

# 10. SessionStart wording must not claim Grok parent-env mutation.
hook_text = texts[hooks_path] + texts[hook_script_path]
if "Claude" not in hook_text or "Grok parent env" not in hook_text:
    raise SystemExit("SessionStart hook must identify Claude handoff and Grok parent-env boundary")
if "apply in-process GROK_SEARCH_MCP_URL default" in hook_text:
    raise SystemExit("SessionStart hook must not claim a parent-process URL mutation")

# 11. Secret scan
# Installed mcp.json, .mcp.json, and host manifests must NOT contain Bearer.
for no_bearer_path in (mcp_path, cursor_mcp_path, manifest_path, codex_manifest_path, cursor_manifest_path):
    if "Bearer" in texts[no_bearer_path]:
        raise SystemExit(f"{no_bearer_path}: must not contain Bearer header or field")

blob = "".join(
    texts[p]
    for p in (
        manifest_path,
        codex_manifest_path,
        mcp_path,
        skill_path,
        readme_path,
        example_path,
        changelog_path,
        hooks_path,
        hook_script_path,
        cursor_manifest_path,
        cursor_mcp_path,
        cursor_marketplace_path,
    )
)
allowed_env_bearer = "Bearer ${env:GROK_SEARCH_MCP_TOKEN}"
allowed_changelog_bearer = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
allowed_shared_url = f"${{GROK_SEARCH_MCP_URL:-{production_url}}}"
allowed_prod = production_url
allowed_admin = "https://search.karldigi.dev/admin/gateway-keys"
scanned = (
    blob.replace(allowed_env_bearer, "")
    .replace(allowed_changelog_bearer, "")
    .replace(allowed_shared_url, "")
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
