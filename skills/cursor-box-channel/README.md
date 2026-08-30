# cursor-box-channel

Thin marketplace plugin for cursor-box-channel. Marketplace install is HTTP Streamable MCP at `https://channel.termolo.com/mcp` with a required origin Bearer.

## Install

From `karlorz-agent-skills`:

```bash
claude plugin install cursor-box-channel@karlorz-agent-skills
```

Cursor: install the plugin, then **Plugins → Configure** and enter `CURSOR_BOX_MCP_TOKEN`. Codex: `codex plugin add cursor-box-channel@karlorz-agent-skills` and set the same bearer.

## Token

- Plugin client variable (pinned): `CURSOR_BOX_MCP_TOKEN`
- Sidecar server env: `MCP_HTTP_TOKEN`
- Operator sets the same secret in both places. Cursor/Codex docs may mention `${MCP_HTTP_TOKEN}` as an alias; the plugin variable name stays `CURSOR_BOX_MCP_TOKEN`.
- Never print a real token.

Claude/Grok default URL is `https://channel.termolo.com/mcp` (`CURSOR_BOX_MCP_URL` override). Cursor-native and Codex pin that URL.

## Attended-only

The queue waits if Grok Bot is closed. There is no grok CLI wrapper. Origin Bearer is required.

The Mac launchd+stdio daemon still exists in `karlorz/cursor-box-channel`. Marketplace install does not use that stdio runner.

Plugin install does not write `~/.cursor/mcp.json`. `agent mcp list` inspects static `~/.cursor/mcp.json`, not plugin MCP. For headless `agent -p` without plugin flags, see `cursor-cli-mcp.example.json`.

## License

MIT
