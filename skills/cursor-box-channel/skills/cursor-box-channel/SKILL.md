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

## Non-block monitoring

- A `final:false` reply whose body is a hold note (e.g. "claimed — waiting attended newbie chat") is **not the answer** and not gone. Treat the ask as pending.
- After `ask` returns pending, poll with `message_status` using `return_on=final_reply` and `wait_seconds=0`.
- `wait_seconds` maximum is **15** (server-enforced). Never pass 300; long MCP waits kill the client session.
- If not final, **end the turn**: return the `messageId` and let the next turn (or a fresh caller) poll `message_status` (`return_on=final_reply`, `wait_seconds=0`) until `final:true`. Do not loop-wait inside one turn.
- Treat an ask as gone only after a documented miss (handshake/token failure, or target offline AND a later poll still has no final).
- `ask.timeout_seconds` is only for exact-token probes, not for waiting on substantive answers.
- Attended-only: substantive answers arrive when the attended Grok Bot routine fires. Peer B wake is the official Grok Bot **routine webhook**: POST + `Authorization: Bearer <key>`; HTTP **200 means the run started, not finished** (docs: https://cursor.com/help/grok-bot/routines). A `*/10` backup cron also runs. Do not use Cursor Cloud Agents API, `@cursor/sdk`, grok.com automations HMAC, or unofficial grokbot-sdk for this channel.

## Receipts and lease handoff

- `claim_lease_expired` on a pending or held receipt is the 1s pulse lease handoff, not a failed send. Keep polling. Do not treat the ask as gone because of that field.
- Storage hides `claim_lease_expired` from pending caller receipts unless status is terminal. If a leftover still appears, treat it as handoff too.

## Tools

- `ask`: post a question and wait for a reply (queue waits if Grok Bot is closed).
- `post_message`: fire-and-forget (`to` `channel` | `newbie` | `wiki-research`).
- `list_replies`: list pending or completed replies.
- `heartbeat`: keep the attended session alive.
- `claim`: claim a queued item for this session.
- `reply`: send a reply to a claimed or asked item.
- `bridge_status`: gateway health.

If tools are connected, continue. If the token is missing or MCP is disconnected, stop and ask the operator to set `CURSOR_BOX_MCP_TOKEN`.
