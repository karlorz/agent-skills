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
):
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
production_url = "https://search.karldigi.dev/mcp"
expected_shared_url = f"${{GROK_SEARCH_MCP_URL:-{production_url}}}"
if server.get("url") != expected_shared_url:
    raise SystemExit(f"{mcp_path}: url must be exactly {expected_shared_url}")

headers = server.get("headers")
if not isinstance(headers, dict) or headers.get("Authorization") != "Bearer ${GROK_SEARCH_MCP_TOKEN}":
    raise SystemExit(f"{mcp_path}: headers.Authorization must be exactly Bearer ${{GROK_SEARCH_MCP_TOKEN}}")

for forbidden in ("command", "args", "env"):
    if forbidden in server:
        raise SystemExit(f"{mcp_path}: server must not contain {forbidden!r}")
# 3. Example config cursor-cli-mcp.example.json contract
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

# Official Cursor schema shape checks. These cover the fields used by this package
# without adding a repository dependency on a schema-validation library.
claude_manifest = json.loads(texts[manifest_path])
cursor_manifest = json.loads(texts[cursor_manifest_path])
expected_version = claude_manifest.get("version")
if not isinstance(expected_version, str) or not re.fullmatch(
    r"[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?", expected_version
):
    raise SystemExit(f"{manifest_path}: version must be supported semver")
allowed_cursor_manifest_fields = {
    "name",
    "description",
    "version",
    "minClientVersions",
    "author",
    "publisher",
    "homepage",
    "repository",
    "license",
    "logo",
    "keywords",
    "commands",
    "agents",
    "skills",
    "rules",
    "hooks",
    "variables",
    "mcpServers",
}
unknown_cursor_fields = sorted(set(cursor_manifest) - allowed_cursor_manifest_fields)
if unknown_cursor_fields:
    raise SystemExit(f"{cursor_manifest_path}: unsupported fields: {', '.join(unknown_cursor_fields)}")
if not isinstance(cursor_manifest.get("description"), str) or not cursor_manifest["description"].strip():
    raise SystemExit(f"{cursor_manifest_path}: description missing")
if cursor_manifest.get("name") != "grok-search":
    raise SystemExit(f"{cursor_manifest_path}: name must be grok-search")
if cursor_manifest.get("version") != expected_version:
    raise SystemExit(f"{cursor_manifest_path}: version must match Claude manifest")
if cursor_manifest.get("mcpServers") != "./mcp.json":
    raise SystemExit(f"{cursor_manifest_path}: mcpServers must point to ./mcp.json")
if cursor_manifest.get("hooks") is not None:
    raise SystemExit(f"{cursor_manifest_path}: Cursor package must not expose Claude hooks")
if claude_manifest.get("hooks") != "./claude-hooks/hooks.json":
    raise SystemExit(f"{manifest_path}: Claude hooks must use isolated claude-hooks path")
variables = cursor_manifest.get("variables")
if not isinstance(variables, dict) or variables.get("type") != "object":
    raise SystemExit(f"{cursor_manifest_path}: variables must be an object schema")
required = variables.get("required")
if not isinstance(required, list) or "GROK_SEARCH_MCP_TOKEN" not in required:
    raise SystemExit(f"{cursor_manifest_path}: GROK_SEARCH_MCP_TOKEN must be required")
properties = variables.get("properties")
if not isinstance(properties, dict) or "GROK_SEARCH_MCP_TOKEN" not in properties:
    raise SystemExit(f"{cursor_manifest_path}: token variable property missing")
skills = cursor_manifest.get("skills")
if skills not in ("./skills/", "./skills/grok-search/SKILL.md"):
    raise SystemExit(f"{cursor_manifest_path}: skills must expose the shipped grok-search skill")

cursor_mcp = json.loads(texts[cursor_mcp_path])
cursor_servers = cursor_mcp.get("mcpServers")
if not isinstance(cursor_servers, dict) or set(cursor_servers) != {"grok-search"}:
    raise SystemExit(f"{cursor_mcp_path}: must contain only server key grok-search")
cursor_server = cursor_servers["grok-search"]
if cursor_server.get("type") != "http":
    raise SystemExit(f"{cursor_mcp_path}: type must be http")
if cursor_server.get("url") != production_url:
    raise SystemExit(f"{cursor_mcp_path}: must use production URL")
if (cursor_server.get("headers") or {}).get("Authorization") != "Bearer ${GROK_SEARCH_MCP_TOKEN}":
    raise SystemExit(f"{cursor_mcp_path}: must interpolate GROK_SEARCH_MCP_TOKEN")
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

# 5. Host manifests and Codex-native MCP config
codex_manifest = json.loads(texts[codex_manifest_path])
codex_servers = codex_manifest.get("mcpServers")
if not isinstance(codex_servers, dict) or set(codex_servers) != {"grok-search"}:
    raise SystemExit(
        f"{codex_manifest_path}: mcpServers must contain exactly one key: grok-search"
    )
if "hooks" in codex_manifest:
    raise SystemExit(f"{codex_manifest_path}: Codex manifest must not expose Claude hooks")
codex_interface = codex_manifest.get("interface")
if not isinstance(codex_interface, dict):
    raise SystemExit(f"{codex_manifest_path}: interface must be an object")
if codex_interface.get("displayName") != "Grok Search":
    raise SystemExit(f"{codex_manifest_path}: interface.displayName must be Grok Search")
if codex_interface.get("category") != "Research":
    raise SystemExit(f"{codex_manifest_path}: interface.category must be Research")
manifest_desc = claude_manifest.get("description", "")
if "HTTP" not in manifest_desc and "http" not in manifest_desc:
    raise SystemExit(f"{manifest_path}: description must mention HTTP MCP")
if "stdio" in manifest_desc.lower():
    raise SystemExit(f"{manifest_path}: description must not mention stdio-as-default")

codex_server = codex_servers["grok-search"]
if codex_server.get("type") != "http":
    raise SystemExit(f"{codex_manifest_path}: Codex MCP type must be http")
if codex_server.get("url") != production_url:
    raise SystemExit(f"{codex_manifest_path}: Codex MCP url must be exactly {production_url}")
if codex_server.get("bearer_token_env_var") != "GROK_SEARCH_MCP_TOKEN":
    raise SystemExit(
        f"{codex_manifest_path}: Codex MCP bearer_token_env_var must be GROK_SEARCH_MCP_TOKEN"
    )
for forbidden in ("headers", "http_headers", "env_http_headers", "command", "args", "env"):
    if forbidden in codex_server:
        raise SystemExit(f"{codex_manifest_path}: Codex MCP server must not contain {forbidden!r}")

# 6. CHANGELOG.md
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
    raise SystemExit(f"{skill_path}: must mention first-run setup / ask if URL or token missing")
if "grok-search-http" not in body:
    raise SystemExit(f"{skill_path}: must mention leftover grok-search-http alias note")
if "Cursor-native" not in body or "pins production" not in body:
    raise SystemExit(f"{skill_path}: must state Cursor-native pins production")
if "not configurable in Cursor" not in body:
    raise SystemExit(f"{skill_path}: must not imply the URL override works in Cursor-native")
if "not a fallback" not in body.lower():
    raise SystemExit(f"{skill_path}: must state leftover grok-search-http is not a fallback")
if "process environment" not in body.lower():
    raise SystemExit(f"{skill_path}: must state Grok requires the token in process environment")
if "sessionstart cannot" not in body.lower() and "sessionstart does not" not in body.lower():
    raise SystemExit(f"{skill_path}: must state SessionStart cannot inject Grok parent MCP env")
if "mcp.env" not in body or "auto-source" not in body.lower():
    raise SystemExit(f"{skill_path}: must state mcp.env is not auto-sourced")
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

if "Plugins" not in readme_text or "Configure" not in readme_text:
    raise SystemExit(f"{readme_path}: Cursor instructions must use Plugins -> Configure for the token variable")
if "Cursor process environment" in readme_text:
    raise SystemExit(f"{readme_path}: must not claim Cursor plugin variables come from process env")
if re.search(r"before starting[^\n.]*\bCursor\b", readme_text, re.IGNORECASE):
    raise SystemExit(f"{readme_path}: must not include Cursor in export-before-starting host list")
for match in re.finditer(
    r"(?:Cursor\b[^\n.]*process[- ]environment|process[- ]environment\s+(?:for|in)\s+Cursor\b)",
    readme_text,
    re.IGNORECASE,
):
    matched_text = match.group(0)
    if "instead of" not in matched_text.lower() and "not" not in matched_text.lower():
        raise SystemExit(
            f"{readme_path}: must not document Cursor as requiring/exporting GROK_SEARCH_MCP_TOKEN through process environment: {matched_text!r}"
        )
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
if "process environment" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must require gateway-keys in the Grok process environment")
if "sessionstart cannot" not in readme_text.lower() and "sessionstart does not" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must explain SessionStart cannot inject Grok parent MCP env")
if "not a fallback" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must state grok-search-http is not a fallback")

# 8b. SessionStart wording must not claim Grok parent-env mutation.
hook_text = texts[hooks_path] + texts[hook_script_path]
if "Claude" not in hook_text or "Grok parent env" not in hook_text:
    raise SystemExit("SessionStart hook must identify Claude handoff and Grok parent-env boundary")
if "apply in-process GROK_SEARCH_MCP_URL default" in hook_text:
    raise SystemExit("SessionStart hook must not claim a parent-process URL mutation")

# 9. Secret scan
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
allowed_bearer = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
allowed_env_bearer = "Bearer ${env:GROK_SEARCH_MCP_TOKEN}"
allowed_shared_url = f"${{GROK_SEARCH_MCP_URL:-{production_url}}}"
allowed_prod = production_url
allowed_admin = "https://search.karldigi.dev/admin/gateway-keys"
scanned = (
    blob.replace(allowed_bearer, "")
    .replace(allowed_env_bearer, "")
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
