# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.7] - 2026-08-25

### Added
- `scripts/check_readiness.py` probe (`in_sync` / `missing_prereq`) and SessionStart hook that apply `GROK_SEARCH_MCP_URL=https://search.karldigi.dev/mcp` in-process when the token is set and the URL is empty. Does not write user MCP config files.
- Orca new-session probe script `scripts/test-grok-search-orca-new-session.sh` (`--dry-run` in CI; `--live-probe` after release).

## [0.1.6] - 2026-08-25

### Changed
- Recommended production URL is now `https://search.karldigi.dev/mcp` using gateway-keys token auth.
- Relabeled Tailscale (`http://100.76.134.104:8800/mcp`) and Cloudflare Access (`https://search.termolo.com/mcp`) endpoints as preview / fallback.
- Added operator troubleshooting note regarding upstream grok2api empty `content` responses with `grok-4.3-fast`.

## [0.1.5] - 2026-08-24

### Changed
- Converted grok-search to a Context7-style HTTP-only MCP plugin using `GROK_SEARCH_MCP_URL` and `GROK_SEARCH_MCP_TOKEN`.
- Updated `.mcp.json` and `cursor-cli-mcp.example.json` to HTTP transport.
- Updated skill and README to document HTTP endpoints and first-run setup.

### Removed
- Removed stdio launcher (`run-grok-search.sh`) and user MCP migration tool (`migrate-from-user-mcp.py`).
- Archived stdio artifacts and configs under `archive/skills/grok-search-stdio/`.
