# grok-search

Thin marketplace plugin for [GrokSearch](https://github.com/karlorz/GrokSearch), providing live web search, structured search intent planning, source extraction, web fetching, and site mapping via Context7-style HTTP MCP.

## Configuration & Environment

For **Claude and Grok plugin hosts**, the plugin defaults the MCP URL to `https://search.karldigi.dev/mcp`; set `GROK_SEARCH_MCP_URL` only to override that endpoint. **Codex and Cursor** marketplace packages pin production. A gateway-keys bearer must be available before MCP loading:

```bash
export GROK_SEARCH_MCP_TOKEN="your-gateway-keys-token"
# Optional for Claude/Grok only:
export GROK_SEARCH_MCP_URL="https://search.karldigi.dev/mcp"
```

Operators may store a token at `~/.config/grok-search/http-mcp.token` for convenience, but HTTP MCP does not auto-source that file or `mcp.env`. Export the gateway-keys bearer before starting Grok, Claude, or Orca sessions. For **Codex Desktop/IDE**, place the variable in Codex's supported `~/.codex/.env` file and fully restart Codex; never put the value in `config.toml` or plugin files. For **Cursor**, configure the token via **Plugins → Configure** instead of process environment variables.

### Operator Endpoints

1. **Production (recommended):** `https://search.karldigi.dev/mcp`
   - Bearer is a **gateway-keys** token generated from `https://search.karldigi.dev/admin/gateway-keys` (create-once / show-raw-once).
   - Set as `GROK_SEARCH_MCP_TOKEN` in the Claude/Grok process environment, or enter it in Cursor under **Plugins → Configure**.
2. **Tailscale (preview / fallback):** `http://100.76.134.104:8800/mcp`
   - Bearer-only: `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`.
   - Preview / fallback endpoint until kr01 is proven.
   - Never bind the backend service to `0.0.0.0`.
3. **Cloudflare Access (preview / fallback):** `https://search.termolo.com/mcp`
   - Token plus operator-local Access headers (`CF-Access-Client-Id`, `CF-Access-Client-Secret`).
   - Preview / fallback endpoint until kr01 is proven.
   - Access headers stay operator-local and never belong in plugin JSON.

### Grok startup boundary

Grok resolves plugin MCP configuration before a SessionStart child can change the parent environment. **SessionStart cannot inject Grok's parent MCP environment.** The hook may populate Claude's `CLAUDE_ENV_FILE`, but it cannot supply a missing Grok token. A new Grok session is necessary after a plugin update and still requires `GROK_SEARCH_MCP_TOKEN` in the process environment.

A leftover `grok-search-http` server inherited from `~/.cursor/mcp.json` is **not a fallback**. It is a separate preview overlay and must not be dual-called. Remove it only after native Cursor and Grok `grok-search` handshakes are proven.

### Operator Troubleshooting Note

Upstream x.ai web → grok2api can make the gateway `POST /grok/v1/chat/completions` return empty `content` (seen with `grok-4.3-fast`). If MCP tools/list works but `web_search` returns blank results, debug grok2api / model routing on the backend, not the plugin URL or client configuration.

Inbound /mcp is not the outbound httpx client GrokSearch uses toward Grok/Tavily/Firecrawl.

A SessionStart hook / `scripts/check_readiness.py` checks the token and can write the production URL to Claude's `CLAUDE_ENV_FILE` when available. It does not auto-source `mcp.env`, change Grok's parent MCP environment, or auto-write `~/.cursor/mcp.json`, `~/.cursor/plugins/local/*`, Grok `config.toml`, or `~/.config/grok-search/mcp.env`. If the token is unset, the companion skill stops and asks.

## Installation

### Claude Code

Install from the `karlorz-agent-skills` marketplace catalog:

```bash
claude plugin install grok-search@karlorz-agent-skills
```

### Codex

Install from the configured `karlorz-agent-skills` marketplace, ensure
`GROK_SEARCH_MCP_TOKEN` is available to the Codex process, and fully restart
Codex after installation or environment changes:

```bash
codex plugin add grok-search@karlorz-agent-skills
codex mcp get grok-search
```

The Codex-native manifest embeds its own MCP definition so Codex never
parses the Claude/Grok shell-style URL fallback. The healthy structural result
uses the absolute production URL and reports `GROK_SEARCH_MCP_TOKEN` as the
bearer-token environment variable. Do not print or paste the token value during
verification.

### Cursor (Desktop + Agent CLI)

1. **Prerequisites:** Install/enable the Cursor-native plugin, then open **Plugins → Configure** for `grok-search` and enter a gateway-keys bearer in `GROK_SEARCH_MCP_TOKEN`. This is a Cursor plugin variable, not a Cursor process-environment setting. The native plugin pins production; no `uvx` / GUDA installation is required.
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
