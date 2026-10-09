# Changelog

All notable changes to this skill are documented in this file.

## [Unreleased]

- Add Windows (Git Bash/MSYS) support to `chrome-debug.sh`: probe the standard Chrome install locations when `CHROME` is unset, convert `CHROME_BIN` to a Windows path so PowerShell `Start-Process` can launch it, detach through `Start-Process`, list and stop profile processes through `Get-CimInstance`/`taskkill`, and skip the `ps -ax` and `ss` probes that Git Bash does not provide.

## [1.4.1] - 2026-09-27

- Document the long-lived chrome-debug Cloudflare human-check failure in `references/chrome-debug.md`. On `owned_by_profile`, run the stale-attach restart sequence once instead of clicking or reloading Turnstile; the user completes any checkbox shown after the restart. On `owned_by_cmux`, stay attach-only.

## [1.4.0] - 2026-09-16

- Rebase the Microsoft Playwright CLI command and reference surface to upstream `v0.1.20`, including recording, WebMCP, idle-timeout, and pull-request attachment guidance.
- Raise the supported `@playwright/cli` minimum to `0.1.20` while preserving the local attach-first, global Chrome profile, chrome-debug, cmux, setup, and browser-worker overlays.
- Document the mixed MIT and Apache-2.0 package licensing and pinned Microsoft source revision.
