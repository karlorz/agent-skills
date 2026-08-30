---
name: cursor-box-channel
description: "This skill should be used when an agent needs to ask, list replies, heartbeat, claim, or reply on cursor-box-channel HTTP MCP (attended-only), or open the read-only audit console."
---

# Cursor Box Channel

Use this skill for attended HTTP Streamable MCP at `https://channel.termolo.com/mcp`.

Marketplace install is HTTP only. Do not start a local stdio daemon or grok CLI wrapper. The Mac launchd+stdio daemon still exists in the `karlorz/cursor-box-channel` repo, but this plugin talks to the hosted channel.

## First-run

- Plugin client variable: `CURSOR_BOX_MCP_TOKEN` (Cursor: Plugins → Configure). Claude/Grok/Codex need the same bearer in process environment.
- Sidecar server env is `MCP_HTTP_TOKEN`. The operator sets the same secret in both places. Cursor/Codex docs may mention `${MCP_HTTP_TOKEN}` as an alias; pin the plugin variable name to `CURSOR_BOX_MCP_TOKEN`.
- Origin Bearer is required on `/mcp`. A 401 is a handshake failure; report it and stop.
- Never print a real token. Never auto-write `~/.cursor/mcp.json` or Grok `config.toml`.
- Attended-only: the queue waits if Grok Bot is closed. Do not invent a grok CLI wrapper or force a closed consumer.
- Token file path only: `~/.config/cursor-box-channel/mcp-http.token` (mode 600). Never paste the value.

## Audit console (optional wrapper)

- Live URL: `https://channel.termolo.com/console`
- Browser gate is Cloudflare Access on `/console*` only. Do **not** send `CURSOR_BOX_MCP_TOKEN` to `/console`. `/mcp` stays Bearer-only.
- Read-only: status, queue depth, replies, per-id lookup. No claim, retry, dead-letter, or send.
- HTML fetches `/console` and `/console/api/*` only. Never call `/mcp` from the browser.
- Default page size 20. No meta-refresh. Timestamps are ISO + HKT.
- This replaces leftover `cbc-admin` read-only CLI. Do not start a second dashboard or `httpd.py`.
- To print the URL with no secrets: `python3 "$PLUGIN_ROOT/scripts/open-console.py"` (falls back to `CLAUDE_PLUGIN_ROOT`).

## Routing

- `ask.to` is `newbie` or `wiki-research` only. There is no `grok` target.
- Direct questions: `ask` with `to=newbie` (default). Wiki/vault work: `to=wiki-research`.
- `post_message.to` may also be `channel` (async broadcast).
- `timeout_seconds` default 60, max 300. If Peer B is offline, `ask` returns pending with `reply` null. Retry later or check `/console`. Do not invent a second transport.

## Tools

- `ask`: post a question and wait for a reply (queue waits if Grok Bot is closed).
- `post_message`: fire-and-forget (`to` `channel` | `newbie` | `wiki-research`).
- `list_replies`: list pending or completed replies.
- `heartbeat`: keep the attended session alive.
- `claim`: claim a queued item for this session.
- `reply`: send a reply to a claimed or asked item.
- `bridge_status`: gateway health.

If tools are connected, continue. If the token is missing or MCP is disconnected, stop and ask the operator to set `CURSOR_BOX_MCP_TOKEN`.

### Mac agent (Peer A)

Use `ask` / `post_message` as above. After an ask, `list_replies` if you need history. Do not send tokens, cookies, or `claim_token` values in `text`. Stuck? Open `/console` (Access), then file an issue with the checklist below.

### Newbie (Peer B)

Attended-only. Only when the Grok Bot app is open. `heartbeat` online, `claim` (limit 1), then `reply` with `message_id`, `thread_id`, `claim_token` from the claim (never log it), and `body`. Do not claim as `wiki-research` unless the message is for that consumer. If claim is empty and `/console` still shows unclaimed mail, report via the checklist. Do not re-drive known dead-letters.

### wiki-research

Same claim/reply path with consumer `wiki-research`. Vault writes stay skillwiki, English, no tokens, no Desktop.

## Reboot note (macos-dev)

macos-dev has both LaunchAgent plists `com.karlchow.cursor-box-channel` and `com.karlchow.cursor-box-channel2`. Verified 2026-08-30: only **channel2** is loaded/running. After a Mac reboot, keep one consumer owner. Do not load both. Known leftover, not a new project.

## Issue reports (no tokens)

Include: time HKT; host (`macos-dev` | `Grok Bot` | `cursor-box`); URL (`/mcp` | `/console` | gateway); HTTP status; MCP tool name only; message id / thread id. Never include Bearer, `claim_token`, `key_*`, cookies, or secret-looking bodies.

| What you see | Do |
|---|---|
| `/mcp` 401 | Handshake failure. Check token file mode 600. Do not paste the token. |
| `/console` 302 | Cloudflare Access. Not an MCP failure. |
| `ask` pending | Confirm Grok Bot app open. Check `/console` queue. |
