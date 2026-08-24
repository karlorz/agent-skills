# Archived: grok-search stdio Transport

- **Status**: Archived
- **Date**: 2026-08-24
- **Reason**: The `grok-search` plugin client has migrated to Context7-style HTTP-only MCP (`type: "http"` pointing to `${GROK_SEARCH_MCP_URL}` with `Bearer ${GROK_SEARCH_MCP_TOKEN}`). Local `uvx` / stdio execution is archived for emergency reference only.

## Archived Artifacts

- `run-grok-search.sh`: Bash wrapper script that sourced `~/.config/grok-search/mcp.env` and launched `uvx --from git+https://github.com/karlorz/GrokSearch@grok-with-tavily grok-search`.
- `migrate-from-user-mcp.py`: Python migration script to migrate legacy stdio user MCP setups.
- `cursor-cli-mcp.example.json`: Legacy stdio JSON wrapper for Cursor CLI pointing to `run-grok-search.sh`.
- `cursor-cli-http.example.json`: Additive `grok-search-http` example replaced by unified HTTP-only `grok-search` configuration.
