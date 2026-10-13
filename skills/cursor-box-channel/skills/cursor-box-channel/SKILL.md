---
name: cursor-box-channel
description: "This skill should be used when an agent needs cursor-box-channel MCP asks or replies, Mac Leaf chat on Chrome :9222, or the read-only audit console."
---

# Cursor Box Channel

Use this skill for attended HTTP Streamable MCP at `https://channel.termolo.com/mcp`.

Marketplace MCP is HTTP only. Do not start a local stdio daemon or grok CLI wrapper. Mac Leaf chat uses the standalone CDP helper below when selected before dispatch.

## First-run

- Plugin client variable: `CURSOR_BOX_MCP_TOKEN` (Cursor: Plugins → Configure). Claude/Grok/Codex need the same bearer in process environment.
- Sidecar env: `MCP_HTTP_TOKEN`; plugin env: `CURSOR_BOX_MCP_TOKEN`. Both use the same bearer.
- Origin Bearer is required on `/mcp`. Installed `.mcp.json` sends `Authorization: Bearer ${CURSOR_BOX_MCP_TOKEN}`. A 401 is a handshake failure or missing token; report it and stop. Grok skips OAuth when that header is present.
- Operator browser vs this-host loopback: headed vs headless is not the discriminator (`DISPLAY`, VNC). `SSH_CONNECTION` / `SSH_TTY` is a hint. If `check_readiness.py` `warnings` contain `headless_oauth_loopback`, export `CURSOR_BOX_MCP_TOKEN` and do not finish a login link on another machine. If `warnings` contain `leftover_stdio_config`, `~/.grok/config.toml` `[mcp_servers.cursor-box-channel]` still has stdio `command=` and shadows marketplace HTTP; Grok `/mcps` `i` auth is HTTP/SSE only. Do not write `config.toml`.
- Resolve the installed root from `GROK_PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT` and run `python3 "$PLUGIN_ROOT/scripts/check_readiness.py" --json` before the first MCP call when those roots exist.
- Never print tokens or write `~/.cursor/mcp.json` or Grok `config.toml`.
- Attended-only: the queue waits if Grok Bot is closed. Do not invent a grok CLI wrapper or force a closed consumer.

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

Two jobs have different owners. **Queue wake** runs peerd/gate-loop on cursor-box after a messageId exists, using `box/routine-helpers/grok-com-bot-cdp.mjs --target <target> --message-id <id>` and messageId-only wake text. **Leaf chat** runs the new sibling `scripts/grok-com-bot-leaf-chat.mjs` on macos-dev, the chrome-debug owner, and sends a full prompt from stdin to newbie.

- **Port map:** Mac Leaf chat attaches `http://127.0.0.1:9222` locally. `http://127.0.0.1:19222` is **box-only**, the reverse tunnel to Mac :9222. Never probe :19222 as the Mac CDP path. Box must not launch Chrome onto or steal Mac :9222.
- **One writer per turn:** Select the route before dispatch. Operator “chat now” selects Leaf chat before any MCP ask. Otherwise try the MCP handshake once: when connected, ask and CLOSE until `final:true`; handshake HTTP 530 / Cloudflare 1033 / disconnected before ask dispatch permits Leaf chat. A 401 or missing token remains a configuration stop unless the operator explicitly selected chat now.
- A messageId or pending receipt commits this prompt to MCP. Hold, lease handoff, slow reply, or later disconnect is never a second CDP writer. **Lost ask response:** a dispatched ask with no response has unknown acceptance, even without a messageId. Reconcile before re-posting or falling back. Chat now does not erase an already-dispatched copy.
- Run readiness first. Its `leaf_chat` field reports local :9222 `OK` independently of MCP credentials; `macos_cdp_port_mismatch` warns about a box-only port expectation. This probes DevTools independently.

Resolve `PLUGIN_ROOT` from `GROK_PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT` (Cursor: installed cursor-box-channel plugin directory). Send prompt text through stdin, never argv:

```bash
node "$PLUGIN_ROOT/scripts/grok-com-bot-leaf-chat.mjs" <<'PROMPT'
Your full prompt for newbie goes here.
PROMPT
```

The helper matches only `https://grok.com/bot/22b3b80c-f7ba-400d-8ad1-6e686cec4d58`, opens it with `PUT /json/new` if missing, and never launches Chrome. If DevTools is down, inspect chrome-debug ownership; only the owner may recover an actually down browser. Stop if not signed in. Generating or composer_busy skips before typing. One real Enter is followed by submit confirmation: a readable empty composer plus a newly observed matching user-message in the same document/tab. `ok` confirms submission, not the answer. Snapshot that same tab for the reply.

`submit_unknown` means timeout, disconnect, navigation, unreadable composer, or missing sent-message proof. `submit_stuck` means the readable draft remains unchanged. Inspect the same tab before deciding on any retry; never auto-resend, refill, press Enter again, or switch writers. `chrome_not_running` means DevTools is down. After an Enter attempt, the helper writes `~/.grok/handoffs/YYYY-MM-DD-leaf-chat-<hash>.md` with timestamp, URL, prompt sha256, and status only; no body or tokens. `ok` with `logStatus: write_failed` still means sent; log failure must not cause a resend. The Mac busy check is not a cross-host lock against peerd.

**Skill origins:** macos Grok loads this marketplace plugin SKILL.md; Cursor uses its plugin copy. Box Grok Bot loads only `/home/box/agent-data/workflows/cursor-box-channel/SKILL.md`, which keeps queue-wake / :19222 instructions. Do not copy this Leaf chat section or the Mac helper into that box workflow. Marketplace injection into Grok Bot Agent chat is unproven. Existing chats do not hot-reload; start a **new macos Grok session** after plugin install/update to load this skill text. Never `Browser.close`, `Target.closeTarget`, or `playwright-cli close`.

## Tools

- `ask`: post a question and wait for a reply (queue waits if Grok Bot is closed).
- `post_message`: fire-and-forget (`to` `channel` | `newbie` | `wiki-research` | `social`).
- `list_replies`: list pending or completed replies.
- `heartbeat`: keep the attended session alive.
- `claim`: claim a queued item for this session.
- `reply`: send a reply to a claimed or asked item.
- `bridge_status`: gateway health.

If MCP is connected, continue with ask and CLOSE. For a pre-dispatch 530/1033/disconnected handshake or explicit chat now, use the Leaf chat route above. Missing token / 401 requires configuration before MCP use.
