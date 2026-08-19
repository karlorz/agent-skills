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

### Cursor Desktop

Install `grok-search` from the already-registered `karlorz-agent-skills` marketplace (same plugin bundle as Claude Code). After reload, MCP Servers should list it as a **plugin** server, like `Context7 (plugin)`.

### Migrate from an existing user MCP install

Daily Claude/Cursor already running a manual `grok-search` user server should **move** that install onto the plugin, not keep both.

1. Install/enable the plugin (above).
2. Dry-run (prints paths and env **key names** only, never secret values):

From this repo:

```bash
python3 skills/grok-search/scripts/migrate-from-user-mcp.py
```

After plugin install, run the same script from the plugin cache `scripts/migrate-from-user-mcp.py`.

3. Copy `GUDA_API_KEY`, `GUDA_BASE_URL`, and `GROK_MODEL` from the user MCP into `~/.config/grok-search/mcp.env` (mode 600), then remove the user servers:

```bash
python3 skills/grok-search/scripts/migrate-from-user-mcp.py --apply-env --remove-user-mcp
```

4. Restart Claude Code / Cursor. `claude mcp list` should show `plugin:grok-search:grok-search` (same shape as `plugin:context7:context7`), not a User-config `grok-search`.

The plugin runner sources that env file so GUI Claude does not need the variables in `~/.zshrc`. Do not add a second stdio row to `~/.cursor/mcp.json`.

## MCP Architecture

- **v1 (current):** stdio transport via `uvx --from git+https://github.com/karlorz/GrokSearch@grok-with-tavily grok-search`.
- **Future:** Hosted HTTP MCP support will be introduced via a configuration update in `.mcp.json` (`type: "http"`).

## License

MIT
