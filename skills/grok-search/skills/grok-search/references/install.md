# Grok Search Standalone Install Contract

## One-Sentence Install Request

> Install the grok-search Skill+CLI from https://github.com/karlorz/agent-skills using sparse checkout of skills/grok-search, copy its skills/grok-search skill unit into this host's skill directory, and run that installed unit's scripts/grok-search.cjs without configuring host MCP.

## Staging and Installation Recipe

Choose ONE target host skill directory (e.g. `~/.claude/skills/grok-search` or `~/.cursor/skills/grok-search` or `~/.agents/skills/grok-search`).

Refuse to overwrite an existing installation without explicit operator intent. If the target already contains the grok-search skill unit, reuse it unless the operator asks to replace it.

```bash
# 1. Prepare staging directory
STAGING_DIR="$(mktemp -d)"
TARGET_SKILL_DIR="${HOME}/.claude/skills/grok-search"

if [ -e "$TARGET_SKILL_DIR" ]; then
  echo "Target directory already exists: $TARGET_SKILL_DIR" >&2
  echo "Aborting to avoid accidental overwrite. Remove or backup existing directory first." >&2
  exit 1
fi

# 2. Sparse checkout of skills/grok-search
git clone --filter=blob:none --no-checkout --depth 1 https://github.com/karlorz/agent-skills.git "$STAGING_DIR/repo"
cd "$STAGING_DIR/repo"
git sparse-checkout set skills/grok-search
git checkout

# 3. Copy the canonical nested skill unit into the target host directory
mkdir -p "$(dirname "$TARGET_SKILL_DIR")"
cp -R "$STAGING_DIR/repo/skills/grok-search/skills/grok-search" "$TARGET_SKILL_DIR"

# 4. Cleanup staging
rm -rf "$STAGING_DIR"

# 5. Verify installation (no subcommand prints usage and exits 2).
node "$TARGET_SKILL_DIR/scripts/grok-search.cjs"; test $? -eq 2
```

## Installed Unit Contents

The installed directory contains strictly:
- `SKILL.md` (root prompt and instructions)
- `scripts/grok-search.cjs` (standalone CLI executable)
- `scripts/lib/toqr.cjs` (offline QR encoder with license notice)
- `references/cli-contract.md`
- `references/auth-contract.md`
- `references/install.md`

Plugin manifest files (`.claude-plugin`, `.cursor-plugin`, `.codex-plugin`, `.mcp.json`, `mcp.json`) and Claude hooks are not installed into the host skill directory.
