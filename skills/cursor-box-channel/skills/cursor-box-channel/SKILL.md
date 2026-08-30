---
name: cursor-box-channel
description: "This skill should be used when an agent needs to ask, list replies, heartbeat, claim, or reply on cursor-box-channel HTTP MCP (attended-only)."
---

# Cursor Box Channel

Use this skill for attended HTTP Streamable MCP at `https://channel.termolo.com/mcp`.

Marketplace install is HTTP only. Do not start a local stdio daemon or grok CLI wrapper. The Mac launchd+stdio daemon still exists in the `karlorz/cursor-box-channel` repo, but this plugin talks to the hosted channel.

## First-run

- Plugin client variable: `CURSOR_BOX_MCP_TOKEN` (Cursor: Plugins → Configure). Claude/Grok/Codex need the same bearer in process environment.
- Sidecar server env is `MCP_HTTP_TOKEN`. The operator sets the same secret in both places. Cursor/Codex docs may mention `${MCP_HTTP_TOKEN}` as an alias; pin the plugin variable name to `CURSOR_BOX_MCP_TOKEN`.
- Origin Bearer is required. A 401 is a handshake failure; report it and stop.
- Never print a real token. Never auto-write `~/.cursor/mcp.json` or Grok `config.toml`.
- Attended-only: the queue waits if Grok Bot is closed. Do not invent a grok CLI wrapper or force a closed consumer.

## Tools

- `ask`: post a question and wait for a reply (queue waits if Grok Bot is closed).
- `list_replies`: list pending or completed replies.
- `heartbeat`: keep the attended session alive.
- `claim`: claim a queued item for this session.
- `reply`: send a reply to a claimed or asked item.

If tools are connected, continue. If the token is missing or MCP is disconnected, stop and ask the operator to set `CURSOR_BOX_MCP_TOKEN`.
