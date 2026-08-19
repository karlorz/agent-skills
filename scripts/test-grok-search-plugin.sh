#!/usr/bin/env bash
# Grok-search-specific MCP pin, env interpolation, skill tools, and secret scan.
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

for path in (mcp_path, skill_path, readme_path, manifest_path):
    if not path.is_file():
        raise SystemExit(f"missing {path}")

data = json.loads(mcp_path.read_text(encoding="utf-8"))
if "mcpServers" not in data or "grok-search" not in data["mcpServers"]:
    raise SystemExit(f"{mcp_path}: missing mcpServers.grok-search")
server = data["mcpServers"]["grok-search"]
if server.get("type", "stdio") != "stdio":
    raise SystemExit(f"{mcp_path}: type must be stdio")
if server.get("command") != "uvx":
    raise SystemExit(f"{mcp_path}: command must be uvx")
args = server.get("args", [])
pin = "git+https://github.com/karlorz/GrokSearch@grok-with-tavily"
if args != ["--from", pin, "grok-search"]:
    raise SystemExit(f"{mcp_path}: unexpected args {args!r}")
env = server.get("env", {})
if set(env) != {"GUDA_API_KEY", "GUDA_BASE_URL"}:
    raise SystemExit(f"{mcp_path}: env keys must be exactly GUDA_API_KEY and GUDA_BASE_URL")
if env["GUDA_API_KEY"] != "${GUDA_API_KEY}" or env["GUDA_BASE_URL"] != "${GUDA_BASE_URL}":
    raise SystemExit(f"{mcp_path}: env values must be unadorned ${{VAR}} interpolation")

text = skill_path.read_text(encoding="utf-8")
if not text.startswith("---\n"):
    raise SystemExit(f"{skill_path}: missing frontmatter")
end = text.find("\n---", 4)
if end < 0:
    raise SystemExit(f"{skill_path}: missing frontmatter terminator")
fm = text[4:end]
body = text[end + 4 :]
if not re.search(r"^name:\s*grok-search\s*$", fm, re.M):
    raise SystemExit(f"{skill_path}: name must be grok-search")
if "This skill should be used when" not in fm:
    raise SystemExit(f"{skill_path}: description must use third-person trigger")
for tool in ("plan_intent", "web_search", "get_sources", "web_fetch", "web_map"):
    if tool not in body:
        raise SystemExit(f"{skill_path}: missing {tool}")
if "mcp__plugin_" in body:
    raise SystemExit(f"{skill_path}: must not hard-code mcp__plugin_ prefixes")
if len(text.split()) > 1500:
    raise SystemExit(f"{skill_path}: too long")

blob = "".join(p.read_text(encoding="utf-8") for p in (manifest_path, mcp_path, skill_path, readme_path))
for needle in ("search.karldigi.dev", "code.guda.studio", "gsk_", "tvly-", "Bearer "):
    if needle in blob:
        raise SystemExit(f"forbidden token {needle!r} in plugin files")
PY

printf 'test-grok-search-plugin: all checks passed\n'
