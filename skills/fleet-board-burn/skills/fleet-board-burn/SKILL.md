---
name: fleet-board-burn
description: Read Fleet Board burn loop, goals, and WP plan catalog via Zero Trust MCP (no SSH, no Tailscale).
---

# fleet-board-burn

MCP server `fleet-board-burn` is launched via plugin-relative
`${CLAUDE_PLUGIN_ROOT}/scripts/fleet-board-burn-mcp` (read-only).

- macOS: existing Access launcher `$HOME/.local/bin/fleet-board-burn-mcp`.
  Default token `$HOME/.config/fleet-board/agent-read.env` when env is unset
  (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, chmod 600); missing file
  fails closed. Explicit `FLEET_BOARD_AGENT_TOKEN_FILE` wins (`~/` expanded).
- Linux/BOX: `python3 …/tools/agent-read/burn_read.py mcp` with empty token
  and `FLEET_BOARD_AGENT_URL=http://127.0.0.1:18099` (keep a safe loopback).
  Explicit token/Access is preserved. Userinfo or non-loopback URL without a
  token fails closed.

Tools (empty arguments):

- `plans` — WP-* workbench catalog
- `board_status` — goals, claimable CS-* queue, native_tasks, operator_loop
- `burn_status` — burn-loop summary (slots, scout, freshness)
- `burn_health` — `/healthz`

Do not SSH or use Tailscale for this catalog. HTML `/plans` stays Access-denied for the token.
