# grok-search

Live web search, page fetch, and site mapping for agents. Two surfaces:

- **Skill+CLI** — copy the nested skill unit, run `scripts/grok-search.cjs`, no host MCP config.
- **Marketplace HTTP MCP** — optional plugin for Claude, Codex, Cursor, Grok. Production only: `https://search.karldigi.dev/mcp`.

Agent runtime rules live in [`skills/grok-search/SKILL.md`](skills/grok-search/SKILL.md). CLI and auth details live in the nested `references/` after install.

## Skill+CLI install

One-sentence request:

> Install the grok-search Skill+CLI from https://github.com/karlorz/agent-skills using sparse checkout of skills/grok-search, copy its skills/grok-search skill unit into this host's skill directory, and run that installed unit's scripts/grok-search.cjs without configuring host MCP.

That sentence needs **git and Node 22 or 24 on the host** (Muse, Doubao 工作 / 云电脑, Orca worker). A chat-only bot cannot execute it.

The one-liner **installs**. `node scripts/grok-search.cjs` with no command prints usage. A later `search` without a token returns `auth_required`. Then, in the **same turn**:

```bash
node scripts/grok-search.cjs auth-start --agent-id <label>
node scripts/grok-search.cjs auth-status
```

Pass `--invite-code <code>` on `auth-start` when the operator gave one. Reply with `approveUrl` only; never print the token or poll secret. Keep `auth-status` until `authenticated`.

Doubao free: `新建自定义连接器` may be disabled. Use Skill+CLI in 工作 mode. Skip 连接器 / 去授权 from the chat.

Copy the nested unit into **one** host skill directory. If that directory already exists, reuse it unless the operator asks to replace it.

```bash
TARGET_DIR="${HOME}/.claude/skills/grok-search"

if [ -e "$TARGET_DIR" ]; then
  echo "Target directory already exists: $TARGET_DIR" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
git clone --filter=blob:none --no-checkout --depth 1 https://github.com/karlorz/agent-skills.git "$STAGING_DIR/repo"
(
  cd "$STAGING_DIR/repo"
  git sparse-checkout set skills/grok-search
  git checkout
)
mkdir -p "$(dirname "$TARGET_DIR")"
cp -R "$STAGING_DIR/repo/skills/grok-search/skills/grok-search" "$TARGET_DIR"
rm -rf "$STAGING_DIR"
node "$TARGET_DIR/scripts/grok-search.cjs"
```

Other hosts: `~/.cursor/skills/grok-search` or `~/.agents/skills/grok-search`. The copy contains `SKILL.md`, `scripts/`, and `references/` only.

**Node 22 or 24.** No `npm install`.

Same recipe: nested [`references/install.md`](skills/grok-search/references/install.md).

## Skill+CLI usage

From the installed skill directory:

```bash
node scripts/grok-search.cjs auth-start --agent-id <label> [--invite-code <code>]
node scripts/grok-search.cjs auth-status
node scripts/grok-search.cjs search --query "..."
node scripts/grok-search.cjs fetch --url "https://..."
node scripts/grok-search.cjs map --url "https://..."
```

`auth-start` prints an HTTPS approve URL. Approve in a browser. `auth-status` writes `~/.config/grok-search/http-mcp.token` (mode `0600`). Do not print the token or poll secret.

If MCP tools are already connected on the host, use those tools (connector mode). If they are not, plan locally and use the CLI. Do not write `mcp.json`, `config.toml`, or `mcp.env`.

## Marketplace plugin

```bash
claude plugin install grok-search@karlorz-agent-skills
codex plugin add grok-search@karlorz-agent-skills
```

Cursor: install `grok-search` from the `karlorz-agent-skills` marketplace.

Export `GROK_SEARCH_MCP_TOKEN` (gateway key from `https://search.karldigi.dev/admin/gateway-keys`) in the process that launches the client. Installed `.mcp.json` / Cursor `mcp.json` send `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`; Grok skips OAuth when that header is present. Codex uses `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`. ChatGPT web and Doubao Work use HTTPS OAuth completed by a person outside the chat.

Verify in a live session: search or `get_config_info` against production. Live tool execution is the proof of install.

## License

MIT
