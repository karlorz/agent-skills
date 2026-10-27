# Changelog

All notable changes to this skill are documented in this file.

## [1.4.3] - 2026-10-27

- Route generic website automation to `/ego-browser` when `ego-browser` is on PATH. This skill stays the chrome-debug CDP `:9222` path (grokbot/channel, Cloudflare, live-profile attach). `BROWSER_AUTOMATION=playwright-cli` forces this skill for generic web tasks.

## [1.4.2] - 2026-10-13

- chrome-debug-contract v6: skip `playwright-cli attach` on `owned_by_cmux` after healthy `/json/version`. Recover with bundled `cdp-session.py` via `chrome-debug --cdp-list` / `--cdp-eval` / `--cdp-screenshot`. Optional `--try-cli-attach` is a bounded attach probe only. Do not pin `@playwright/cli` below 0.1.20. `--cdp-screenshot` calls `Target.activateTarget` before `Page.captureScreenshot` so a background tab does not eat the 8s deadline.

## [1.4.1] - 2026-09-27

- Document the long-lived chrome-debug Cloudflare human-check failure in `references/chrome-debug.md`. On `owned_by_profile`, run the stale-attach restart sequence once instead of clicking or reloading Turnstile; the user completes any checkbox shown after the restart. On `owned_by_cmux`, stay attach-only.

## [1.4.0] - 2026-09-16

- Rebase the Microsoft Playwright CLI command and reference surface to upstream `v0.1.20`, including recording, WebMCP, idle-timeout, and pull-request attachment guidance.
- Raise the supported `@playwright/cli` minimum to `0.1.20` while preserving the local attach-first, global Chrome profile, chrome-debug, cmux, setup, and browser-worker overlays.
- Document the mixed MIT and Apache-2.0 package licensing and pinned Microsoft source revision.
