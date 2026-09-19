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

- After `ask` returns pending, the coordinator **CLOSE**s until `final:true` **in the same job**. Do not wait for the operator to type poll.
- Hold notes (e.g. "claimed — waiting attended newbie chat") and other `final:false` replies are **not the answer** and not gone.
- MCP `message_status` `wait_seconds` maximum is **15** (server-enforced). Never pass 300; long MCP waits kill the client session. Short checks may use `return_on=final_reply` with `wait_seconds=0` (at most 15).
- For the remaining wait, run `cursor-box-close` from `karlorz/cursor-box-channel` (`docs/reply-closer.md`). Pass only the message id (optional `--thread-id`). `GATEWAY_URL` and `GATEWAY_TOKEN` come from the environment; never argv.
- `cursor-box-close` waits until `final:true` and prints one `DONE` or `FAILED` line. Hold and other non-final replies never count as completion.
- Treat an ask as gone only after a documented miss (handshake/token failure, or target offline AND a later close still has no final).
- `ask.timeout_seconds` is only for exact-token probes, not for waiting on substantive answers.
- Attended-only: substantive answers arrive when the attended Grok Bot routine fires. A `*/10` backup cron also runs.
  - **Primary Peer B wake:** the official Grok Bot **routine webhook** using POST + `Authorization: Bearer <key>`; HTTP **200 means the run started, not finished** (docs: https://cursor.com/help/grok-bot/routines).
  - **Optional extra, default off in peerd/gate-loop:** grok.com Automations **Standard Webhooks HMAC**; HTTP **202 means accepted, not finished** (docs: https://docs.x.ai/grok/automations/webhooks). This is a second outbound event from the same box senders. It does not own the cursor-box computer and cannot start the Bot. Never tell operators to put the Bot Bearer key inside a grok.com automation, and do not invent what the automation does after 202.
  - **Optional grok.com Chat/Bot CDP, default off in peerd/gate-loop:** Attach-first over CDP (`http://127.0.0.1:9222`) to the grok.com Chat/Bot tab for `ask.to` / consumer id (`newbie` vs `wiki-research`). Never broadcast; dual endpoints. If DevTools is down, launch `chrome-debug` on darwin or `PEERD_GROK_COM_BOT_CDP_LAUNCH_CMD` (do not let box Chrome steal the macos-dev `:9222` tunnel). If Chrome is up but the mapped tab is missing, open it with `PUT /json/new`. `newbie` falls back to the known `/bot` URL when TARGETS is unset. Never `Browser.close` / `Target.closeTarget`. Wake text is message ID only (`cursor-box-channel substantive_hold messageId=<id>`). Do not enable live without explicit authorization.
  - Do not use Cursor Cloud Agents API, `@cursor/sdk`, or unofficial grokbot-sdk for this channel.

## Receipts and lease handoff

- `claim_lease_expired` on a pending or held receipt is the 1s pulse lease handoff, not a failed send and not gone. Keep closing until `final:true`. Do not treat the ask as gone because of that field.
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
