# Grok Search Standalone Install Contract

Use this fallback only after detecting that native MCP tools, a supported vaulted helper, and an in-thread HTTP MCP card are unavailable. Muse with official connector setup uses [muse-connector.md](muse-connector.md). Cue defaults to the Apps card; see [first-run.md](first-run.md). This recipe needs git and Node 22 or 24 on the host.

## One-Sentence Install Request

> Install the grok-search Skill+CLI from https://github.com/karlorz/agent-skills using sparse checkout of skills/grok-search, copy its skills/grok-search skill unit into this host's skill directory, and run that installed unit's scripts/grok-search.cjs without configuring host MCP.

## Staging and Installation Recipe

Choose ONE target host skill directory (e.g. `~/.claude/skills/grok-search` or `~/.cursor/skills/grok-search` or `~/.agents/skills/grok-search`).

Refuse to overwrite an existing installation without explicit operator intent. If the target already contains the grok-search skill unit, reuse it unless the operator asks to replace it.

```bash
# 1. Prepare staging directory
STAGING_DIR="$(mktemp -d)"
TARGET_SKILL_DIR="${HOME}/.claude/skills/grok-search"

if [ -e "$TARGET_SKILL_DIR" ] || [ -L "$TARGET_SKILL_DIR" ]; then
  echo "Target directory already exists: $TARGET_SKILL_DIR" >&2
  echo "Aborting to avoid accidental overwrite. Remove or backup existing directory first." >&2
  exit 1
fi

# 2. Sparse checkout of skills/grok-search
git clone --filter=blob:none --no-checkout --depth 1 https://github.com/karlorz/agent-skills.git "$STAGING_DIR/repo"
cd "$STAGING_DIR/repo"
git sparse-checkout set skills/grok-search
# Select a reviewed immutable release SHA; obtain it from the trusted release record.
: "${GROK_SEARCH_INSTALL_SHA:?Set a reviewed 40-character release commit SHA}"
case "$GROK_SEARCH_INSTALL_SHA" in
  *[!0-9a-f]*) echo "Invalid release SHA" >&2; exit 1 ;;
esac
[ "${#GROK_SEARCH_INSTALL_SHA}" -eq 40 ] || exit 1
git fetch --depth 1 origin "$GROK_SEARCH_INSTALL_SHA"
git checkout --detach "$GROK_SEARCH_INSTALL_SHA"

# 3. Copy the canonical nested skill unit into the target host directory
mkdir -p "$(dirname "$TARGET_SKILL_DIR")"
cp -R "$STAGING_DIR/repo/skills/grok-search/skills/grok-search" "$TARGET_SKILL_DIR"

# 4. Cleanup staging
rm -rf "$STAGING_DIR"

# 5. Verify installation (no subcommand prints usage and exits 2).
node "$TARGET_SKILL_DIR/scripts/grok-search.cjs"; test $? -eq 2
```

## Installed Unit Contents

The installed directory contains:
- `SKILL.md` (root prompt and instructions)
- `scripts/grok-search.cjs` (standalone CLI executable)
- `scripts/check-connection-profile.cjs` (optional credential-free discovery check)
- `scripts/lib/toqr.cjs` (offline QR encoder with license notice)
- `references/cli-contract.md`
- `references/auth-contract.md`
- `references/install.md`
- `references/first-run.md`
- `references/muse-connector.md`
- `references/connection-profile.json` (shared, non-secret policy)

Plugin manifest files (`.claude-plugin`, `.cursor-plugin`, `.codex-plugin`, `.mcp.json`, `mcp.json`) and Claude hooks are not installed into the host skill directory.

The connection profile applies to hosted connector setup. It does not replace the CLI auth contract or upgrade CLI operator credentials into OAuth scopes. Existing CLI issuance and credential storage remain supported.
