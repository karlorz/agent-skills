#!/usr/bin/env bash
# Cursor-box-channel-specific stdio MCP pin, runner script, companion skill, and secret scan.
# Catalog/manifest inventory is covered by scripts/test-dev-loop-release-tooling.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="$ROOT/skills/cursor-box-channel"

python3 - "$PLUGIN_ROOT" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
mcp_path = root / ".mcp.json"
skill_path = root / "skills" / "cursor-box-channel" / "SKILL.md"
readme_path = root / "README.md"
manifest_path = root / ".claude-plugin" / "plugin.json"
example_path = root / "cursor-cli-mcp.example.json"
changelog_path = root / "CHANGELOG.md"
runner_path = root / "scripts" / "run-cursor-box-mcp.sh"

texts = {}
for path in (mcp_path, skill_path, readme_path, manifest_path, example_path, changelog_path, runner_path):
    try:
        texts[path] = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"missing {path}") from None

# 1. Plugin .mcp.json contract (stdio, not HTTP)
data = json.loads(texts[mcp_path])
servers = data.get("mcpServers")
if not isinstance(servers, dict) or set(servers.keys()) != {"cursor-box-channel"}:
    raise SystemExit(f"{mcp_path}: mcpServers must contain exactly one key: cursor-box-channel")

server = servers["cursor-box-channel"]
if "type" in server:
    raise SystemExit(f"{mcp_path}: server must not specify type (must be stdio runner, no type: http)")
if "url" in server or "headers" in server:
    raise SystemExit(f"{mcp_path}: server must not contain url or headers (no HTTP MCP)")

if server.get("command") != "bash":
    raise SystemExit(f"{mcp_path}: command must be bash")
args = server.get("args")
if not isinstance(args, list) or len(args) != 1 or args[0] != "${CLAUDE_PLUGIN_ROOT}/scripts/run-cursor-box-mcp.sh":
    raise SystemExit(f"{mcp_path}: args must be [\"${{CLAUDE_PLUGIN_ROOT}}/scripts/run-cursor-box-mcp.sh\"]")

# 2. Runner script contract (scripts/run-cursor-box-mcp.sh)
runner_text = texts[runner_path]
if not runner_text.startswith("#!/usr/bin/env bash") and not runner_text.startswith("#!/bin/bash"):
    raise SystemExit(f"{runner_path}: missing bash shebang")

target_bin_path = 'Library/Application Support/cursor-box-channel/bin/cursor-box-mcp'
if target_bin_path not in runner_text:
    raise SystemExit(f"{runner_path}: must reference $HOME/Library/Application Support/cursor-box-channel/bin/cursor-box-mcp")

if "exec " not in runner_text:
    raise SystemExit(f"{runner_path}: must exec the target binary")

for forbidden in ("launchctl load", "launchctl start", "launchctl bootstrap", "install-daemon", "server.py"):
    if forbidden in runner_text:
        raise SystemExit(f"{runner_path}: runner must not launch or load daemon ({forbidden!r} forbidden)")

# 3. Example config cursor-cli-mcp.example.json contract
ex = json.loads(texts[example_path])
ex_servers = ex.get("mcpServers")
if not isinstance(ex_servers, dict) or set(ex_servers.keys()) != {"cursor-box-channel"}:
    raise SystemExit(f"{example_path}: mcpServers must contain exactly one key: cursor-box-channel")

ex_server = ex_servers["cursor-box-channel"]
if "type" in ex_server or "url" in ex_server or "headers" in ex_server:
    raise SystemExit(f"{example_path}: must not contain type/url/headers (stdio only)")
if ex_server.get("command") != "bash":
    raise SystemExit(f"{example_path}: command must be bash")

# 4. JSON configs must not have hardcoded IPs, ports, tokens, secrets, or remote images
for json_path in (mcp_path, example_path, manifest_path):
    json_text = texts[json_path]
    for forbidden in ("100.76.134.104", "18742", "18743", "ghcr.io", "http://", "https://", "Authorization"):
        if forbidden in json_text:
            raise SystemExit(f"{json_path}: must not contain {forbidden!r}")

# 5. Manifest (.claude-plugin/plugin.json)
manifest = json.loads(texts[manifest_path])
if manifest.get("name") != "cursor-box-channel":
    raise SystemExit(f"{manifest_path}: name must be cursor-box-channel")
if manifest.get("version") != "0.1.0":
    raise SystemExit(f"{manifest_path}: version must be 0.1.0")
manifest_desc = manifest.get("description", "")
if "cursor-box" not in manifest_desc.lower() and "channel" not in manifest_desc.lower():
    raise SystemExit(f"{manifest_path}: description must mention cursor-box or channel")

# 6. CHANGELOG.md
changelog_text = texts[changelog_path]
if "0.1.0" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must mention version 0.1.0")
if "2026-08-24" not in changelog_text:
    raise SystemExit(f"{changelog_path}: must mention release date 2026-08-24")

# 7. SKILL.md contract
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

for tool in ("post_message", "ask_message", "list_replies"):
    if tool not in body:
        raise SystemExit(f"{skill_path}: missing tool {tool}")

# Targets contract: channel, newbie, wiki-research; no cursor-plugins MCP target
for target in ("channel", "newbie", "wiki-research"):
    if target not in body:
        raise SystemExit(f"{skill_path}: missing target {target}")
if "cursor-plugins" in body:
    raise SystemExit(f"{skill_path}: cursor-plugins target must not be in SKILL.md")

if "server.py" not in body or "never dual-call" not in body.lower():
    raise SystemExit(f"{skill_path}: must mention never dual-calling leftover Python server.py")

if "karlorz/cursor-box-channel" not in body:
    raise SystemExit(f"{skill_path}: must reference karlorz/cursor-box-channel repo")

if "first-run" not in body.lower() and "first run" not in body.lower():
    raise SystemExit(f"{skill_path}: must mention first-run setup / ask if daemon/socket/Keychain/wrapper missing")

if "Grok Bot" not in body and "grok bot" not in body.lower():
    raise SystemExit(f"{skill_path}: must mention Grok Bot consumer blocker")

if len(skill_text.split()) > 1500:
    raise SystemExit(f"{skill_path}: too long ({len(skill_text.split())} words > 1500)")

# 8. README.md contract
readme_text = texts[readme_path]
if "karlorz/cursor-box-channel" not in readme_text:
    raise SystemExit(f"{readme_path}: must reference karlorz/cursor-box-channel repo")
if "agent mcp list" not in readme_text:
    raise SystemExit(f"{readme_path}: must mention agent mcp list diagnostic note")
if "not write ~/.cursor/mcp.json" not in readme_text.lower() and "does not write" not in readme_text.lower():
    raise SystemExit(f"{readme_path}: must note plugin install does not write ~/.cursor/mcp.json")

# 9. Secret & IP scan across all plugin files
blob = "".join(texts[p] for p in (manifest_path, mcp_path, skill_path, readme_path, example_path, changelog_path, runner_path))
for needle in ("100.76.134.104", "18742", "18743", "search.karldigi.dev", "code.guda.studio", "gsk_", "tvly-", "Bearer "):
    if needle in blob:
        raise SystemExit(f"forbidden token {needle!r} in cursor-box-channel plugin files")

PY

printf 'test-cursor-box-channel-plugin: all checks passed\n'
