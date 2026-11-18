---
name: fleet-board-burn
description: Read Fleet Board burn loop, goals, and WP plan catalog via Zero Trust MCP (no SSH, no Tailscale).
---

# fleet-board-burn

MCP server `fleet-board-burn` talks to `https://orca.termolo.com` with a Cloudflare Access service token.

Token file: `~/.config/fleet-board/agent-read.env` (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, chmod 600).

Tools (empty arguments):

- `plans` — WP-* workbench catalog
- `board_status` — goals, claimable CS-* queue, native_tasks, operator_loop
- `burn_status` — burn-loop summary (slots, scout, freshness)
- `burn_health` — `/healthz`

Do not SSH or use Tailscale for this catalog. HTML `/plans` stays Access-denied for the token.
