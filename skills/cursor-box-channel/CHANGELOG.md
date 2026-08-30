# Changelog

All notable changes to this plugin will be documented in this file.

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
