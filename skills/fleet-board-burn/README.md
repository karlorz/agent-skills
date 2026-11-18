# fleet-board-burn Grok plugin

Install:

```
grok plugin install fleet-board-burn@karlorz-agent-skills --trust
codex plugin add fleet-board-burn@karlorz-agent-skills
```

MCP command is plugin-relative: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/fleet-board-burn-mcp`.

- **macOS:** exec `$HOME/.local/bin/fleet-board-burn-mcp`. If `FLEET_BOARD_AGENT_TOKEN_FILE` is unset, use `$HOME/.config/fleet-board/agent-read.env` (chmod 600) and fail closed when that file is missing. Explicit `FLEET_BOARD_AGENT_TOKEN_FILE` / `FLEET_BOARD_BURN_MCP_BIN` win; a leading `~/` is expanded and the absolute path is exported.
- **Linux/BOX:** `python3 /workspace/code/fleet-board/tools/agent-read/burn_read.py mcp`. With an empty token file, default `FLEET_BOARD_AGENT_URL=http://127.0.0.1:18099` (keep an already-safe loopback URL). Explicit token/Access is preserved and not forced to loopback.
- **Overrides:** `FLEET_BOARD_BURN_MCP_BIN`, `FLEET_BOARD_AGENT_READ`, `FLEET_BOARD_PYTHON`, `FLEET_BOARD_BOX_PY`, `FLEET_BOARD_AGENT_TOKEN_FILE`, `FLEET_BOARD_AGENT_URL`.
- Fail closed if the backend is missing, the expected Mac token is missing, the URL has userinfo, or a non-loopback URL is used with an empty token. The launcher never writes files and never prints URL userinfo.

Access destinations: `/burn-loop.json`, `/healthz`, `/board-status.json`, `/plans.json`.
