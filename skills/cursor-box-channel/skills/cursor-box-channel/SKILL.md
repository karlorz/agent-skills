---
name: cursor-box-channel
description: "This skill should be used when an agent needs cursor-box-channel MCP asks or replies, Mac Leaf chat via Ego Lite or Chrome :9222, or the read-only audit console."
---

# Cursor Box Channel

Use this skill for attended HTTP Streamable MCP at `https://channel.termolo.com/mcp`.

Marketplace MCP is HTTP only. Do not start a local stdio daemon or grok CLI wrapper. Mac Leaf chat uses the standalone helper below when selected before dispatch.

## First-run

- Plugin client variable: `CURSOR_BOX_MCP_TOKEN` (Cursor: Plugins → Configure). Claude/Grok need the same bearer. Codex overlay omits mcpServers; ChatGPT import is skills-available.
- Sidecar env: `MCP_HTTP_TOKEN`; plugin env: `CURSOR_BOX_MCP_TOKEN`. Both use the same bearer.
- Origin Bearer is required on `/mcp`. Installed `.mcp.json` sends `Authorization: Bearer ${CURSOR_BOX_MCP_TOKEN}`. A 401 is a handshake failure or missing token; report it and stop. Grok skips OAuth when that header is present.
- Operator browser vs this-host loopback: headed vs headless is not the discriminator (`DISPLAY`, VNC). `SSH_CONNECTION` / `SSH_TTY` is a hint. If `check_readiness.py` `warnings` contain `headless_oauth_loopback`, export `CURSOR_BOX_MCP_TOKEN` and do not finish a login link on another machine. If `warnings` contain `leftover_stdio_config`, `~/.grok/config.toml` `[mcp_servers.cursor-box-channel]` still has stdio `command=` and shadows marketplace HTTP; Grok `/mcps` `i` auth is HTTP/SSE only. Do not write `config.toml`.
- Resolve the installed root from `GROK_PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT` and run `python3 "$PLUGIN_ROOT/scripts/check_readiness.py" --json` before the first MCP call when those roots exist.
- Never print tokens or write `~/.cursor/mcp.json` or Grok `config.toml`.
- Attended-only: the queue waits if Grok Bot is closed. Do not invent a grok CLI wrapper.

## Audit console (optional wrapper)

- Live URL: `https://channel.termolo.com/console`
- Browser gate is Cloudflare Access on `/console*` only. Do **not** send `CURSOR_BOX_MCP_TOKEN` to `/console`. `/mcp` stays Bearer-only.
- Read-only. HTML fetches `/console` and `/console/api/*` only. Never call `/mcp` from the browser.
- To print the URL with no secrets: `python3 "$PLUGIN_ROOT/scripts/open-console.py"` (falls back to `CLAUDE_PLUGIN_ROOT`).

## Routing

- `ask.to` is `newbie`, `wiki-research`, or `social`. There is no `grok` target.
- `post_message.to` may also be `channel`.
- Live hosted MCP at `https://channel.termolo.com/mcp` may still advertise only `newbie` | `wiki-research` until Coolify HOLD lifts. Do not treat a live `INVALID_TARGET` on `social` as a skill-text bug while HOLD is on.

## Non-block monitoring

- After `ask` returns pending, the coordinator **CLOSE**s until `final:true` **in the same job**. Do not wait for the operator to type poll.
- Hold notes (e.g. "claimed — waiting attended newbie chat") and other `final:false` replies are **not the answer** and not gone.
- MCP `message_status` `wait_seconds` maximum is **15** (server-enforced). Never pass 300; long MCP waits kill the client session. Short checks may use `return_on=final_reply` with `wait_seconds=0` (at most 15).
- For the remaining wait, run `cursor-box-close` from `karlorz/cursor-box-channel` (`docs/reply-closer.md`). Pass only the message id (optional `--thread-id`). `GATEWAY_URL` and `GATEWAY_TOKEN` come from the environment; never argv.
- `cursor-box-close` observes validated gateway events immediately, reconnects with its event sequence, and uses a two-second read-only polling fallback. It waits until `final:true` and prints one `DONE` or `FAILED` line. Hold and other non-final replies never count as completion.
- Handshake failure before dispatch is a route decision. Once an ask is dispatched, reconcile it; target offline or a close without final does not permit a second writer.
- `ask.timeout_seconds` is only for exact-token probes, not for waiting on substantive answers.
- Attended-only: substantive answers arrive when the attended Grok Bot routine fires. The :08, :28, and :48 schedule is the fallback wake, and a `*/10` backup cron also runs.
  - **Default first wake: grok.com Chat/Bot CDP.** Peerd and gate-loop enable CDP when `PEERD_GROK_COM_BOT_CDP_ENABLED` is unset or `1`; set it to `0` to disable. Attach to the tab mapped to `ask.to` / consumer id (`newbie`, `wiki-research`, or `social`) and never broadcast. Live cursor-box uses `http://127.0.0.1:19222`, forwarded to signed-in macos-dev Chrome `:9222`; box ports `9223–9478` are reserved for sandbox browsers. If DevTools is down, launch `chrome-debug` on the owning host; do not let box Chrome steal the Mac tunnel. If Chrome is up but the mapped tab is missing, open it with `PUT /json/new`. `newbie` falls back to the known `/bot` URL when TARGETS is unset; `social` and `wiki-research` need explicit TARGETS rows. Never `Browser.close` / `Target.closeTarget`. The helper sends a real Enter and checks the wake left the composer. Wake text is message ID only (`cursor-box-channel substantive_hold messageId=<id>`). Immediate substantive wakes retry safe pre-Enter failures every two seconds, up to five times. Main/backup share `CBC_WAKE_STATE_DIR`; confirmed/uncertain sends never resend. Reconciliation is read-only. Backup: 10-second ticks, 5-second grace. `PEERD_WAKE_ONLY=1` preserves disabled mechanical workers.
  - **Optional routine webhook:** `PEERD_GROK_ROUTINE_WEBHOOK` must be `1`, `true`, `yes`, or `on` before the stored routine URL is posted. The current Triggers webhook is deprecated; a saved URL and token alone do not send. HTTP **200 means the run started, not finished** (docs: https://cursor.com/help/grok-bot/routines).
  - The grok.com Automations HMAC wake was removed from the running channel. Do not use it as a Bot wake or put the Bot Bearer key in a grok.com automation.
  - Do not use Cursor Cloud Agents API, `@cursor/sdk`, or unofficial grokbot-sdk for this channel.

## Receipts and lease handoff

- `claim_lease_expired` on a pending or held receipt is the 1s pulse lease handoff, not a failed send and not gone. Keep closing until `final:true`. Do not treat the ask as gone because of that field.
- Storage hides `claim_lease_expired` from pending caller receipts unless status is terminal. If a leftover still appears, treat it as handoff too.

## Leaf chat

**Queue wake** runs peerd/gate-loop on cursor-box after a messageId exists, using `box/routine-helpers/grok-com-bot-cdp.mjs --target <target> --message-id <id>` with messageId-only text. **Leaf chat** sends a full prompt from macos-dev stdin to newbie.

- Prefer `scripts/grok-com-bot-leaf-chat-ego.mjs` when `ego-browser` is on PATH, unless `BROWSER_AUTOMATION=playwright-cli`. It opens/reuses the bot in an Ego Lite TaskSpace; keep that Space/tab open. Missing CLI returns `ego_not_running`; never launch Chrome as fallback after an Ego attempt.
- **Port map:** Chrome helper `scripts/grok-com-bot-leaf-chat.mjs` remains local `http://127.0.0.1:9222`. `http://127.0.0.1:19222` is **box-only**, the reverse tunnel to Mac :9222. Peerd stays on chrome-debug CDP. Box must not launch Chrome onto Mac :9222.
- **One writer per turn:** Operator “chat now” selects Leaf chat before any MCP ask. Otherwise handshake once: connected means ask and CLOSE until `final:true`; HTTP 530 / Cloudflare 1033 / disconnected before dispatch permits Leaf chat. A 401/missing token is a configuration stop unless chat now was explicitly selected.
- A messageId/pending receipt commits this prompt to MCP. Hold, lease handoff, slow reply or later disconnect never permits another writer. **Lost ask response:** acceptance is unknown even without a messageId; reconcile before reposting or falling back. Chat now cannot erase a dispatched copy.
- Readiness `leaf_chat` probes Chrome :9222 independently of MCP credentials, not Ego availability; `macos_cdp_port_mismatch` warns about box-only port expectations.

Resolve `PLUGIN_ROOT` from `GROK_PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT` (Cursor: installed plugin directory). Select before dispatch; prompt is stdin, never argv:

```bash
helper=grok-com-bot-leaf-chat.mjs
if command -v ego-browser >/dev/null 2>&1 && [ "${BROWSER_AUTOMATION:-}" != playwright-cli ]; then
  helper=grok-com-bot-leaf-chat-ego.mjs
fi
node "$PLUGIN_ROOT/scripts/$helper" <<'PROMPT'
Your full prompt for newbie goes here.
PROMPT
```

Both helpers match only `https://grok.com/bot/22b3b80c-f7ba-400d-8ad1-6e686cec4d58`. Chrome opens missing tabs with `PUT /json/new`, never launches Chrome; only its owner recovers DevTools. Stop if signed out, generating or composer_busy. One real Enter needs an empty readable composer plus a new matching user-message in the same document/tab. `ok` confirms submission, not the answer; inspect that same tab for the reply.

`submit_unknown` covers timeout/disconnect/navigation or missing proof; `submit_stuck` means the draft remains unchanged. Inspect the same tab; never auto-resend, refill, press Enter again or switch writers. `chrome_not_running` means DevTools is down. After Enter (or uncertain CLI completion), receipts at `~/.grok/handoffs/YYYY-MM-DD-leaf-chat-<sha256>.md` contain timestamp, URL, prompt sha256 and status only; no body/tokens. `logStatus: write_failed` never permits resend, including with `ok`. Busy checks are not cross-host locks against peerd.

**Skill origins:** Mac/Cursor loads marketplace text. Box Grok Bot loads only `/home/box/agent-data/workflows/cursor-box-channel/SKILL.md`; keep it queue-wake/:19222 only. Do not copy Leaf chat or either Mac helper, including the Ego helper, there. Marketplace injection into Grok Bot Agent chat is unproven. Existing chats do not hot-reload; start a **new macos Grok session** after update. Never `page.close`, `closeTaskSpace`, `Browser.close`, `Target.closeTarget` or `playwright-cli close`.

## Tools

- `ask`: post a question and wait for a reply (queue waits if Grok Bot is closed).
- `post_message`: fire-and-forget (`to` `channel` | `newbie` | `wiki-research` | `social`).
- `list_replies`: list pending or completed replies.
- `heartbeat`: keep the attended session alive.
- `claim`: claim a queued item for this session.
- `reply`: send a reply to a claimed or asked item.
- `bridge_status`: gateway health.

If MCP is connected, continue with ask and CLOSE. For a pre-dispatch 530/1033/disconnected handshake or explicit chat now, use the Leaf chat route above. Missing token / 401 requires configuration before MCP use.
