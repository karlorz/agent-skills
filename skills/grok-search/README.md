# grok-search

Thin marketplace plugin for [GrokSearch](https://github.com/karlorz/GrokSearch), providing live web search, structured search intent planning, source extraction, web fetching, and site mapping via Context7-style HTTP MCP OAuth.

## Configuration & Environment

For **Claude and Grok plugin hosts**, the plugin defaults the MCP URL to `https://search.karldigi.dev/mcp`; set `GROK_SEARCH_MCP_URL` only to override that endpoint. **Codex and Cursor** marketplace packages pin production; the URL is not configurable in Cursor.

The installed desktop plugin connects via **MCP OAuth** and does not require or store a bearer token. Claude `userConfig` token prompts and Cursor plugin variables have been removed.

For headless batch workflows (such as `agent -p`), an optional wrapper example is available in `cursor-cli-mcp.example.json` using `Bearer ${env:GROK_SEARCH_MCP_TOKEN}`.

```bash
# Optional for Claude/Grok only:
export GROK_SEARCH_MCP_URL="https://search.karldigi.dev/mcp"
# Only needed for optional headless bearer use (e.g. cursor-cli-mcp.example.json):
# export GROK_SEARCH_MCP_TOKEN="your-gateway-keys-token"
```

Operators may store a token at `~/.config/grok-search/http-mcp.token` for convenience when using gateway keys, but HTTP MCP does not auto-source that file or `mcp.env`. For **Cursor**, the installed plugin pins production and connects via OAuth without requiring process environment variables.

### Operator Endpoints

1. **Production (recommended, kr01 proven):** `https://search.karldigi.dev/mcp`
   - Installed plugin authenticates via **MCP OAuth** (gateway-keys bearer tokens generated from `https://search.karldigi.dev/admin/gateway-keys` remain supported for optional headless clients).
   - Cursor-native pins this endpoint without requiring token configuration.
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

Install the plugin from the marketplace. Claude `userConfig` has been removed and does not prompt for a token; the plugin connects via HTTP MCP OAuth.

```bash
claude plugin install grok-search@karlorz-agent-skills
```

### Codex

Install from the configured `karlorz-agent-skills` marketplace and restart Codex:

```bash
codex plugin add grok-search@karlorz-agent-skills
codex mcp get grok-search
```

The Codex-native manifest embeds an HTTP MCP definition pointing to `https://search.karldigi.dev/mcp` via MCP OAuth with no bundled bearer or `bearer_token_env_var`.

### Cursor (Desktop + Agent CLI)

1. **Desktop / Agent settings:** Install/enable the plugin. Settings → Rules, Skills, Subagents → enable **Include third-party Plugins, Skills, and other configs**.
2. **Plugin loading:** After marketplace install, grok-search MCP loads automatically in Cursor Agent TUI via the plugin chain (`plugin-grok-search-grok-search` or `plugin-chain`) using MCP OAuth. No token variable or `Plugins → Configure` step is required.
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
2. Confirm the agent discovers and invokes tools such as `get_config_info` or `web_search`. Live session tool execution is the ground truth, not `agent mcp list`. Complete the first-run OAuth prompt if your host requests it.

A healthy production `get_config_info` response identifies the configured
remote streamable-HTTP endpoint and confirms that the client needs no local
server stack. See the companion
[SKILL.md](skills/grok-search/SKILL.md#diagnostics) for the canonical diagnostic
safety contract.

## Archived stdio Client

Previous versions supported local stdio execution via `uvx`. All legacy stdio scripts, migration utilities, and stdio examples have been archived under `archive/skills/grok-search-stdio/`.

## License

MIT
