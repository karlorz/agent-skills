# Changelog

## [0.1.1] - 2026-09-24

### Fixed
- Reference the Grok Search OAuth app published to the xaicom workspace so ChatGPT web can start the connect flow.

## [0.1.0] - 2026-09-24

### Added
- ChatGPT web package that references the existing OAuth app and does not ship `mcp.json` or `.mcp.json`.
- The desktop `grok-search` package is unchanged and still uses `GROK_SEARCH_MCP_TOKEN`.
