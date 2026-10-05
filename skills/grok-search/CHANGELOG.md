# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.22] - 2026-10-06

### Changed
- README is agent-facing install and usage only: Skill+CLI one-sentence plus recipe, CLI commands, marketplace one-liners, production URL. Removed Tailscale IPs, Cloudflare Access preview, host nicknames, SessionStart, grok2api, and other deploy notes. Operator connector details stay in `SKILL.md`.

## [0.1.21] - 2026-10-05

### Fixed
- `auth-status` persists the bearer when hosted `/auth/cli/check` returns JSON `status: "success"` (the coordinator's first claim). v0.1.20 treated `success` as unknown, deleted `cli-auth.json`, and failed the session.
- `claiming` stays pending so a concurrent claim can be retried. `consumed` reports authenticated only when `http-mcp.token` already exists. Unknown check statuses fail without deleting the pending session.

## [0.1.20] - 2026-10-05

### Added
- Standalone Skill+CLI unit under `skills/grok-search/skills/grok-search/` with bundled `scripts/grok-search.cjs` and offline QR generator `scripts/lib/toqr.cjs`.
- Outer convenience script wrapper `skills/grok-search/scripts/grok-search.cjs`.
- Reference contracts: `references/cli-contract.md`, `references/auth-contract.md`, and `references/install.md`.
- Dual-mode support in `SKILL.md`: connector mode when MCP tools are connected; local planning and standalone CLI execution when no host connector is registered.
- Hosted approve+poll CLI authentication commands `auth-start` and `auth-status`.

## [0.1.19] - 2026-09-28

### Changed
- Restored 0.1.13 env-backed Authorization on installed desktop plugin JSON: `.mcp.json` and Cursor `mcp.json` send `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`; Codex `bearer_token_env_var` is `GROK_SEARCH_MCP_TOKEN`. Grok skips OAuth discovery when that header is present, so SSH/operator-browser loopback no longer blocks Grok TUI.
- Missing `GROK_SEARCH_MCP_TOKEN` leaves the header key in place; Grok then 401s instead of sitting at `[authenticating]`.
- Claude `userConfig` and Cursor plugin `variables` stay removed. ChatGPT Admin Apps and Doubao Work keep HTTPS OAuth with no custom headers. Gateway authorize 302 is unchanged.
- `leftover_stdio_config` still warns when `~/.grok/config.toml` `[mcp_servers.grok-search]` has `command=`. The probe never writes `config.toml`.

## [0.1.18] - 2026-09-28

### Changed
- MCP OAuth loopback is same-host. The discriminator is whether the operator browser is on the host running the MCP client; headed vs headless (`DISPLAY`, VNC, local Chrome) is not. `SSH_CONNECTION` / `SSH_TTY` stays a hint.
- `check_readiness.py` `headless_oauth_loopback` copy now says SSH is a hint that the operator browser may not be this host, and names the Grok HTTP bearer overlay. The probe still never writes `config.toml`.
- SKILL and README document the Grok overlay as user `~/.grok/config.toml` `[mcp_servers.grok-search]` `url = "https://search.karldigi.dev/mcp"` plus `[mcp_servers.grok-search.headers]` `Authorization = "Bearer ${GROK_SEARCH_MCP_TOKEN}"`; Grok skips OAuth when that header is set. Leftover stdio `command=` still shadows it. `cursor-cli-mcp.example.json` stays the Cursor CLI overlay. Installed `.mcp.json` stays OAuth with no Authorization header.

## [0.1.17] - 2026-09-28

### Added
- `check_readiness.py` warns `leftover_stdio_config` when `~/.grok/config.toml` `[mcp_servers.grok-search]` still has a stdio `command`. A Grok marketplace HTTP plugin upgrade does not remove that table, so `/mcps` `i` auth fails with `does not use OAuth`. The probe never writes `config.toml`.

## [0.1.16] - 2026-09-28

### Added
- SSH / headless Linux guidance: MCP OAuth loopback stays on the SSH host; overlay `GROK_SEARCH_MCP_TOKEN` with `cursor-cli-mcp.example.json` instead of completing the grok-search OAuth login in a laptop browser.
- `check_readiness.py` emits `headless_oauth_loopback` when `SSH_CONNECTION` or `SSH_TTY` is set. Status stays `in_sync`. Process env token does not suppress the warning.

### Changed
- Installed desktop plugin remains MCP OAuth (same-host browser). Gateway authorize 302 is unchanged.

## [0.1.15] - 2026-09-24

### Changed
- Document that a ChatGPT web chat and a Doubao Work chat cannot finish first-time connector setup. A person completes Admin Apps or Doubao 去授權 before the chat calls `web_search`.

## [0.1.14] - 2026-09-24

### Changed
- Converted grok-search installed plugin to HTTP MCP OAuth at `https://search.karldigi.dev/mcp`. Removed bearer token requirement from installed `.mcp.json` and `mcp.json`.
- Removed Claude `userConfig` token prompt and Cursor plugin token `variables`.
- Removed `bearer_token_env_var` from Codex-native plugin manifest; Codex connects via production HTTP MCP OAuth.
- Updated `check_readiness.py` probe so missing token is `in_sync` and empty URL migrates to `https://search.karldigi.dev/mcp`.
- Documented ChatGPT web integration via Admin Apps (`https://chatgpt.com/admin/apps` Create App) instead of GitHub card.
- Retained `cursor-cli-mcp.example.json` as an optional headless wrapper using `Bearer ${env:GROK_SEARCH_MCP_TOKEN}`.

### Removed
- Removed `skills/grok-search-web/` package and its entries from Claude and Agents plugin marketplaces in favor of unified `grok-search`.

## [0.1.13] - 2026-09-15

### Added
- Claude `.claude-plugin` `userConfig` for `GROK_SEARCH_MCP_TOKEN` (`required` + `sensitive`). In-app `/plugin install` prompts; CLI `claude plugin install` does not. `.mcp.json` keeps `Bearer ${GROK_SEARCH_MCP_TOKEN}` so Grok still uses process environment.

### Changed
- Document Cursor Agent TUI `/plugin` Configure as pull-not-push: fill the token, Confirm, then a new Agent chat. `required` does not auto-interrupt.
- Document kr01 `https://search.karldigi.dev/mcp` as proven production. Mark Tailscale `100.76.134.104:8800` and sg01 `100.118.12.90:8800` as stale previews; do not start a grok-search listener on sg01.
- `check_readiness.py` warns when `GROK_SEARCH_MCP_URL` still points at those stale preview URLs. Status stays `in_sync`; no live `:8800` probe.

## [0.1.12] - 2026-09-10

### Changed
- Skill: treat MCP `web_search` `content == ""` or `upstream_error:` / `upstream_empty:` as a failed search (retry once, then `web_fetch`). New API token counts are not proof of usable MCP content.

## [0.1.11] - 2026-08-29

### Changed
- Document the production `get_config_info` contract: it identifies the configured remote streamable-HTTP endpoint and local-client dependency boundary without exposing loopback routes, filesystem paths, credential fields or fragments, upstream response bodies, or low-level exception details.

## [0.1.10] - 2026-08-29

- Shorten SKILL.md descriptions to the Codex catalog budget (180-character target, CI fail above 220).

## [0.1.9] - 2026-08-29

### Fixed
- Add a native Codex plugin manifest with an inline Codex-native HTTP MCP definition and an absolute production URL, preventing Codex from treating Bash `${VAR:-default}` syntax as a relative URL.
- Keep bearer authentication environment-backed through Codex-native `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN` while preserving the existing Claude/Grok Authorization placeholder and endpoint override.

### Changed
- Codex and Cursor marketplace installs pin production. Claude/Grok retain `GROK_SEARCH_MCP_URL` as an optional endpoint override.

## [0.1.8] - 2026-08-25

### Changed
- Default the Claude/Grok HTTP MCP URL to `https://search.karldigi.dev/mcp` while preserving `GROK_SEARCH_MCP_URL` as an explicit override, avoiding a literal relative URL when the variable is unset.
- Document that Grok requires an operator-provided gateway-keys bearer in process environment; SessionStart cannot inject the parent MCP environment and `mcp.env` is not auto-sourced.
- Add a Cursor-native `.cursor-plugin` package with a required token variable and production `grok-search` HTTP MCP server; leftover `grok-search-http` is not a fallback.

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
