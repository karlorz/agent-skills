---
name: playwright-cli
description: >
  Use this skill when the user asks to open a browser, browse a website,
  scrape a page, automate Chrome, take a screenshot, fill out a form,
  click a button, or otherwise interact with a website. Includes a
  browser-worker agent (model: sonnet) for mechanical Chrome lifecycle and
  interaction tasks.
allowed-tools: Bash(playwright-cli:*) Bash(npx:*) Bash(npm:*) Bash(bash\ scripts/chrome-debug.sh:*)
---

# Browser Automation with playwright-cli

## Model Strategy

Browser automation tasks are tiered by complexity. Simple single-script operations (Chrome launch) use `model: "haiku"`. Multi-step interaction sequences (navigate, snapshot, interpret element refs) use `model: "sonnet"`. The orchestrator handles navigation intent, anti-pattern detection, and result interpretation — keeping the parent session focused on decision-making while the worker handles command sequences.

## Phase 0: Launch Chrome (ALWAYS FIRST)

For single-script launch tasks, delegate to browser-worker with `model: "haiku"`:
```
Agent(description: "Launch Chrome", model: "haiku", prompt: "Launch Chrome with CDP on port 9222. Run scripts/chrome-debug.sh --restart, then playwright-cli attach.")
```

For multi-step browser interactions (navigation, snapshot, element manipulation), use `model: "sonnet"`:
```
Agent(description: "Navigate and snapshot", model: "sonnet", prompt: "Go to <url>, wait for load, take a snapshot. Report element refs.")
Agent(description: "Screenshot page", model: "sonnet", prompt: "Take a full-page screenshot. Save as <filename>.")
```

Alternatively, run directly:

The project config (`.playwright/cli.config.json`) sets `cdpEndpoint: http://localhost:9222`. This means `playwright-cli open` will attempt to connect to port 9222 first and fail if Chrome is not already running there. That is why Chrome must be launched before any playwright-cli command.

Do not attempt `playwright-cli open` or `playwright-cli attach` until Phase 0 completes.

**Preferred — fresh restart (kills stale sessions too):**
```bash
bash scripts/chrome-debug.sh --restart
```

**Or step by step:**
```bash
# Check if Chrome is already running on port 9222
bash scripts/chrome-debug.sh --check-port

# If port is free, launch Chrome with remote debugging
bash scripts/chrome-debug.sh

# If port is occupied but attach fails (stale session), restart cleanly:
playwright-cli kill-all
bash scripts/chrome-debug.sh --restart

# If you need a clean profile (no cookies from personal Chrome)
bash scripts/chrome-debug.sh --repo-local-profile
```

When the script prints `[OK] Chrome is listening on port 9222`, advance to Phase 1.

### Known issue: Stale attach session

If `playwright-cli attach` times out after 30s even though Chrome is healthy on port 9222, a stale playwright-cli daemon is holding a dead session. Fix:
```bash
playwright-cli kill-all
bash scripts/chrome-debug.sh --restart
playwright-cli attach
```
The `--restart` flag kills the Chrome debugger process and stale daemon sessions together, ensuring a clean start.

## Phase 1: Attach and interact

Run directly (Chrome should already be running from Phase 0):

```bash
# Attach to the Chrome instance launched in Phase 0
playwright-cli attach

# Navigate
playwright-cli goto https://example.com

# See what's on the page (returns element refs like e3, e5, etc.)
playwright-cli snapshot

# Interact using refs from the snapshot
playwright-cli click e3
playwright-cli fill e5 "user@example.com" --submit
playwright-cli type "search query"
playwright-cli press Enter
```

When done, Chrome stays running — the user can re-attach anytime with `playwright-cli attach`. Only run `playwright-cli close` to shut Chrome down.

## Anti-patterns to prevent

- **Running `playwright-cli open` without launching Chrome first.** The config has `cdpEndpoint` set, so `open` tries to connect to 9222 and gets ECONNREFUSED. Always run `bash scripts/chrome-debug.sh` first.
- **Using `make chrome-debug`.** There is no Makefile. Run `bash scripts/chrome-debug.sh` directly.
- **Skipping `playwright-cli attach`.** After launching Chrome, `attach` is the command that connects playwright-cli to it. Without attach, no interaction commands will work.
- **Forgetting to snapshot before interacting.** Element refs (e3, e5, etc.) come from the snapshot. Always snapshot first, then use the refs.

## Command reference

### Core

| Command | What it does |
|---------|-------------|
| `playwright-cli attach` | Connect to Chrome on port 9222 |
| `playwright-cli goto <url>` | Navigate to URL |
| `playwright-cli snapshot` | Get page snapshot with element refs |
| `playwright-cli click <ref>` | Click an element |
| `playwright-cli fill <ref> "text" --submit` | Fill input and press Enter |
| `playwright-cli type "text"` | Type text into focused element |
| `playwright-cli press Enter` | Press a key |
| `playwright-cli dblclick <ref>` | Double-click |
| `playwright-cli hover <ref>` | Hover over element |
| `playwright-cli select <ref> "value"` | Select dropdown option |
| `playwright-cli upload <file>` | Upload a file |
| `playwright-cli check <ref>` | Check a checkbox |
| `playwright-cli uncheck <ref>` | Uncheck a checkbox |
| `playwright-cli eval "document.title"` | Run JS in page context |
| `playwright-cli eval "el => el.id" <ref>` | Run JS on an element |
| `playwright-cli close` | Close the browser |
| `playwright-cli dialog-accept` | Accept a dialog |
| `playwright-cli dialog-dismiss` | Dismiss a dialog |
| `playwright-cli resize 1920 1080` | Resize window |

### Navigation / Keyboard / Mouse

```bash
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
playwright-cli press ArrowDown
playwright-cli keydown Shift
playwright-cli keyup Shift
playwright-cli mousemove 150 300
playwright-cli mousedown
playwright-cli mouseup
playwright-cli mousewheel 0 100
```

### Tabs

```bash
playwright-cli tab-list
playwright-cli tab-new
playwright-cli tab-new https://example.com/page
playwright-cli tab-close
playwright-cli tab-select 0
```

### Save as

```bash
playwright-cli screenshot
playwright-cli screenshot e5
playwright-cli screenshot --filename=page.png
playwright-cli pdf --filename=page.pdf
```

### Storage

```bash
playwright-cli state-save auth.json
playwright-cli state-load auth.json
playwright-cli cookie-list
playwright-cli cookie-set session_id abc123
playwright-cli cookie-delete session_id
playwright-cli localstorage-set theme dark
playwright-cli localstorage-get theme
```

### Network / DevTools

```bash
playwright-cli route "**/*.jpg" --status=404
playwright-cli route "https://api.example.com/**" --body='{"mock": true}'
playwright-cli console
playwright-cli requests
playwright-cli run-code "async page => await page.context().grantPermissions(['geolocation'])"
playwright-cli tracing-start
playwright-cli tracing-stop
playwright-cli video-start video.webm
playwright-cli video-stop
```

### Raw output

The `--raw` flag strips status output, returning only the result value (useful for piping):

```bash
playwright-cli --raw eval "document.title"
playwright-cli --raw cookie-get session_id
playwright-cli --raw snapshot > page.yml
```

### Browser sessions

```bash
playwright-cli list                    # list sessions
playwright-cli close-all               # close all browsers
playwright-cli kill-all                # force-kill all browser processes
playwright-cli -s=mysession open example.com --persistent  # named session
```

## Targeting elements

Use refs from the snapshot (`e3`, `e5`, etc.) or CSS selectors / Playwright locators:

```bash
playwright-cli click e15                       # by ref
playwright-cli click "#main > button.submit"   # by CSS
playwright-cli click "getByRole('button', { name: 'Submit' })"  # by role
playwright-cli click "getByTestId('submit-button')"  # by test id
```

## Installation

```bash
# Check if installed
npx --no-install playwright-cli --version

# Install globally if needed
npm install -g @playwright/cli@latest
```

## Reference files

- **Chrome debug launcher** — [references/chrome-debug.md](references/chrome-debug.md) (profile modes, env vars, troubleshooting)
- **Playwright tests** — [references/playwright-tests.md](references/playwright-tests.md)
- **Request mocking** — [references/request-mocking.md](references/request-mocking.md)
- **Running Playwright code** — [references/running-code.md](references/running-code.md)
- **Session management** — [references/session-management.md](references/session-management.md)
- **Spec-driven testing** — [references/spec-driven-testing.md](references/spec-driven-testing.md)
- **Storage state** — [references/storage-state.md](references/storage-state.md)
- **Test generation** — [references/test-generation.md](references/test-generation.md)
- **Tracing** — [references/tracing.md](references/tracing.md)
- **Video recording** — [references/video-recording.md](references/video-recording.md)
- **Element attributes** — [references/element-attributes.md](references/element-attributes.md)
