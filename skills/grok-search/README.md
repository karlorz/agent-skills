# grok-search

Thin marketplace plugin for [GrokSearch](https://github.com/karlorz/GrokSearch), providing live web search, structured search intent planning, source extraction, web fetching, and site mapping via stdio MCP.

## Prerequisites

- Python 3.10+
- `uv` / `uvx` installed and available in `PATH`
- Environment variables configured prior to launching your agent/editor:
  ```bash
  export GUDA_API_KEY="your-api-key"
  export GUDA_BASE_URL="https://your-api-gateway-url"
  ```

## Installation

### Claude Code

Install from the `karlorz-agent-skills` marketplace catalog:

```bash
claude plugin install grok-search@karlorz-agent-skills
```

### Cursor (Desktop + Agent CLI)

1. **Prerequisites:** `uv`/`uvx`, Python 3.10+, and environment variables (`GUDA_API_KEY`, `GUDA_BASE_URL`).
2. **Desktop / Agent settings:** Settings → Rules, Skills, Subagents → enable **Include third-party Plugins, Skills, and other configs**. Reload the window / restart your session.
3. **Plugin loading:** After marketplace install, grok-search MCP loads automatically in Cursor Agent TUI via the plugin chain (`plugin-grok-search-grok-search`) when third-party / Claude-compat plugins are enabled.
4. **Diagnostic note on `agent mcp list`:** `agent mcp list` returns empty because it only inspects `~/.cursor/mcp.json` and `.cursor/mcp.json`, not Claude-style plugin `.mcp.json` definitions. This is a diagnostic gap in the CLI listing tool, not proof the plugin is broken. Therefore, `agent mcp list` is not the proof of install.
5. **Optional headless wrapper (`cursor-cli-mcp.example.json`):** For headless batch commands (`agent -p`) invoked without `--plugin-dir`, you can optionally configure a JSON wrapper pointing `run-grok-search.sh` to `~/.cursor/mcp.json`. This wrapper is purely OPTIONAL and is not required for normal interactive Cursor Agent TUI or plugin-chain usage.
   Do not auto-write operator configuration paths (`~/.cursor/mcp.json`, `~/.cursor/plugins/local/*`, `~/.config/grok-search/mcp.env`); let operators configure them deliberately if needed.

## Verify it works

To verify that grok-search MCP is active and functioning properly:

1. In a live Cursor Agent session or Claude Code session, ask the agent to run an MCP tool check:
   ```text
   Use grok-search get_config_info and web_search for the latest AI news.
   ```
2. Confirm the agent discovers and invokes tools such as `get_config_info` or `web_search`. Live session tool execution is the ground truth, not `agent mcp list`.
3. If using headless CLI invocations, you can approve MCP tools explicitly:
   ```bash
   agent --plugin-dir /path/to/plugin/grok-search --approve-mcps --trust -f -p "Use grok-search get_config_info"
   ```

## Migrate from an existing user MCP install

If you previously configured a manual user-level `grok-search` entry in `~/.claude.json` or `~/.cursor/mcp.json`, you can optionally migrate environment settings to avoid running duplicate servers. (This cleanup is optional and not required for a fresh marketplace install.)

1. Dry-run (prints paths and env key names only, never secret values):

From this repo:

```bash
python3 skills/grok-search/scripts/migrate-from-user-mcp.py
```

After plugin install, run the same script from the plugin cache `scripts/migrate-from-user-mcp.py`.

2. Copy `GUDA_API_KEY`, `GUDA_BASE_URL`, and `GROK_MODEL` from the user MCP into `~/.config/grok-search/mcp.env` (mode 600), then remove the user servers:

```bash
python3 skills/grok-search/scripts/migrate-from-user-mcp.py --apply-env --remove-user-mcp
```

3. Restart Claude Code / Cursor. `claude mcp list` should show `plugin:grok-search:grok-search` without duplicate user-level servers.

The plugin runner sources that env file so GUI Claude does not need the variables in `~/.zshrc`. Do not add a second stdio row to `~/.cursor/mcp.json`.

## MCP Architecture

- **stdio (default):** `uvx --from git+https://github.com/karlorz/GrokSearch@grok-with-tavily grok-search` via `scripts/run-grok-search.sh`. Needs `GUDA_API_KEY` / `GUDA_BASE_URL`.
- **http (additive):** official Cursor `type: "http"` in the same `.mcp.json` as `grok-search-http`. Points at cursor-box Tailscale `http://100.76.134.104:8800/mcp` with `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`.
  - Operator supplies `GROK_SEARCH_MCP_TOKEN`. Do not reuse `GUDA_API_KEY`, `GROK_API_KEY`, `TAVILY_API_KEY`, or `FIRECRAWL_API_KEY`. No live keys in git.
  - Never set the server bind to `0.0.0.0`. Tailscale-only.
  - Optional CLI wrapper: `cursor-cli-http.example.json` (same shape; still no secrets).
  - Same tools as stdio. Inbound `/mcp` is not the outbound `httpx` client.

## License

MIT
