# cursor-box-channel

Thin marketplace plugin for cursor-box-channel. Marketplace install is HTTP Streamable MCP at `https://channel.termolo.com/mcp` with a required origin Bearer.

Optional read-only audit UI: `https://channel.termolo.com/console` (Cloudflare Access). This plugin is a wrapper around that live URL, not a second dashboard.

SKILL.md is a thin wrap (routing enum + tool names). Runbook, issue guide, and LaunchAgent leftover stay in the wiki.

The tracked `skills/cursor-box-channel/SKILL.md` is the Mac/Cursor source for Queue wake and Leaf chat guidance. Leaf chat runs `scripts/grok-com-bot-leaf-chat.mjs` with prompt stdin on local Mac :9222 and confirms one submission without closing Chrome. Box :19222 is the reverse tunnel for messageId-only peerd Queue wake. Grok Bot Agent chats on cursor-box load only `/home/box/agent-data/workflows/cursor-box-channel/SKILL.md`; keep that workflow queue-wake only and never copy the Leaf chat section there. A plugin cache manifest alone does not prove marketplace skill injection into Grok Bot. Existing chats do not hot-reload; a new macos Grok session loads the installed Leaf chat text.

## Install

From `karlorz-agent-skills`:

```bash
claude plugin install cursor-box-channel@karlorz-agent-skills
```

Cursor: install the plugin, then **Plugins → Configure** and enter `CURSOR_BOX_MCP_TOKEN`. Codex: `codex plugin add cursor-box-channel@karlorz-agent-skills` and set the same bearer.

## Token (MCP only)

- Plugin client variable (pinned): `CURSOR_BOX_MCP_TOKEN`
- Sidecar server env: `MCP_HTTP_TOKEN`
- Operator sets the same secret in both places. Cursor/Codex docs may mention `${MCP_HTTP_TOKEN}` as an alias; the plugin variable name stays `CURSOR_BOX_MCP_TOKEN`.
- Never print a real token.
- The browser console does **not** use this bearer. Cloudflare Access on `/console*` is the gate. `/mcp` stays Bearer-only.

Claude/Grok default URL is `https://channel.termolo.com/mcp` (`CURSOR_BOX_MCP_URL` override). Cursor-native and Codex pin that URL.

## Audit console

Open `https://channel.termolo.com/console` after Access. Read-only: queue depth, replies, per-id message lookup. No claim, retry, dead-letter, or send. HTML never calls `/mcp`.

To print the URL (no tokens):

```bash
python3 "$PLUGIN_ROOT/scripts/open-console.py"
```

Leftover `cbc-admin` CLI in `karlorz/cursor-box-channel` is legacy; use this console for read-only audit. Do not ship a second dashboard or `httpd.py`.

## Attended-only

The queue waits if Grok Bot is closed. There is no grok CLI wrapper. Origin Bearer is required for `/mcp`.

The Mac launchd+stdio daemon still exists in `karlorz/cursor-box-channel`. Marketplace install does not use that stdio runner.

Plugin install does not write `~/.cursor/mcp.json`. `agent mcp list` inspects static `~/.cursor/mcp.json`, not plugin MCP. For headless `agent -p` without plugin flags, see `cursor-cli-mcp.example.json`.

Installed `.mcp.json` sends `Authorization: Bearer ${CURSOR_BOX_MCP_TOKEN}`. Grok skips OAuth when that header is present; a missing token is a 401. Headed vs headless is not the discriminator: `DISPLAY` / VNC on the SSH host is not the operator browser. `SSH_CONNECTION` / `SSH_TTY` is a hint. `scripts/check_readiness.py` warns `headless_oauth_loopback` when SSH is set and the token is unset. Leftover `[mcp_servers.cursor-box-channel]` `command=` in `~/.grok/config.toml` still shadows marketplace HTTP (`leftover_stdio_config`). The probe never writes `config.toml`.

## License

MIT
