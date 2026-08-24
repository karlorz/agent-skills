# grok-search

Thin marketplace plugin for [GrokSearch](https://github.com/karlorz/GrokSearch), providing live web search, structured search intent planning, source extraction, web fetching, and site mapping via Context7-style HTTP MCP.

## Configuration & Environment

The plugin connects over HTTP MCP using two environment variables:

```bash
export GROK_SEARCH_MCP_URL="https://search.karldigi.dev/mcp"
export GROK_SEARCH_MCP_TOKEN="your-gateway-keys-token"
```

Operators may store the token at `~/.config/grok-search/http-mcp.token` for convenience. Note that HTTP MCP does not auto-source `mcp.env`; set these variables in your shell profile or session environment before starting the agent.

### Operator Endpoints

1. **Production (recommended):** `https://search.karldigi.dev/mcp`
   - Bearer is a **gateway-keys** token generated from `https://search.karldigi.dev/admin/gateway-keys` (create-once / show-raw-once).
   - Set as `GROK_SEARCH_MCP_TOKEN` in client environment.
2. **Tailscale (preview / fallback):** `http://100.76.134.104:8800/mcp`
   - Bearer-only: `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`.
   - Preview / fallback endpoint until kr01 is proven.
   - Never bind the backend service to `0.0.0.0`.
3. **Cloudflare Access (preview / fallback):** `https://search.termolo.com/mcp`
   - Token plus operator-local Access headers (`CF-Access-Client-Id`, `CF-Access-Client-Secret`).
   - Preview / fallback endpoint until kr01 is proven.
   - Access headers stay operator-local and never belong in plugin JSON.

### Operator Troubleshooting Note

Upstream x.ai web → grok2api can make the gateway `POST /grok/v1/chat/completions` return empty `content` (seen with `grok-4.3-fast`). If MCP tools/list works but `web_search` returns blank results, debug grok2api / model routing on the backend, not the plugin URL or client configuration.

Inbound /mcp is not the outbound httpx client GrokSearch uses toward Grok/Tavily/Firecrawl.

A SessionStart hook / `scripts/check_readiness.py` applies the production URL in-process when the token is set and the URL is empty. It does not auto-write `~/.cursor/mcp.json`, `~/.cursor/plugins/local/*`, or `~/.config/grok-search/mcp.env`. If the token is unset, the companion skill stops and asks. After a plugin update, start a **new session**.

## Installation

### Claude Code

Install from the `karlorz-agent-skills` marketplace catalog:

```bash
claude plugin install grok-search@karlorz-agent-skills
```

### Cursor (Desktop + Agent CLI)

1. **Prerequisites:** Set `GROK_SEARCH_MCP_URL` and `GROK_SEARCH_MCP_TOKEN`. No `uvx` / GUDA installation is required.
2. **Desktop / Agent settings:** Settings → Rules, Skills, Subagents → enable **Include third-party Plugins, Skills, and other configs**. Reload the window / restart your session.
3. **Plugin loading:** After marketplace install, grok-search MCP loads automatically in Cursor Agent TUI via the plugin chain (`plugin-grok-search-grok-search` or `plugin-chain`) when third-party / Claude-compat plugins are enabled.
4. **Diagnostic note on `agent mcp list`:** `agent mcp list` inspects `~/.cursor/mcp.json` and `.cursor/mcp.json`, not Claude-style plugin `.mcp.json` definitions. This is a known CLI diagnostic gap and is not the proof of install.
5. **Optional headless wrapper (`cursor-cli-mcp.example.json`):** For headless batch commands (`agent -p`) invoked without `--plugin-dir`, you can optionally configure a JSON wrapper in `~/.cursor/mcp.json`. This wrapper is purely optional and is not required for normal interactive Cursor Agent TUI or plugin-chain usage. Do not treat writing that file as part of marketplace install.

## Verification

To verify that grok-search MCP is active and functioning properly:

1. In a live Cursor Agent session or Claude Code session, ask the agent to run an MCP tool check:
   ```text
   Use grok-search get_config_info and web_search for the latest AI news.
   ```
2. Confirm the agent discovers and invokes tools such as `get_config_info` or `web_search`. Live session tool execution is the ground truth, not `agent mcp list`.

## Archived stdio Client

Previous versions supported local stdio execution via `uvx`. All legacy stdio scripts, migration utilities, and stdio examples have been archived under `archive/skills/grok-search-stdio/`.

## License

MIT
