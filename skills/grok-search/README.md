# grok-search

Thin marketplace plugin for [GrokSearch](https://github.com/karlorz/GrokSearch), providing live web search, structured search intent planning, source extraction, web fetching, and site mapping via Context7-style HTTP MCP.

## Configuration & Environment

For **Claude and Grok plugin hosts**, the plugin defaults the MCP URL to `https://search.karldigi.dev/mcp`; set `GROK_SEARCH_MCP_URL` only to override that endpoint. **Codex and Cursor** marketplace packages pin production; the URL is not configurable in Cursor.

The installed desktop plugin sends `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}` from `.mcp.json` (Claude/Grok) and `mcp.json` (Cursor). Codex uses `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`. Export `GROK_SEARCH_MCP_TOKEN` in the shell that launches the client. Grok skips OAuth discovery when that Authorization header is present. Claude `userConfig` token prompts and Cursor plugin variables stay removed. ChatGPT Admin Apps and Doubao Work keep HTTPS OAuth.

For headless batch workflows (such as `agent -p`), the optional `cursor-cli-mcp.example.json` wrapper applies.

```bash
# Optional for Claude/Grok only:
export GROK_SEARCH_MCP_URL="https://search.karldigi.dev/mcp"
export GROK_SEARCH_MCP_TOKEN="your-gateway-keys-token"
```

Operators may store a token at `~/.config/grok-search/http-mcp.token` for convenience when using gateway keys, but HTTP MCP does not auto-source that file or `mcp.env`. Cursor-native pins production and reads `Bearer ${GROK_SEARCH_MCP_TOKEN}` from installed `mcp.json`.

### Operator browser not on this host (SSH)

The OAuth loopback is same-host: it binds on the machine running the MCP client. When the operator browser is on another machine (for example Grok over SSH on pvelxc, browser on a Mac), the callback never reaches the waiting client, and Grok sits at `[authenticating]` unless the installed plugin already has an Authorization header. Headed vs headless is not the discriminator: `DISPLAY`, VNC, or a local Chrome on the SSH host opens a browser there, not on the operator's machine. `SSH_CONNECTION` / `SSH_TTY` is only a hint, and the probe reports it as `headless_oauth_loopback`. Do not finish the login link on another machine, and do not press `/mcps` `i` over SSH.

Export `GROK_SEARCH_MCP_TOKEN` so Grok skips OAuth. A missing token still leaves the header key, so Grok 401s instead of starting OAuth. For **Cursor CLI**, `cursor-cli-mcp.example.json` (`Bearer ${env:GROK_SEARCH_MCP_TOKEN}`) remains the optional batch wrapper. ChatGPT/Doubao `https` redirects stay OAuth.

A Grok marketplace plugin upgrade does not remove leftover user TOML. If `~/.grok/config.toml` still has `[mcp_servers.grok-search]` with `command` (stdio `uvx`), that table still shadows the HTTP plugin and any HTTP overlay. `/mcps` `i` auth then fails with `does not use OAuth`. Remove the stdio table, or replace `command=` with this HTTP overlay. The probe never writes `config.toml`.

```toml
[mcp_servers.grok-search]
url = "https://search.karldigi.dev/mcp"

[mcp_servers.grok-search.headers]
Authorization = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
```

### Operator Endpoints

1. **Production (recommended, kr01 proven):** `https://search.karldigi.dev/mcp`
   - Installed desktop plugin authenticates with `Bearer ${GROK_SEARCH_MCP_TOKEN}` (create a gateway key at `https://search.karldigi.dev/admin/gateway-keys`). ChatGPT/Doubao keep MCP OAuth.
   - Cursor-native pins this endpoint and reads the same env-backed Authorization header.
2. **Stale Tailscale preview — do not use, do not start on sg01:**
   - Retired URLs: `http://100.76.134.104:8800/mcp` (old Tailscale IP) and `http://100.118.12.90:8800/mcp` (current sg01 Tailscale, no `:8800` listener).
   - `scripts/check_readiness.py` emits a `warnings` entry if `GROK_SEARCH_MCP_URL` still points at those hosts. Status stays `in_sync`; the probe never live-checks `:8800` and never starts a service.
3. **Cloudflare Access (preview / fallback):** `https://search.termolo.com/mcp`
   - Requires operator-local Access headers (`CF-Access-Client-Id`, `CF-Access-Client-Secret`).
   - Access headers stay operator-local and never belong in plugin JSON.

### Grok startup boundary

Grok resolves plugin MCP configuration before a SessionStart child can change the parent environment. **SessionStart cannot inject Grok's parent MCP environment.** The hook may populate Claude's `CLAUDE_ENV_FILE`, but it cannot supply parent environment variables.

A leftover `grok-search-http` server inherited from `~/.cursor/mcp.json` is **not a fallback**. It is a separate preview overlay and must not be dual-called. Remove it only after native Cursor and Grok `grok-search` handshakes are proven.

### Operator Troubleshooting Note

Upstream x.ai web → grok2api can make the gateway `POST /grok/v1/chat/completions` return empty `content` (seen with `grok-4.3-fast`). If MCP tools/list works but `web_search` returns blank results, debug grok2api / model routing on the backend, not the plugin URL or client configuration.

Inbound /mcp is not the outbound httpx client GrokSearch uses toward Grok/Tavily/Firecrawl. Never bind a local grok-search listener to `0.0.0.0`.

A SessionStart hook / `scripts/check_readiness.py` checks readiness and can write the production URL to Claude's `CLAUDE_ENV_FILE` when available. It warns when `GROK_SEARCH_MCP_URL` still names the retired Tailscale/sg01 `:8800` preview. It does not auto-source `mcp.env`, change Grok's parent MCP environment, live-probe sg01, start `:8800`, or auto-write `~/.cursor/mcp.json`, `~/.cursor/plugins/local/*`, Grok `config.toml`, or `~/.config/grok-search/mcp.env`.

## Installation

### Claude Code

Install the plugin from the marketplace. Claude `userConfig` stays removed and does not prompt for a token; export `GROK_SEARCH_MCP_TOKEN` in the process environment. The plugin `.mcp.json` sends `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`.

```bash
claude plugin install grok-search@karlorz-agent-skills
```

### Codex

Install from the configured `karlorz-agent-skills` marketplace and restart Codex:

```bash
codex plugin add grok-search@karlorz-agent-skills
codex mcp get grok-search
```

The Codex-native manifest embeds an HTTP MCP definition pointing to `https://search.karldigi.dev/mcp` with `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`. Export that env in the Codex process. ChatGPT/Doubao HTTPS OAuth is unchanged.

### Cursor (Desktop + Agent CLI)

1. **Desktop / Agent settings:** Install/enable the plugin. Settings → Rules, Skills, Subagents → enable **Include third-party Plugins, Skills, and other configs**.
2. **Plugin loading:** After marketplace install, grok-search MCP loads automatically in Cursor Agent TUI via the plugin chain (`plugin-grok-search-grok-search` or `plugin-chain`). Installed `mcp.json` sends `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`. Cursor plugin `variables` stay removed, so there is no `Plugins → Configure` token prompt; export the env in the process that launches Agent.
3. **Diagnostic note on `agent mcp list`:** `agent mcp list` inspects `~/.cursor/mcp.json` and `.cursor/mcp.json`, not Claude-style plugin `.mcp.json` definitions. This is a known CLI diagnostic gap and is not the proof of install.
4. **Optional headless wrapper (`cursor-cli-mcp.example.json`):** For headless batch commands (`agent -p`) invoked without `--plugin-dir`, you can optionally configure a JSON wrapper in `~/.cursor/mcp.json`. This wrapper is purely optional and is not required for normal interactive Cursor Agent TUI or plugin-chain usage. Do not treat writing that file as part of marketplace install.

### ChatGPT web and Doubao Work

A chat cannot finish first-time connector setup. The person completes consent outside the chat. After that, the chat may call `web_search`.

ChatGPT web uses **Admin Apps** (`https://chatgpt.com/admin/apps` Create App) with `https://search.karldigi.dev/mcp` and OAuth. The GitHub marketplace card is desktop-only because `mcp.json` ships. The ChatGPT chat cannot open that admin page.

Doubao Work uses `技能 · 連接器 · 夥伴` → 我的技能 → 連接器 → 新增自訂連接器. Choose HTTP, name `grok-search`, URL `https://search.karldigi.dev/mcp`, and add no custom headers. Then choose 去授權 and enter the operator password in the browser. The Doubao chat cannot click that button or type the password.

## Verification

To verify that grok-search MCP is active and functioning properly:

1. In a live Cursor Agent session or Claude Code session, ask the agent to run an MCP tool check:
   ```text
   Use grok-search get_config_info and web_search for the latest AI news.
   ```
2. Confirm the agent discovers and invokes tools such as `get_config_info` or `web_search`. Live session tool execution is the ground truth, not `agent mcp list`. Desktop clients use `GROK_SEARCH_MCP_TOKEN`; a missing token is a 401. ChatGPT/Doubao still complete first-run OAuth outside the chat.

A healthy production `get_config_info` response identifies the configured
remote streamable-HTTP endpoint and confirms that the client needs no local
server stack. See the companion
[SKILL.md](skills/grok-search/SKILL.md#diagnostics) for the canonical diagnostic
safety contract.

## Archived stdio Client

Previous versions supported local stdio execution via `uvx`. All legacy stdio scripts, migration utilities, and stdio examples have been archived under `archive/skills/grok-search-stdio/`.

## License

MIT
