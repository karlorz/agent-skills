# grok-search

Thin marketplace plugin for [GrokSearch](https://github.com/karlorz/GrokSearch), providing live web search, structured search intent planning, source extraction, web fetching, and site mapping via Context7-style HTTP MCP.

## Configuration & Environment

The plugin connects over HTTP MCP using two environment variables:

```bash
export GROK_SEARCH_MCP_URL="http://100.76.134.104:8800/mcp"
export GROK_SEARCH_MCP_TOKEN="your-mcp-bearer-token"
```

Operators may store the token at `~/.config/grok-search/http-mcp.token` for convenience. Note that HTTP MCP does not auto-source `mcp.env`; set these variables in your shell profile or session environment before starting the agent.

### Operator Endpoints (cursor-box)

1. **Tailscale (recommended):** `http://100.76.134.104:8800/mcp`
   - Bearer-only: `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`.
   - Never bind the backend service to `0.0.0.0`.
2. **Cloudflare Access:** `https://search.termolo.com/mcp`
   - Token plus operator-local Access headers (`CF-Access-Client-Id`, `CF-Access-Client-Secret`).
   - Access headers stay operator-local and never belong in plugin JSON.

Inbound /mcp is not the outbound httpx client GrokSearch uses toward Grok/Tavily/Firecrawl.

If URL or token is unset, the companion skill asks on first run. Do not auto-write `~/.cursor/mcp.json`, `~/.cursor/plugins/local/*`, or `~/.config/grok-search/mcp.env`.

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
