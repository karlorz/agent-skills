---
name: playwright-cli
description: "Automate headed Chrome with Playwright CLI: inspect, screenshot, and test pages. Use for browser automation or chrome-debug setup."
allowed-tools: Bash(playwright-cli:*) Bash(npx:*) Bash(npm:*) Bash(chrome-debug:*) Bash(bash\ scripts/chrome-debug.sh:*) Bash(bash\ scripts/setup-playwright-cli.sh:*) Bash(make\ chrome-debug:*)
---

# Browser Automation with playwright-cli

Karlorz fork of the Microsoft playwright-cli skill: **preserve MS command surface**,
layer **attach-first + global Chrome profile** via `scripts/chrome-debug.sh`.

Requires `@playwright/cli` **≥ 0.1.17**. Use the setup workflow below to
install or verify it without `sudo`.

## One-time setup / init

When the user asks to install, initialize, configure, or set up Playwright CLI:

1. Resolve the plugin root from this loaded `SKILL.md` path (two directories above
   `skills/playwright-cli/SKILL.md`). Assign that absolute path to
   `PLAYWRIGHT_CLI_PLUGIN_ROOT`; do not assume the variable already exists.
2. Run the bundled setup script against the user's current project:

```bash
bash "$PLAYWRIGHT_CLI_PLUGIN_ROOT/scripts/setup-playwright-cli.sh" --project "$PWD"
```

The script is idempotent. It:

- installs or verifies user-accessible `@playwright/cli` ≥ 0.1.17;
- installs `chrome-debug` under `${XDG_BIN_HOME:-$HOME/.local/bin}` with its
  payload in `${XDG_DATA_HOME:-$HOME/.local/share}/playwright-cli`;
- creates `.playwright/cli.config.json` when absent;
- preserves an existing config that already targets `http://localhost:9222`;
- refuses to overwrite divergent config or an unmanaged launcher unless the user
  explicitly approves the corresponding `--force-*` flag.

Use `--dry-run` to preview, `--skip-cli` when npm installation is out of scope,
or `--skip-project-config` for launcher-only setup. Do not run setup merely because
the skill activated; run it when the user asks for setup/init or a required command
is missing and the user authorizes installation.

## Karlorz defaults (read first)

### Preferred runtime: attach to chrome-debug

```bash
# 1) Preferred after one-time setup: works from any repository
chrome-debug

# Consumer-repo fallbacks:
make chrome-debug
bash scripts/chrome-debug.sh

# 2) Attach (uses .playwright/cli.config.json cdpEndpoint when present)
playwright-cli attach
# or:
playwright-cli attach --cdp=http://localhost:9222

# 3) Interact
playwright-cli goto https://example.com
playwright-cli snapshot
```

**Default profile mode is `default-user`** (clone under Application Support / XDG — not a new empty profile).

| Mode | When to use |
|------|-------------|
| `default-user` | **Default.** Shared global debug clone of real Chrome (cookies/logins). |
| `dedicated` | Long-lived automation-only OS profile. |
| `repo-local` | **Only if the user asks** for a clean isolated profile (`--repo-local-profile`). |

### Phase 0 sequence (ALWAYS before attach)

```bash
chrome-debug --check-port
# If free:
chrome-debug
# If stale / attach fails:
playwright-cli kill-all
chrome-debug --restart
playwright-cli attach
```

Never invent `--repo-local-profile` as recovery. Prefer closing personal Chrome so the default-user clone can be created, or reuse an existing clone.

### Config

Project `.playwright/cli.config.json` typically sets:

```json
{
  "browser": {
    "browserName": "chromium",
    "cdpEndpoint": "http://localhost:9222",
    "launchOptions": { "headless": false, "channel": "chrome" }
  }
}
```

`cdpEndpoint` makes attach/open prefer an existing debugger. Launch Chrome first with `chrome-debug.sh`. Profile paths are **not** set in this config — only by chrome-debug.

### Host matrix

- **macOS:** headed; default-user clone under `~/Library/Application Support/Google/chrome-debug-profile-from-default`
- **Linux / LXC / container:** `--no-sandbox` + shm flags; **headless auto when `DISPLAY` is unset**; override with `CHROME_DEBUG_HEADLESS=0|1`
- **Remote:** tunnel CDP `ssh -L 9222:127.0.0.1:9222 host`

Details: [references/chrome-debug.md](references/chrome-debug.md)

### Model strategy

- Chrome launch / check-port: lightweight model (`haiku` when available)
- Multi-step interaction (snapshot, click, fill): `sonnet` when available
- Orchestrator owns intent; browser-worker owns mechanical command sequences

### Anti-patterns

- **`playwright-cli open` without need** when a logged-in session is required — use chrome-debug + attach instead
- **`--repo-local-profile` by default** — creates empty profile; only on explicit request
- **Skipping attach** after launch — interaction commands need an attached session
- **Assuming `make chrome-debug` is invalid** — use it when the consumer Makefile provides it
- **Assuming the consumer repo vendors the launcher** — prefer the installed `chrome-debug` command
- Forgetting snapshot before click/fill (need element refs)

### Fallback: disposable browser (Microsoft default)

When you do not need a real logged-in profile:

```bash
playwright-cli open
playwright-cli open https://example.com
```

---

## Microsoft command reference

The sections below track the upstream Microsoft playwright-cli skill (package ≥ 0.1.17).

## Quick start

```bash
# open new browser
playwright-cli open
# navigate to a page
playwright-cli goto https://playwright.dev
# interact with the page using refs from the snapshot
playwright-cli click e15
playwright-cli type "page.click"
playwright-cli press Enter
# take a screenshot (rarely used, as snapshot is more common)
playwright-cli screenshot
# close the browser
playwright-cli close
```

## Commands

### Core

```bash
playwright-cli open
# open and navigate right away
playwright-cli open https://example.com/
playwright-cli goto https://playwright.dev
playwright-cli type "search query"
playwright-cli click e3
playwright-cli dblclick e7
# --submit presses Enter after filling the element
playwright-cli fill e5 "user@example.com"  --submit
playwright-cli drag e2 e8
# drop files or data onto an element (from outside the page)
playwright-cli drop e4 --path=./image.png
playwright-cli drop e4 --data="text/plain=hello world"
playwright-cli hover e4
playwright-cli select e9 "option-value"
playwright-cli upload ./document.pdf
playwright-cli check e12
playwright-cli uncheck e12
playwright-cli snapshot
# search the snapshot for text or a regexp, returns matching nodes with surrounding context
playwright-cli find "Sign in"
playwright-cli find --regex "Sign (in|up)"
# wrap the regexp in slashes to add flags, e.g. /i for case-insensitive
playwright-cli find --regex "/sign (in|up)/i"
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
# get element id, class, or any attribute not visible in the snapshot
playwright-cli eval "el => el.id" e5
playwright-cli eval "el => el.getAttribute('data-testid')" e5
playwright-cli dialog-accept
playwright-cli dialog-accept "confirmation text"
playwright-cli dialog-dismiss
playwright-cli resize 1920 1080
playwright-cli close
```

### Navigation

```bash
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
```

### Keyboard

```bash
playwright-cli press Enter
playwright-cli press ArrowDown
playwright-cli keydown Shift
playwright-cli keyup Shift
```

### Mouse

```bash
playwright-cli mousemove 150 300
playwright-cli mousedown
playwright-cli mousedown right
playwright-cli mouseup
playwright-cli mouseup right
playwright-cli mousewheel 0 100
```

### Save as

```bash
playwright-cli screenshot
playwright-cli screenshot e5
playwright-cli screenshot --filename=page.png
playwright-cli screenshot --hires
playwright-cli pdf --filename=page.pdf
```

### Tabs

```bash
playwright-cli tab-list
playwright-cli tab-new
playwright-cli tab-new https://example.com/page
playwright-cli tab-close
playwright-cli tab-close 2
playwright-cli tab-select 0
```

### Storage

```bash
playwright-cli state-save
playwright-cli state-save auth.json
playwright-cli state-load auth.json

# Cookies
playwright-cli cookie-list
playwright-cli cookie-list --domain=example.com
playwright-cli cookie-get session_id
playwright-cli cookie-set session_id abc123
playwright-cli cookie-set session_id abc123 --domain=example.com --httpOnly --secure
playwright-cli cookie-delete session_id
playwright-cli cookie-clear

# LocalStorage
playwright-cli localstorage-list
playwright-cli localstorage-get theme
playwright-cli localstorage-set theme dark
playwright-cli localstorage-delete theme
playwright-cli localstorage-clear

# SessionStorage
playwright-cli sessionstorage-list
playwright-cli sessionstorage-get step
playwright-cli sessionstorage-set step 3
playwright-cli sessionstorage-delete step
playwright-cli sessionstorage-clear
```

### Network

```bash
playwright-cli route "**/*.jpg" --status=404
playwright-cli route "https://api.example.com/**" --body='{"mock": true}'
playwright-cli route-list
playwright-cli unroute "**/*.jpg"
playwright-cli unroute
```

### DevTools

```bash
playwright-cli console
playwright-cli console warning
playwright-cli requests
playwright-cli request 5
playwright-cli run-code "async page => await page.context().grantPermissions(['geolocation'])"
playwright-cli run-code --filename=script.js
playwright-cli tracing-start
playwright-cli tracing-stop
playwright-cli video-start video.webm
playwright-cli video-chapter "Chapter Title" --description="Details" --duration=2000
playwright-cli video-stop

# annotate each subsequent action (click, type, ...) with a callout naming the action and highlighting the target
playwright-cli video-show-actions --duration=600 --position=top-right
playwright-cli video-hide-actions

# launch the dashboard for UI review / design feedback — user annotates the page, you receive the annotated screenshot, snapshot, and notes
playwright-cli show --annotate

# generate a Playwright locator for an element from its ref or selector
playwright-cli generate-locator e5 --raw

# show a persistent highlight overlay for an element, optionally with a custom style
playwright-cli highlight e5
playwright-cli highlight e5 --style="outline: 3px dashed red"
# hide a single element highlight, or all page highlights when no target is given
playwright-cli highlight e5 --hide
playwright-cli highlight --hide
```

## Raw output

The global `--raw` option strips page status, generated code, and snapshot sections from the output, returning only the result value. Use it to pipe command output into other tools. Commands that don't produce output return nothing.

```bash
playwright-cli --raw eval "JSON.stringify(performance.timing)" | jq '.loadEventEnd - .navigationStart'
playwright-cli --raw eval "JSON.stringify([...document.querySelectorAll('a')].map(a => a.href))" > links.json
playwright-cli --raw snapshot > before.yml
playwright-cli click e5
playwright-cli --raw snapshot > after.yml
diff before.yml after.yml
TOKEN=$(playwright-cli --raw cookie-get session_id)
playwright-cli --raw localstorage-get theme
```

For structured output wrapping every reply as JSON, pass --json
```bash
playwright-cli list --json
```

## Open parameters
```bash
# Use specific browser when creating session
playwright-cli open --browser=chrome
playwright-cli open --browser=firefox
playwright-cli open --browser=webkit
playwright-cli open --browser=msedge

# Emulate a generic mobile device (Pixel 10 for Chromium, iPhone 17 for WebKit).
# Prefer this when a mobile layout is acceptable: mobile pages are usually
# lighter, so snapshots are smaller and cheaper.
playwright-cli open --mobile
playwright-cli open --device="iPhone 15"

# Use persistent profile (by default profile is in-memory)
playwright-cli open --persistent
# Use persistent profile with custom directory
playwright-cli open --profile=/path/to/profile

# Connect to browser via Playwright Extension
playwright-cli attach --extension=chrome

# Connect to a running Chrome or Edge by channel name
playwright-cli attach --cdp=chrome
playwright-cli attach --cdp=msedge

# Connect to a running browser via CDP endpoint
playwright-cli attach --cdp=http://localhost:9222

# Start with config file
playwright-cli open --config=my-config.json

# Close the browser
playwright-cli close
# Detach from an attached browser (leaves the external browser running)
playwright-cli -s=msedge detach
# Delete user data for the default session
playwright-cli delete-data
```

## URLs with `&` on Windows

On Windows, `cmd.exe` and PowerShell treat `&` as a command separator, so URLs with multiple query parameters get truncated before `playwright-cli` runs. Escape `&` with `^&` in `cmd.exe`, or use `--%` in PowerShell:

```batch
playwright-cli goto "https://example.com/?a=1^&b=2"
```

```powershell
playwright-cli --% goto "https://example.com/?a=1&b=2"
```

## Snapshots

After each command, playwright-cli provides a snapshot of the current browser state.

```bash
> playwright-cli goto https://example.com
### Page
- Page URL: https://example.com/
- Page Title: Example Domain
### Snapshot
[Snapshot](.playwright-cli/page-2026-02-14T19-22-42-679Z.yml)
```

You can also take a snapshot on demand using `playwright-cli snapshot` command. All the options below can be combined as needed.

```bash
# default - save to a file with timestamp-based name
playwright-cli snapshot

# save to file, use when snapshot is a part of the workflow result
playwright-cli snapshot --filename=after-click.yaml

# snapshot an element instead of the whole page
playwright-cli snapshot "#main"

# limit snapshot depth for efficiency, take a partial snapshot afterwards
playwright-cli snapshot --depth=4
playwright-cli snapshot e34

# include each element's bounding box as [box=x,y,width,height]
playwright-cli snapshot --boxes

# search a large snapshot instead of capturing it all — returns matching nodes
# with 3 lines of context around each match (like grep -C)
playwright-cli find "Add to cart"
playwright-cli find --regex "\\$[0-9]+\\.[0-9]{2}"
```

## Targeting elements

By default, use refs from the snapshot to interact with page elements.

```bash
# get snapshot with refs
playwright-cli snapshot

# interact using a ref
playwright-cli click e15
```

You can also use css selectors or Playwright locators.

```bash
# css selector
playwright-cli click "#main > button.submit"

# role locator
playwright-cli click "getByRole('button', { name: 'Submit' })"

# test id
playwright-cli click "getByTestId('submit-button')"
```

## Browser Sessions

```bash
# create new browser session named "mysession" with persistent profile
playwright-cli -s=mysession open example.com --persistent
# same with manually specified profile directory (use when requested explicitly)
playwright-cli -s=mysession open example.com --profile=/path/to/profile
playwright-cli -s=mysession click e6
playwright-cli -s=mysession close  # stop a named browser
playwright-cli -s=mysession delete-data  # delete user data for persistent session

playwright-cli list
# Close all browsers
playwright-cli close-all
# Forcefully kill all browser processes
playwright-cli kill-all
```

## Installation

If global `playwright-cli` command is not available, try a local version via `npx playwright cli`:

```bash
npx --no-install playwright --version
```

When local version is available, use `npx playwright cli` in all commands. Otherwise, install `playwright-cli` as a global command:

```bash
npm install -g @playwright/cli@latest
```

## Example: Form submission

```bash
playwright-cli open https://example.com/form
playwright-cli snapshot

playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e3
playwright-cli snapshot
playwright-cli close
```

## Example: Multi-tab workflow

```bash
playwright-cli open https://example.com
playwright-cli tab-new https://example.com/other
playwright-cli tab-list
playwright-cli tab-select 0
playwright-cli snapshot
playwright-cli close
```

## Example: Debugging with DevTools

```bash
playwright-cli open https://example.com
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli console
playwright-cli requests
playwright-cli close
```

```bash
playwright-cli open https://example.com
playwright-cli tracing-start
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli tracing-stop
playwright-cli close
```

## Example: Interactive session

Ask the user for UI review or design feedback. The user draws boxes on the live page and types comments; you receive the annotated screenshot, the snapshot of the marked region, and the user's notes. Use this whenever the user asks for "UI review", "design feedback", or to "ask the user what they think / want / mean":

```bash
playwright-cli open https://example.com
playwright-cli show --annotate
```

## Specific tasks

* **Running and Debugging Playwright tests** [references/playwright-tests.md](references/playwright-tests.md)
* **Request mocking** [references/request-mocking.md](references/request-mocking.md)
* **Running Playwright code** [references/running-code.md](references/running-code.md)
* **Browser session management** [references/session-management.md](references/session-management.md)
* **Storage state (cookies, localStorage)** [references/storage-state.md](references/storage-state.md)
* **Test generation (plan / generate / heal)** [references/test-generation.md](references/test-generation.md)
* **Tracing** [references/tracing.md](references/tracing.md)
* **Video recording** [references/video-recording.md](references/video-recording.md)
* **Inspecting element attributes** [references/element-attributes.md](references/element-attributes.md)
* **Chrome debug launcher (Karlorz)** [references/chrome-debug.md](references/chrome-debug.md)
