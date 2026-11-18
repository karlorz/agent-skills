# Changelog

## 0.1.3

- Replace hardcoded Mac MCP paths with a plugin-relative bash launcher.
- Darwin execs `$HOME/.local/bin/fleet-board-burn-mcp` with default
  `$HOME/.config/fleet-board/agent-read.env` when the token env is unset.
- Linux uses BOX `burn_read.py mcp` with loopback
  `FLEET_BOARD_AGENT_URL=http://127.0.0.1:18099` and an empty token file.
- Fail closed when the backend is missing, the Mac token is missing, or a
  remote/userinfo URL has no token file.
- Keep `.mcp.json` and `mcp.json` byte-identical.

## 0.1.2

- Add compact `.codex-plugin` overlay for CodexHost / `codex plugin add`.
- Add `.cursor-plugin` overlay with `mcpServers` → `./mcp.json`.

## 0.1.1

- Ship `.mcp.json` so Grok loads the MCP server (same as grok-search).

## 0.1.0

- Initial marketplace plugin: Access MCP for burn_status, burn_health, board_status, plans.
