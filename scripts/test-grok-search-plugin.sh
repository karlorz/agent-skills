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
cli_wrapper_path = root / "scripts" / "grok-search.cjs"
nested_cli_path = root / "skills" / "grok-search" / "scripts" / "grok-search.cjs"
toqr_lib_path = root / "skills" / "grok-search" / "scripts" / "lib" / "toqr.cjs"
cli_contract_path = root / "skills" / "grok-search" / "references" / "cli-contract.md"
auth_contract_path = root / "skills" / "grok-search" / "references" / "auth-contract.md"
install_contract_path = root / "skills" / "grok-search" / "references" / "install.md"

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
    cli_wrapper_path,
    nested_cli_path,
    toqr_lib_path,
    cli_contract_path,
    auth_contract_path,
    install_contract_path,
):
    try:
        texts[path] = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"missing {path}") from None

if "grok-search-web" in texts[claude_marketplace_path]:
    raise SystemExit(f"{claude_marketplace_path}: must not contain grok-search-web")
if "grok-search-web" in texts[agents_marketplace_path]:
    raise SystemExit(f"{agents_marketplace_path}: must not contain grok-search-web")

# 2. Plugin .mcp.json contract: env-backed Authorization header
data = json.loads(texts[mcp_path])
servers = data.get("mcpServers")
if not isinstance(servers, dict) or set(servers.keys()) != {"grok-search"}:
    raise SystemExit(f"{mcp_path}: mcpServers must contain exactly one key: grok-search")

server = servers["grok-search"]
if server.get("type") != "http":
    raise SystemExit(f"{mcp_path}: type must be http")
production_url = "https://search.karldigi.dev/mcp"
expected_shared_url = f"${{GROK_SEARCH_MCP_URL:-{production_url}}}"
expected_bearer = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
if server.get("url") != expected_shared_url:
    raise SystemExit(f"{mcp_path}: url must be exactly {expected_shared_url}")

headers = server.get("headers")
if not isinstance(headers, dict) or headers.get("Authorization") != expected_bearer:
    raise SystemExit(f"{mcp_path}: headers.Authorization must be exactly {expected_bearer}")

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
expected_version = "0.1.24"
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

# Cursor mcp.json: type http, url production, env-backed Authorization header
cursor_mcp = json.loads(texts[cursor_mcp_path])
cursor_servers = cursor_mcp.get("mcpServers")
if not isinstance(cursor_servers, dict) or set(cursor_servers) != {"grok-search"}:
    raise SystemExit(f"{cursor_mcp_path}: must contain only server key grok-search")
cursor_server = cursor_servers["grok-search"]
if cursor_server.get("type") != "http":
    raise SystemExit(f"{cursor_mcp_path}: type must be http")
if cursor_server.get("url") != production_url:
    raise SystemExit(f"{cursor_mcp_path}: must use production URL")
cursor_headers = cursor_server.get("headers")
if not isinstance(cursor_headers, dict) or cursor_headers.get("Authorization") != expected_bearer:
    raise SystemExit(f"{cursor_mcp_path}: headers.Authorization must be exactly {expected_bearer}")
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

# 5. Codex manifest: expected version, bearer_token_env_var, no apps, type http, production url
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
if "GROK_SEARCH_MCP_TOKEN" not in long_desc:
    raise SystemExit(f"{codex_manifest_path}: longDescription must name GROK_SEARCH_MCP_TOKEN")
if "OAuth" not in long_desc:
    raise SystemExit(f"{codex_manifest_path}: longDescription must keep ChatGPT/Doubao MCP OAuth")

codex_server = codex_servers["grok-search"]
if codex_server.get("type") != "http":
    raise SystemExit(f"{codex_manifest_path}: Codex MCP type must be http")
if codex_server.get("url") != production_url:
    raise SystemExit(f"{codex_manifest_path}: Codex MCP url must be exactly {production_url}")
if codex_server.get("bearer_token_env_var") != "GROK_SEARCH_MCP_TOKEN":
    raise SystemExit(
        f"{codex_manifest_path}: bearer_token_env_var must be GROK_SEARCH_MCP_TOKEN"
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
version_headings = re.findall(r"^## \[([^]]+)\]", changelog_text, re.MULTILINE)
duplicate_versions = sorted({v for v in version_headings if version_headings.count(v) > 1})
if duplicate_versions:
    raise SystemExit(f"{changelog_path}: duplicate release headings {duplicate_versions}")
for section in re.split(r"^## ", changelog_text, flags=re.MULTILINE)[1:]:
    subsections = re.findall(r"^### (.+)$", section, re.MULTILINE)
    duplicate_subsections = sorted({s for s in subsections if subsections.count(s) > 1})
    if duplicate_subsections:
        heading = section.splitlines()[0]
        raise SystemExit(f"{changelog_path}: {heading} repeats {duplicate_subsections}")

grok_overlay_table = "[mcp_servers.grok-search.headers]"
grok_overlay_header = 'Authorization = "Bearer ${GROK_SEARCH_MCP_TOKEN}"'
discriminator = "headed vs headless is not the discriminator"

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
if "a chat cannot finish first-time connector setup" not in body.lower():
    raise SystemExit(f"{skill_path}: must state a chat cannot finish first-time connector setup")
if "headless_oauth_loopback" not in body:
    raise SystemExit(f"{skill_path}: must mention headless_oauth_loopback for SSH sessions")
if "cursor-cli-mcp.example.json" not in body:
    raise SystemExit(f"{skill_path}: must name cursor-cli-mcp.example.json for Cursor CLI bearer overlay")
if "Bearer ${GROK_SEARCH_MCP_TOKEN}" not in body:
    raise SystemExit(f"{skill_path}: must document installed plugin Bearer ${{GROK_SEARCH_MCP_TOKEN}}")
if "bearer_token_env_var" not in body:
    raise SystemExit(f"{skill_path}: must document Codex bearer_token_env_var")
if grok_overlay_table not in body or grok_overlay_header not in body:
    raise SystemExit(f"{skill_path}: must document Grok config.toml HTTP url + headers.Authorization overlay")
if discriminator not in body.lower() or "DISPLAY" not in body:
    raise SystemExit(f"{skill_path}: must state DISPLAY / headed vs headless is not the discriminator")
if "operator browser" not in body.lower():
    raise SystemExit(f"{skill_path}: must frame operator browser vs this-host loopback")
if "do not tell the operator to click the login link on another machine" not in body.lower():
    raise SystemExit(f"{skill_path}: must forbid completing OAuth login on another machine")
if "leftover_stdio_config" not in body:
    raise SystemExit(f"{skill_path}: must mention leftover_stdio_config for Grok config.toml stdio")
if "does not use oauth" not in body.lower() and "http/sse only" not in body.lower():
    raise SystemExit(f"{skill_path}: must state Grok i auth is HTTP/SSE only")
if "doubao" not in body.lower() or "去授權" not in body:
    raise SystemExit(f"{skill_path}: must document Doubao Work 去授權 as a person step")
if re.search(r"`/grok-search`", body) or re.search(r"start (?:the skill|it) with (?:a )?`/grok-search`", body):
    raise SystemExit(f"{skill_path}: must not instruct users to invoke skill with a leading slash")

# 9. README.md is agent-facing install and usage only.
readme_text = texts[readme_path]
if "Install the grok-search Skill+CLI from https://github.com/karlorz/agent-skills" not in readme_text:
    raise SystemExit(f"{readme_path}: must include the one-sentence Skill+CLI install")
if "sparse checkout" not in readme_text.lower() or "skills/grok-search" not in readme_text:
    raise SystemExit(f"{readme_path}: must describe sparse checkout of skills/grok-search")
if "without configuring host MCP" not in readme_text:
    raise SystemExit(f"{readme_path}: must say the Skill+CLI install does not configure host MCP")
if "https://search.karldigi.dev/mcp" not in readme_text:
    raise SystemExit(f"{readme_path}: must document production endpoint https://search.karldigi.dev/mcp")
if "auth-start" not in readme_text or "auth-status" not in readme_text:
    raise SystemExit(f"{readme_path}: must document auth-start and auth-status")
if "search --query" not in readme_text:
    raise SystemExit(f"{readme_path}: must document CLI search --query")
if "Bearer ${GROK_SEARCH_MCP_TOKEN}" not in readme_text:
    raise SystemExit(f"{readme_path}: must document installed plugin Bearer ${{GROK_SEARCH_MCP_TOKEN}}")
if "skips OAuth" not in readme_text:
    raise SystemExit(f"{readme_path}: must state Grok skips OAuth when the Authorization header is set")
if "~/.config/grok-search/http-mcp.token" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention ~/.config/grok-search/http-mcp.token token path")
if "claude plugin install grok-search@karlorz-agent-skills" not in readme_text:
    raise SystemExit(f"{readme_path}: must include Claude marketplace install")
for leaked in (
    "100.76.134.104",
    "100.118.12.90",
    "search.termolo.com",
    "sg01",
    "kr01",
    "0.0.0.0",
    "grok2api",
):
    if leaked in readme_text:
        raise SystemExit(f"{readme_path}: must not leak deploy/private endpoint {leaked!r}")

# 10. SessionStart wording must not claim Grok parent-env mutation.
hook_text = texts[hooks_path] + texts[hook_script_path]
if "Claude" not in hook_text or "Grok parent env" not in hook_text:
    raise SystemExit("SessionStart hook must identify Claude handoff and Grok parent-env boundary")
if "apply in-process GROK_SEARCH_MCP_URL default" in hook_text:
    raise SystemExit("SessionStart hook must not claim a parent-process URL mutation")

# 11. Secret scan
# Host manifests must not embed a Bearer header; plugin JSON may use the env placeholder.
for no_bearer_path in (manifest_path, codex_manifest_path, cursor_manifest_path):
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
        cli_wrapper_path,
        nested_cli_path,
        toqr_lib_path,
        cli_contract_path,
        auth_contract_path,
        install_contract_path,
    )
)
allowed_env_bearer = "Bearer ${env:GROK_SEARCH_MCP_TOKEN}"
allowed_changelog_bearer = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
allowed_auth_bearer = "Bearer ${this.token}"
allowed_shared_url = f"${{GROK_SEARCH_MCP_URL:-{production_url}}}"
allowed_prod = production_url
allowed_admin = "https://search.karldigi.dev/admin/gateway-keys"
allowed_origin = "https://search.karldigi.dev"
scanned = (
    blob.replace(allowed_env_bearer, "")
    .replace(allowed_changelog_bearer, "")
    .replace(allowed_auth_bearer, "")
    .replace(allowed_shared_url, "")
    .replace(allowed_prod, "")
    .replace(allowed_admin, "")
    .replace(allowed_origin, "")
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
