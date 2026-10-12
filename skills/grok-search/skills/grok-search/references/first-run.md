# Grok Search First-Run Host Details

Apply the detect → install → init order in [SKILL.md](../SKILL.md). Use the first matching surface; do not run connector and CLI searches together. Agents never write host MCP files (`mcp.json`, `config.toml`, or `mcp.env`).

## Connector already present

Use the host's `grok-search` tools and server `plan_*` workflow, then `web_search` and `get_sources`. Ignore leftover `grok-search-http`; it is not a fallback. Never dual-call it. A 401 is a handshake failure or missing token: report it and stop rather than installing another connector.

## Cue / 小Q: in-thread Apps MCP card

When tools are absent, ask the host to add the HTTP MCP app named `grok-search`, URL `https://search.karldigi.dev/mcp`, with no custom headers. Finish the in-thread connection card (Added / authorize); the operator confirms in the host UI. Keep passwords and credentials in that UI, never in chat. Once tools appear, return to connector mode and run one tiny search.

This is Cue's default. Do not default to GitHub Import of the `karlorz/agent-skills` monorepo. If the host cannot present an in-thread card but has git and Node, use Skill+CLI with `--agent-id cue`.

Leftover `~/.manus/skills/grok-search` plus `~/.config/grok-search/` makes Cue run CLI and skip the Apps card. Uninstall those copies and CLI auth state before a deliberate Apps-first test. This reset removes the CLI installation and its local credentials; use it only for that test, not as routine connector detection.

Proof on 2026-10-12: after uninstalling the leftover CLI copy, Cue presented the in-thread Apps MCP card, listed grok-search tools, and `web_search` returned `ok: true`, `sources_count: 6`. A new thread's successful tool call is its own readiness proof.

## Skill+CLI hosts

Muse, Doubao 工作 / 云电脑, Orca workers, and other hosts with git and Node 22 or 24 can use [install.md](install.md) when connector tools and an in-thread MCP card are unavailable. Reuse an existing nested skill unit; copy into only one host skill directory. No npm install and no host MCP registration.

Muse **prefer_first: skill-cli**. Settings → Connectors lists marketplace presets (Browser, GitHub, …) plus Muse-created Lab Access Id/Jwt/Secret rows. Those Lab rows are **credential vaults** (operator pastes in a Muse secure card; scripts use surrogates). They are not HTTP MCP tool attachment. Muse has no connector type for `https://search.karldigi.dev/mcp`, and a vault row cannot fill `web_search` / `get_sources` or `GROK_SEARCH_MCP_TOKEN`. Persist is Skill+CLI on the Muse VM (`--agent-id muse`); the file token lasts. Do not mint a unused `custom.grok-search` vault row. Unlike kimi.com K3, do not re-mint every thread.

kimi.com web is **not** a persist host. Plugins are marketplace presets (`persist_via_plugins: no`); there is no user HTTP MCP add. Custom MCP is Kimi Work desktop Plugin Builder. K3 sandbox Skill+CLI (`--agent-id kimi`) is a one-chat proof; HOME and `http-mcp.token` wipe. kimi.com/skills Add persists SKILL.md only. Instant without a terminal is chat-only. Do not treat Kimi web as Cue.

From the installed directory, `node scripts/grok-search.cjs` prints usage (exit 2). Init with `node scripts/grok-search.cjs search --query "Node.js official documentation"`. On `auth_required`:

```bash
node scripts/grok-search.cjs auth-start --agent-id <short-host-label>
node scripts/grok-search.cjs auth-status
```

Use `muse`, `doubao`, `cue`, or `kimi` (K3 one-chat proof only) as appropriate. Pass `--invite-code <code>` only when the operator supplied one. Reply with `approveUrl` only, then keep polling `auth-status` in the **same turn**, respecting `intervalSeconds` / `nextRetrySeconds`, until `authenticated`. Do not wait for another user message. On expiry, cancellation, or a terminal error, report the status and stop; do not poll forever. Never print a token, poll secret, or pending auth file. Retry the tiny search after authentication. See [auth-contract.md](auth-contract.md).

## Chat-only and person-outside-chat connector setup

ChatGPT web, Doubao 对话, and WeCom without git + Node or an in-thread MCP card stop at the chat-only route. A chat cannot finish first-time connector setup on these surfaces. A person completes connector/OAuth outside chat; do not ask the chat to create the app, click 去授權, or type the operator password.

- **ChatGPT web:** A person uses `https://chatgpt.com/admin/apps` → Create App, URL `https://search.karldigi.dev/mcp`, OAuth, no custom headers. The GitHub marketplace card is desktop-only because `mcp.json` ships.
- **Doubao Work paid/connector path:** A person uses `技能 · 連接器 · 夥伴` → 连接器 → 新增自定义连接器, HTTP, production URL, no custom headers, then 去授權 in the browser. This person-outside-chat path does not inherit Cue's card flow.
- **Doubao free:** `新建自定义连接器` may be disabled. Skill+CLI works in 工作 / 云电脑 with git + Node; 对话 remains chat-only. Do not send 对话 to 去授權 for first mint.

## Desktop marketplace plugin readiness

These are existing desktop plugin contracts, not instructions for CLI installation or Cue's Apps card:

- Installed `.mcp.json` / Cursor `mcp.json` use `type: http` and `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`. Export `GROK_SEARCH_MCP_TOKEN` in the process launching the client. Grok skips OAuth when that Authorization header is present; a missing token yields 401 instead of `[authenticating]`.
- Claude/Grok default to production. `GROK_SEARCH_MCP_URL` may override only on those hosts. Codex and Cursor-native pin production; the URL is not configurable in Cursor.
- **Claude/Grok plugin hosts:** Resolve `PLUGIN_ROOT` from `GROK_PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT`, then run `python3 "$PLUGIN_ROOT/scripts/check_readiness.py" --apply --json` before the first MCP call. `in_sync` verifies configuration; a live search verifies execution. Keep production if warnings mention a stale preview URL.
- **Codex:** Native manifest uses `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`.
- **Cursor-native / Agent TUI:** Cursor-native pins production and does not run the probe. Installed `mcp.json` uses the environment-backed header above.
- Grok SessionStart cannot inject the parent MCP environment. `~/.config/grok-search/mcp.env` is not auto-sourced. Do not auto-write host configuration or start a local stdio `uvx` server.

### Operator browser and SSH

MCP OAuth loopback binds on the host running the MCP client. Headed vs headless is not the discriminator: `DISPLAY`, VNC, or local Chrome on that host cannot complete a login in a browser on another machine. `SSH_CONNECTION` / `SSH_TTY` is only a hint. Do not tell the operator to click the login link on another machine.

If readiness warns `headless_oauth_loopback`, or Grok sits at `[authenticating]` over SSH, stop and do not press `/mcps` `i`; confirm the launch process has `GROK_SEARCH_MCP_TOKEN`. The operator can consult `cursor-cli-mcp.example.json` for Cursor CLI, or this Grok HTTP overlay in `~/.grok/config.toml` (the agent never writes it):

```toml
[mcp_servers.grok-search]
url = "https://search.karldigi.dev/mcp"

[mcp_servers.grok-search.headers]
Authorization = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
```

If readiness warns `leftover_stdio_config`, a stdio `command=` / `uvx` table still shadows the HTTP plugin. The operator removes that stale table or replaces it with the HTTP overlay. Grok `/mcps` `i` auth is HTTP/SSE only. Do not write `config.toml`.
