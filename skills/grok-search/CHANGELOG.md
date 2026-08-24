# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.5] - 2026-08-24

### Changed
- Converted grok-search to a Context7-style HTTP-only MCP plugin using `GROK_SEARCH_MCP_URL` and `GROK_SEARCH_MCP_TOKEN`.
- Updated `.mcp.json` and `cursor-cli-mcp.example.json` to HTTP transport.
- Updated skill and README to document HTTP endpoints and first-run setup.

### Removed
- Removed stdio launcher (`run-grok-search.sh`) and user MCP migration tool (`migrate-from-user-mcp.py`).
- Archived stdio artifacts and configs under `archive/skills/grok-search-stdio/`.
