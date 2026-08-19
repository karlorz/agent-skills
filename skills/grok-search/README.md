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

Cursor Agent CLI (`agent mcp list`) **only** reads `.cursor/mcp.json` and `~/.cursor/mcp.json`. It does **not** load Claude-style plugin MCP. Context7 can still show as a Desktop plugin while CLI stays empty unless JSON is present.

Do this in order (no secrets in JSON):

1. **Prereqs:** `uv`/`uvx`, Python 3.10+, and `~/.config/grok-search/mcp.env` from the migrate step below.
2. **Desktop:** Settings → Rules, Skills, Subagents → enable **Include third-party Plugins, Skills, and other configs**. Reload the window.
3. **Plugin on disk:** link the plugin so Desktop can chain MCP like Context7:

```bash
mkdir -p ~/.cursor/plugins/local
ln -sfn /path/to/agent-skills/skills/grok-search ~/.cursor/plugins/local/grok-search
```

4. **Remove legacy user MCP** (keys in `~/.cursor/mcp.json`) so you do not run two servers. Use the migrator below.
5. **CLI fallback** (required for `agent mcp list` after step 4): copy `cursor-cli-mcp.example.json` to `~/.cursor/mcp.json` and replace `REPLACE_WITH_PLUGIN_ROOT` with the plugin directory. That JSON has **no API keys**; the runner loads `mcp.env`.

```bash
# example after linking:
# args: ["/Users/you/.cursor/plugins/local/grok-search/scripts/run-grok-search.sh"]
```

6. Reload Cursor / start a **new** `agent` session. Desktop should show `grok-search (plugin)` if third-party plugins loaded; CLI should show `grok-search: ready` from the wrapper JSON.

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
