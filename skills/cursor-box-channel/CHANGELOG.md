# Changelog

All notable changes to this plugin will be documented in this file.

## [0.3.2] - 2026-09-04

### Added
- Non-block monitor guidance in SKILL.md: hold is not the answer, poll `message_status` with `wait_seconds=0`, server-enforced `wait_seconds` max 15, and end turn if not final.

## [0.3.1] - 2026-08-30

### Added
- Thin SKILL wrap: `ask.to` routing enum (`newbie` | `wiki-research` only), `post_message` / `bridge_status` tool names, `post_message.to` may be `channel`.

## [0.3.0] - 2026-08-30

### Added
- Optional read-only audit wrapper around `https://channel.termolo.com/console` (Cloudflare Access). Not a second dashboard.
- Tiny `scripts/open-console.py` that prints the console URL and never reads tokens.

### Changed
- Skill documents `/console` vs `/mcp` path split. Leftover `cbc-admin` CLI is pointed at this console.

## [0.2.0] - 2026-08-30

### Changed
- Marketplace install is HTTP Streamable MCP at `https://channel.termolo.com/mcp` using the `CURSOR_BOX_MCP_TOKEN` bearer placeholder.
- Claude/Grok keep an optional `CURSOR_BOX_MCP_URL` override; Cursor-native and Codex pin production.
- Stop using the stdio `scripts/run-cursor-box-mcp.sh` runner as the default MCP.

### Added
- Compact Cursor and Codex plugin manifests (`.cursor-plugin/plugin.json`, `mcp.json`, `.codex-plugin/plugin.json`).
- KEEP re-pin list now includes `cursor-box-channel` next to `grok-search` and `deep-research`.

## [0.1.0] - 2026-08-24

- Initial release of cursor-box-channel marketplace plugin.
- Stdio MCP bridge runner connecting to local macOS daemon (`cursor-box-mcp`).
- Companion skill for targeted agent-to-agent messaging and channel updates.
