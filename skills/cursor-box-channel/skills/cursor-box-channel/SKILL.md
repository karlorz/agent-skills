---
name: cursor-box-channel
description: "This skill should be used when an agent needs to ask, list replies, heartbeat, claim, or reply on cursor-box-channel HTTP MCP (attended-only), or open the read-only audit console."
---

# Cursor Box Channel

Use this skill for attended HTTP Streamable MCP at `https://channel.termolo.com/mcp`. Core logic lives on that remote backend.

Marketplace install is HTTP only. Do not start a local stdio daemon or grok CLI wrapper. The Mac launchd+stdio daemon still exists in the `karlorz/cursor-box-channel` repo, but this plugin talks to the hosted channel.

## First-run

- Plugin client variable: `CURSOR_BOX_MCP_TOKEN` (Cursor: Plugins → Configure). Claude/Grok/Codex need the same bearer in process environment.
- Sidecar server env is `MCP_HTTP_TOKEN`. The operator sets the same secret in both places. Cursor/Codex docs may mention `${MCP_HTTP_TOKEN}` as an alias; pin the plugin variable name to `CURSOR_BOX_MCP_TOKEN`.
- Origin Bearer is required on `/mcp`. A 401 is a handshake failure; report it and stop.
- Never print a real token. Never auto-write `~/.cursor/mcp.json` or Grok `config.toml`.
- Attended-only: the queue waits if Grok Bot is closed. Do not invent a grok CLI wrapper or force a closed consumer.

## Audit console (optional wrapper)

- Live URL: `https://channel.termolo.com/console`
- Browser gate is Cloudflare Access on `/console*` only. Do **not** send `CURSOR_BOX_MCP_TOKEN` to `/console`. `/mcp` stays Bearer-only.
- Read-only. HTML fetches `/console` and `/console/api/*` only. Never call `/mcp` from the browser.
- To print the URL with no secrets: `python3 "$PLUGIN_ROOT/scripts/open-console.py"` (falls back to `CLAUDE_PLUGIN_ROOT`).

## Routing

- `ask.to` is `newbie` or `wiki-research` only. There is no `grok` target.
- `post_message.to` may also be `channel`.

## Tools

- `ask`: post a question and wait for a reply (queue waits if Grok Bot is closed).
- `post_message`: fire-and-forget (`to` `channel` | `newbie` | `wiki-research`).
- `list_replies`: list pending or completed replies.
- `heartbeat`: keep the attended session alive.
- `claim`: claim a queued item for this session.
- `reply`: send a reply to a claimed or asked item.
- `bridge_status`: gateway health.

If tools are connected, continue. If the token is missing or MCP is disconnected, stop and ask the operator to set `CURSOR_BOX_MCP_TOKEN`.
