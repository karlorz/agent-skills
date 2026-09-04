#!/usr/bin/env bash
# Cursor-box-channel-specific HTTP MCP pin, host manifests, companion skill, and secret scan.
# Catalog/manifest inventory is covered by scripts/test-dev-loop-release-tooling.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="$ROOT/skills/cursor-box-channel"

python3 - "$PLUGIN_ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
repo_root = root.parent.parent
mcp_path = root / ".mcp.json"
cursor_mcp_path = root / "mcp.json"
skill_path = root / "skills" / "cursor-box-channel" / "SKILL.md"
readme_path = root / "README.md"
manifest_path = root / ".claude-plugin" / "plugin.json"
cursor_manifest_path = root / ".cursor-plugin" / "plugin.json"
codex_manifest_path = root / ".codex-plugin" / "plugin.json"
example_path = root / "cursor-cli-mcp.example.json"
changelog_path = root / "CHANGELOG.md"
cursor_marketplace_path = repo_root / ".cursor-plugin" / "marketplace.json"
keep_skill_path = repo_root / "skills" / "cursor-github-marketplace-repin" / "skills" / "cursor-github-marketplace-repin" / "SKILL.md"
keep_install_path = repo_root / "skills" / "cursor-github-marketplace-repin" / "scripts" / "install-keep-plugins.sh"

texts = {}
for path in (
    mcp_path,
    cursor_mcp_path,
    skill_path,
    readme_path,
    manifest_path,
    cursor_manifest_path,
    codex_manifest_path,
    example_path,
    changelog_path,
    cursor_marketplace_path,
    keep_skill_path,
    keep_install_path,
):
    try:
        texts[path] = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"missing {path}") from None

production_url = "https://channel.termolo.com/mcp"
expected_shared_url = f"${{CURSOR_BOX_MCP_URL:-{production_url}}}"
expected_bearer = "Bearer ${CURSOR_BOX_MCP_TOKEN}"

# 1. Claude/Grok .mcp.json (allow URL override)
data = json.loads(texts[mcp_path])
servers = data.get("mcpServers")
if not isinstance(servers, dict) or set(servers.keys()) != {"cursor-box-channel"}:
    raise SystemExit(f"{mcp_path}: mcpServers must contain exactly one key: cursor-box-channel")
server = servers["cursor-box-channel"]
if server.get("type") != "http":
    raise SystemExit(f"{mcp_path}: type must be http")
if server.get("url") != expected_shared_url:
    raise SystemExit(f"{mcp_path}: url must be exactly {expected_shared_url}")
headers = server.get("headers")
if not isinstance(headers, dict) or headers.get("Authorization") != expected_bearer:
    raise SystemExit(f"{mcp_path}: headers.Authorization must be exactly {expected_bearer}")
for forbidden in ("command", "args", "env"):
    if forbidden in server:
        raise SystemExit(f"{mcp_path}: server must not contain {forbidden!r}")

# 2. Cursor-native mcp.json pin (no shell fallback)
cursor_mcp = json.loads(texts[cursor_mcp_path])
cursor_servers = cursor_mcp.get("mcpServers")
if not isinstance(cursor_servers, dict) or set(cursor_servers) != {"cursor-box-channel"}:
    raise SystemExit(f"{cursor_mcp_path}: must contain only server key cursor-box-channel")
cursor_server = cursor_servers["cursor-box-channel"]
if cursor_server.get("type") != "http":
    raise SystemExit(f"{cursor_mcp_path}: type must be http")
if cursor_server.get("url") != production_url:
    raise SystemExit(f"{cursor_mcp_path}: must pin {production_url}")
if (cursor_server.get("headers") or {}).get("Authorization") != expected_bearer:
    raise SystemExit(f"{cursor_mcp_path}: must interpolate CURSOR_BOX_MCP_TOKEN")
for forbidden in ("command", "args", "env"):
    if forbidden in cursor_server:
        raise SystemExit(f"{cursor_mcp_path}: server must not contain {forbidden!r}")
if "${CURSOR_BOX_MCP_URL" in texts[cursor_mcp_path]:
    raise SystemExit(f"{cursor_mcp_path}: Cursor-native pin must not use a URL fallback")

# 3. Example config
ex = json.loads(texts[example_path])
ex_servers = ex.get("mcpServers")
if not isinstance(ex_servers, dict) or set(ex_servers.keys()) != {"cursor-box-channel"}:
    raise SystemExit(f"{example_path}: mcpServers must contain exactly one key: cursor-box-channel")
ex_server = ex_servers["cursor-box-channel"]
if ex_server.get("type") != "http":
    raise SystemExit(f"{example_path}: type must be http")
if ex_server.get("url") != production_url:
    raise SystemExit(f"{example_path}: url must be exactly {production_url}")
ex_headers = ex_server.get("headers")
if not isinstance(ex_headers, dict) or ex_headers.get("Authorization") != expected_bearer:
    raise SystemExit(f"{example_path}: headers.Authorization must be exactly {expected_bearer}")
for forbidden in ("command", "args", "env"):
    if forbidden in ex_server:
        raise SystemExit(f"{example_path}: server must not contain {forbidden!r}")

# 4. Host manifests
claude_manifest = json.loads(texts[manifest_path])
cursor_manifest = json.loads(texts[cursor_manifest_path])
codex_manifest = json.loads(texts[codex_manifest_path])
expected_version = claude_manifest.get("version")
if expected_version != "0.3.2":
    raise SystemExit(f"{manifest_path}: version must be 0.3.2")
if cursor_manifest.get("version") != expected_version:
    raise SystemExit(f"{cursor_manifest_path}: version must match Claude manifest")
if codex_manifest.get("version") != expected_version:
    raise SystemExit(f"{codex_manifest_path}: version must match Claude manifest")

if claude_manifest.get("name") != "cursor-box-channel":
    raise SystemExit(f"{manifest_path}: name must be cursor-box-channel")
manifest_desc = claude_manifest.get("description", "")
if "HTTP" not in manifest_desc and "http" not in manifest_desc:
    raise SystemExit(f"{manifest_path}: description must mention HTTP MCP")
if "stdio" in manifest_desc.lower() or "daemon" in manifest_desc.lower():
    raise SystemExit(f"{manifest_path}: description must not mention stdio/daemon as default")

if cursor_manifest.get("name") != "cursor-box-channel":
    raise SystemExit(f"{cursor_manifest_path}: name must be cursor-box-channel")
if cursor_manifest.get("author", {}).get("name") != "karlorz":
    raise SystemExit(f"{cursor_manifest_path}: author must be karlorz")
if cursor_manifest.get("repository") != "https://github.com/karlorz/agent-skills":
    raise SystemExit(f"{cursor_manifest_path}: repository must be https://github.com/karlorz/agent-skills")
if cursor_manifest.get("mcpServers") != "./mcp.json":
    raise SystemExit(f"{cursor_manifest_path}: mcpServers must point to ./mcp.json")
if cursor_manifest.get("skills") != "./skills/":
    raise SystemExit(f"{cursor_manifest_path}: skills must be ./skills/")
variables = cursor_manifest.get("variables")
if not isinstance(variables, dict) or variables.get("type") != "object":
    raise SystemExit(f"{cursor_manifest_path}: variables must be an object schema")
required = variables.get("required")
if not isinstance(required, list) or "CURSOR_BOX_MCP_TOKEN" not in required:
    raise SystemExit(f"{cursor_manifest_path}: CURSOR_BOX_MCP_TOKEN must be required")
properties = variables.get("properties")
if not isinstance(properties, dict) or "CURSOR_BOX_MCP_TOKEN" not in properties:
    raise SystemExit(f"{cursor_manifest_path}: token variable property missing")

codex_servers = codex_manifest.get("mcpServers")
if not isinstance(codex_servers, dict) or set(codex_servers) != {"cursor-box-channel"}:
    raise SystemExit(f"{codex_manifest_path}: mcpServers must contain exactly one key: cursor-box-channel")
codex_server = codex_servers["cursor-box-channel"]
if codex_server.get("type") != "http":
    raise SystemExit(f"{codex_manifest_path}: Codex MCP type must be http")
if codex_server.get("url") != production_url:
    raise SystemExit(f"{codex_manifest_path}: Codex MCP url must be exactly {production_url}")
if codex_server.get("bearer_token_env_var") != "CURSOR_BOX_MCP_TOKEN":
    raise SystemExit(f"{codex_manifest_path}: bearer_token_env_var must be CURSOR_BOX_MCP_TOKEN")
for forbidden in ("headers", "http_headers", "env_http_headers", "command", "args", "env"):
    if forbidden in codex_server:
        raise SystemExit(f"{codex_manifest_path}: Codex MCP server must not contain {forbidden!r}")

# 5. CHANGELOG
changelog_text = texts[changelog_path]
if "## [0.3.2] - 2026-09-04" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must contain ## [0.3.2] - 2026-09-04")
if "## [0.3.1] - 2026-08-30" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must contain ## [0.3.1] - 2026-08-30")
if "## [0.3.0] - 2026-08-30" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must contain ## [0.3.0] - 2026-08-30")
if "## [0.2.0] - 2026-08-30" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must contain ## [0.2.0] - 2026-08-30")
if "0.1.0" not in changelog_text or "2026-08-24" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must keep the 0.1.0 release note")

# 6. SKILL.md
skill_text = texts[skill_path]
if not skill_text.startswith("---\n"):
    raise SystemExit(f"{skill_path}: missing frontmatter")
end = skill_text.find("\n---", 4)
if end < 0:
    raise SystemExit(f"{skill_path}: missing frontmatter terminator")
fm = skill_text[4:end]
body = skill_text[end + 4 :]
if not re.search(r"^name:\s*cursor-box-channel\s*$", fm, re.M):
    raise SystemExit(f"{skill_path}: name must be cursor-box-channel")
if "This skill should be used when" not in fm:
    raise SystemExit(f"{skill_path}: description must use third-person trigger")
for tool in ("ask", "list_replies", "heartbeat", "claim", "reply"):
    if tool not in body:
        raise SystemExit(f"{skill_path}: missing tool {tool}")
if "CURSOR_BOX_MCP_TOKEN" not in body:
    raise SystemExit(f"{skill_path}: must mention CURSOR_BOX_MCP_TOKEN")
if production_url not in body:
    raise SystemExit(f"{skill_path}: must mention {production_url}")
if "attended-only" not in body.lower() and "attended only" not in body.lower():
    raise SystemExit(f"{skill_path}: must mention attended-only")
if "HTTP" not in body and "http" not in body:
    raise SystemExit(f"{skill_path}: must mention HTTP MCP")
if "first-run" not in body.lower() and "first run" not in body.lower():
    raise SystemExit(f"{skill_path}: must mention first-run setup")
if "karlorz/cursor-box-channel" not in body:
    raise SystemExit(f"{skill_path}: must reference karlorz/cursor-box-channel repo")
if "https://channel.termolo.com/console" not in body:
    raise SystemExit(f"{skill_path}: must mention https://channel.termolo.com/console")
if "stdio (default)" in body.lower() or "via stdio mcp" in body.lower():
    raise SystemExit(f"{skill_path}: must not present stdio as default")
if len(skill_text.split()) > 1500:
    raise SystemExit(f"{skill_path}: too long ({len(skill_text.split())} words > 1500)")

# 7. README
readme_text = texts[readme_path]
if "karlorz-agent-skills" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention karlorz-agent-skills")
if "CURSOR_BOX_MCP_TOKEN" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention CURSOR_BOX_MCP_TOKEN")
if "MCP_HTTP_TOKEN" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention sidecar MCP_HTTP_TOKEN")
if production_url not in readme_text:
    raise SystemExit(f"{readme_path}: must document {production_url}")
if "Plugins" not in readme_text or "Configure" not in readme_text:
    raise SystemExit(f"{readme_path}: Cursor instructions must use Plugins -> Configure")
if "attended-only" not in readme_text.lower() and "attended only" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must mention attended-only")
if "Bearer" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention Bearer required")
if "karlorz/cursor-box-channel" not in readme_text:
    raise SystemExit(f"{readme_path}: must reference karlorz/cursor-box-channel repo")
if "agent mcp list" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention agent mcp list diagnostic note")
if "does not write" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must note plugin install does not write ~/.cursor/mcp.json")
if "https://channel.termolo.com/console" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention https://channel.termolo.com/console")

# 8. Cursor catalog + KEEP list
cursor_marketplace = json.loads(texts[cursor_marketplace_path])
entries = cursor_marketplace.get("plugins")
if not isinstance(entries, list):
    raise SystemExit(f"{cursor_marketplace_path}: plugins must be an array")
cursor_entry = next((item for item in entries if item.get("name") == "cursor-box-channel"), None)
if not cursor_entry:
    raise SystemExit(f"{cursor_marketplace_path}: cursor-box-channel entry missing")
if cursor_entry.get("source") != "skills/cursor-box-channel":
    raise SystemExit(f"{cursor_marketplace_path}: source must be skills/cursor-box-channel")

keep_skill = texts[keep_skill_path]
if "`grok-search`, `deep-research`, `cursor-box-channel`" not in keep_skill:
    raise SystemExit(f"{keep_skill_path}: KEEP table must list grok-search, deep-research, cursor-box-channel")
if "cursor-box-channel@karlorz-agent-skills" not in keep_skill:
    raise SystemExit(f"{keep_skill_path}: KEEP install commands must include cursor-box-channel@karlorz-agent-skills")
keep_install = texts[keep_install_path]
if "cursor-box-channel@karlorz-agent-skills" not in keep_install:
    raise SystemExit(f"{keep_install_path}: KEEP list must include cursor-box-channel@karlorz-agent-skills")

# 9. Secret scan — placeholders only, no live tokens
blob = "".join(
    texts[p]
    for p in (
        manifest_path,
        cursor_manifest_path,
        codex_manifest_path,
        mcp_path,
        cursor_mcp_path,
        skill_path,
        readme_path,
        example_path,
        changelog_path,
        cursor_marketplace_path,
    )
)
allowed_bearer = expected_bearer
allowed_shared_url = expected_shared_url
allowed_prod = production_url
scanned = (
    blob.replace(allowed_bearer, "")
    .replace(allowed_shared_url, "")
    .replace(allowed_prod, "")
    .replace("https://channel.termolo.com/console", "")
    .replace("Bearer token", "")
    .replace("origin Bearer", "")
    .replace("required origin Bearer", "")
    .replace("Bearer is", "")
    .replace("Bearer required", "")
)
for needle in ("100.76.134.104", "18742", "18743", "search.karldigi.dev", "code.guda.studio", "gsk_", "tvly-", "Bearer "):
    if needle in scanned:
        raise SystemExit(f"forbidden token {needle!r} in cursor-box-channel plugin files")
if re.search(r"Bearer [A-Za-z0-9_\-]{16,}", blob):
    raise SystemExit("live bearer token must not appear in plugin files")
PY

printf 'test-cursor-box-channel-plugin: all checks passed\n'
