# Chrome Debug Launcher

Start Chrome with remote debugging enabled, ready for `playwright-cli attach`.

Contract stamp: **`chrome-debug-contract: v4`** (see `scripts/chrome-debug.sh` header).

The bundled `scripts/chrome-debug.sh` handles Chrome detection, profile management, port health checks, detached launch, and CDP `Extensions.loadUnpacked`. The one-time setup script installs it as a stable user-level `chrome-debug` command. **Do not vendor a second copy in consumer repos.**

Prefer:

```bash
chrome-debug
chrome-debug --load-unpacked /path/to/unpacked-extension
# consumer Makefile should call the installed command, not a copied script
make chrome-debug
```

## One-time user setup

Resolve the installed plugin root from the active skill path, then run:

```bash
bash "$PLAYWRIGHT_CLI_PLUGIN_ROOT/scripts/setup-playwright-cli.sh" --project "$PWD"
```

This verifies or installs `@playwright/cli` ≥ 0.1.17, installs the `chrome-debug`
command in `${XDG_BIN_HOME:-$HOME/.local/bin}`, copies the launcher into stable
user data storage, and initializes the current project's `.playwright/cli.config.json`.
It preserves richer existing configs that already target `http://localhost:9222`.
Use `--dry-run` to preview all actions.

## Default profile (global)

**Default mode is `default-user`:** a debug-safe **clone** of your real Chrome user-data directory.

| Host | Clone path |
|------|------------|
| macOS | `~/Library/Application Support/Google/chrome-debug-profile-from-default` |
| Linux | `${XDG_CONFIG_HOME:-$HOME/.config}/Google/chrome-debug-profile-from-default` |

Do **not** use `--repo-local-profile` unless the user explicitly wants an empty isolated profile. Repo-local creates `<repo>/.chrome-debug-profile/` and loses logged-in sessions.

## Quick start

```bash
# Start Chrome with debug port 9222 (default-user profile)
chrome-debug

# Attach playwright-cli (reads cdpEndpoint from .playwright/cli.config.json when present)
playwright-cli attach
# or explicit:
playwright-cli attach --cdp=http://localhost:9222
```

## Common flags

```bash
chrome-debug --check-port
chrome-debug --explain
chrome-debug --dry-run --print-config
chrome-debug --dry-run --json
chrome-debug https://example.com
chrome-debug --launch-and-explain

# Kill existing debug Chrome + stale playwright-cli daemons, same profile mode
chrome-debug --restart

# Install or refresh an unpacked extension on the live :9222 profile (no picker)
chrome-debug --load-unpacked /path/to/unpacked-extension
```

## Profile modes

| Mode | Flag / env | Description |
|------|------------|-------------|
| `default-user` | `--default-user-profile` (default) | Clone of real Chrome profile (cookies, logins). **Preferred.** |
| `dedicated` | `--dedicated-profile` | Persistent OS-native debug-only profile |
| `repo-local` | `--repo-local-profile` | Empty per-repo profile — **explicit isolation only** |

```bash
# Re-sync clone from real Chrome (close personal Chrome first)
chrome-debug --refresh-from-default

# Isolated clean profile (only when requested)
chrome-debug --repo-local-profile
```

## Headless / container (Linux LXC)

| Condition | Behavior |
|-----------|----------|
| macOS | headed by default |
| Linux with `DISPLAY` set | headed |
| Linux with no `DISPLAY` | **auto headless** (`--headless=new`) |
| `CHROME_DEBUG_HEADLESS=1` | force headless (any OS) |
| `CHROME_DEBUG_HEADLESS=0` | force headed |

Non-darwin always adds container-friendly flags: `--no-sandbox`, `--disable-dev-shm-usage`, etc.

CDP binds to `127.0.0.1`. For remote LXC/hosts, tunnel:

```bash
ssh -L 9222:127.0.0.1:9222 user@remote-host
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CHROME_DEBUG_PORT` | `9222` | Remote debugging port |
| `CHROME_DEBUG_PROFILE_MODE` | `default-user` | Profile mode |
| `CHROME_DEBUG_PROFILE` | *(auto)* | Custom user-data directory |
| `CHROME_DEBUG_URL` | `about:blank` | Starting URL |
| `CHROME_DEBUG_PROFILE_DIRECTORY` | `Default` | Chrome profile subdirectory |
| `CHROME_DEBUG_REFRESH_FROM_DEFAULT` | `0` | Re-sync clone on launch |
| `CHROME_DEBUG_HEADLESS` | *(auto)* | empty=auto, `0`=headed, `1`=headless |
| `CHROME_DEBUG_PROJECT_ROOT` | launcher cwd | Project root used by explicit repo-local mode |
| `CHROME_DEBUG_LOG` | user state or bundled log | Chrome launcher log path |
| `CHROME_DEBUG_COMMAND_NAME` | bundled path / `chrome-debug` | Command name shown in help and diagnostics |
| `CHROME_DEBUG_LOAD_UNPACKED` | *(empty)* | Colon-separated extra unpacked extension paths |
| `CHROME` | *(auto-detect)* | Chrome/Chromium binary |

## Typical workflow

```bash
chrome-debug                          # or a consumer Makefile that calls this command
playwright-cli attach
playwright-cli goto https://example.com
playwright-cli snapshot
# Leave Chrome running; detach CLI without killing Chrome when supported:
playwright-cli detach
```

## Stale attach sessions

If `playwright-cli attach` times out while port 9222 is healthy:

```bash
playwright-cli kill-all
chrome-debug --restart
playwright-cli attach
```

## Unpacked extension debugging (Chrome 137+)

The launcher always passes `--enable-unsafe-extension-debugging` so branded Chrome 137+ accepts CDP `Extensions.loadUnpacked` on the TCP debug port (`:9222`), not only over a pipe.

```bash
chrome-debug --load-unpacked /abs/path/to/extension
```

- **Re-apply**: Chrome 152 does **not** persist CDP-loaded unpacked extensions across process restart (they never land in Secure Preferences). This launcher writes the paths to `${PROFILE_DIR}/.chrome-debug-load-unpacked` and re-runs `Extensions.loadUnpacked` after every start, `--restart`, and reuse of an already-running debug Chrome.
- **Stable path**: pass a directory that will still exist after the session (repo `apps/browser-extension`, not a disposable worktree). Vanished sidecar paths are skipped with a warning.
- **`--refresh-from-default`**: still wipes the clone. The sidecar is restored after sync when it existed; pass `--load-unpacked` again if the sidecar was empty.
- **Do not** raw-CDP `Extensions.loadUnpacked`, open `chrome://extensions` Load unpacked, or start a second pipe-debug Chrome against the collect profile.

## Sync note

This skill is the **SSOT**. Install the user-level command; do **not** copy `chrome-debug.sh` into consumer repos:

```bash
bash "$PLAYWRIGHT_CLI_PLUGIN_ROOT/scripts/setup-playwright-cli.sh" --project "$PWD"
chrome-debug --load-unpacked /path/to/unpacked-extension
```

A consumer Makefile may wrap `chrome-debug` (for example to always pass a repo extension path). It must not vendor a second launcher.
