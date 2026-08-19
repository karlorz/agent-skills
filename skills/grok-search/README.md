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

Then disable the existing **user** `grok-search` entry so Desktop does not start two copies. Do not add a second stdio row to `~/.cursor/mcp.json` for this plugin.

## MCP Architecture

- **v1 (current):** stdio transport via `uvx --from git+https://github.com/karlorz/GrokSearch@grok-with-tavily grok-search`.
- **Future:** Hosted HTTP MCP support will be introduced via a configuration update in `.mcp.json` (`type: "http"`).

## License

MIT
