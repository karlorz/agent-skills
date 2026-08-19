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

texts = {}
for path in (mcp_path, skill_path, readme_path, manifest_path):
    try:
        texts[path] = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"missing {path}") from None

data = json.loads(texts[mcp_path])
if "mcpServers" not in data or "grok-search" not in data["mcpServers"]:
    raise SystemExit(f"{mcp_path}: missing mcpServers.grok-search")
server = data["mcpServers"]["grok-search"]
if server.get("type", "stdio") != "stdio":
    raise SystemExit(f"{mcp_path}: type must be stdio")
if server.get("command") != "bash":
    raise SystemExit(f"{mcp_path}: command must be bash wrapper")
args = server.get("args", [])
if args != ["${CLAUDE_PLUGIN_ROOT}/scripts/run-grok-search.sh"]:
    raise SystemExit(f"{mcp_path}: unexpected args {args!r}")
runner = root / "scripts" / "run-grok-search.sh"
runner_text = runner.read_text(encoding="utf-8")
pin = "git+https://github.com/karlorz/GrokSearch@grok-with-tavily"
if pin not in runner_text or "uvx" not in runner_text:
    raise SystemExit(f"{runner}: must exec uvx pin {pin}")
env = server.get("env", {})
if set(env) != {"GUDA_API_KEY", "GUDA_BASE_URL"}:
    raise SystemExit(f"{mcp_path}: env keys must be exactly GUDA_API_KEY and GUDA_BASE_URL")
if env["GUDA_API_KEY"] != "${GUDA_API_KEY}" or env["GUDA_BASE_URL"] != "${GUDA_BASE_URL}":
    raise SystemExit(f"{mcp_path}: env values must be unadorned ${{VAR}} interpolation")

text = texts[skill_path]
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

blob = "".join(texts[p] for p in (manifest_path, mcp_path, skill_path, readme_path))
for needle in ("search.karldigi.dev", "code.guda.studio", "gsk_", "tvly-", "Bearer "):
    if needle in blob:
        raise SystemExit(f"forbidden token {needle!r} in plugin files")
PY

# Migrate dry-run + apply-env against a fake HOME (placeholder secrets only)
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/grok-search-migrate.XXXXXX")"
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.cursor"
python3 - "$FAKE_HOME" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
claude = {
    "mcpServers": {
        "grok-search": {
            "command": "uvx",
            "args": ["--from", "git+https://github.com/karlorz/GrokSearch@grok-with-tavily", "grok-search"],
            "env": {
                "GUDA_API_KEY": "placeholder-guda-key",
                "GUDA_BASE_URL": "https://example.invalid",
                "GROK_MODEL": "test-model",
            },
        }
    }
}
(home / ".claude.json").write_text(json.dumps(claude), encoding="utf-8")
cursor = {"mcpServers": {"grok-search": {"command": "uvx", "env": {"GUDA_API_KEY": "placeholder-guda-key"}}}}
(home / ".cursor" / "mcp.json").write_text(json.dumps(cursor), encoding="utf-8")
PY
MIGRATE="$PLUGIN_ROOT/scripts/migrate-from-user-mcp.py"
DRY="$(python3 "$MIGRATE" --home "$FAKE_HOME")"
printf '%s\n' "$DRY" | grep -q 'placeholder-guda-key' && fail 'migrate dry-run leaked secret value'
printf '%s\n' "$DRY" | grep -q 'claude-user' || fail 'migrate dry-run missed claude-user'
printf '%s\n' "$DRY" | grep -q 'cursor-user' || fail 'migrate dry-run missed cursor-user'
python3 "$MIGRATE" --home "$FAKE_HOME" --apply-env >/dev/null
test -f "$FAKE_HOME/.config/grok-search/mcp.env" || fail 'migrate --apply-env did not write env file'
python3 "$MIGRATE" --home "$FAKE_HOME" --apply-env --remove-user-mcp >/dev/null
python3 - "$FAKE_HOME" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
cursor = json.loads((home / ".cursor" / "mcp.json").read_text(encoding="utf-8"))
servers = cursor.get("mcpServers") or {}
if "grok-search" in servers:
    raise SystemExit("cursor grok-search not removed")
PY

printf 'test-grok-search-plugin: all checks passed\n'
