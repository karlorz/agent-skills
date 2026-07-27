# Chrome Debug Launcher

Start Chrome with remote debugging enabled, ready for `playwright-cli attach`.

Contract stamp: **`chrome-debug-contract: v2`** (see `scripts/chrome-debug.sh` header).

The bundled `scripts/chrome-debug.sh` handles Chrome detection, profile management, port health checks, and detached launch. It is the recommended way to start Chrome before using `playwright-cli attach`.

Prefer:

```bash
bash scripts/chrome-debug.sh
# or, when the consumer repo has a Makefile target:
make chrome-debug
```

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
bash scripts/chrome-debug.sh

# Attach playwright-cli (reads cdpEndpoint from .playwright/cli.config.json when present)
playwright-cli attach
# or explicit:
playwright-cli attach --cdp=http://localhost:9222
```

## Common flags

```bash
bash scripts/chrome-debug.sh --check-port
bash scripts/chrome-debug.sh --explain
bash scripts/chrome-debug.sh --dry-run --print-config
bash scripts/chrome-debug.sh --dry-run --json
bash scripts/chrome-debug.sh https://example.com
bash scripts/chrome-debug.sh --launch-and-explain

# Kill existing debug Chrome + stale playwright-cli daemons, same profile mode
bash scripts/chrome-debug.sh --restart
```

## Profile modes

| Mode | Flag / env | Description |
|------|------------|-------------|
| `default-user` | `--default-user-profile` (default) | Clone of real Chrome profile (cookies, logins). **Preferred.** |
| `dedicated` | `--dedicated-profile` | Persistent OS-native debug-only profile |
| `repo-local` | `--repo-local-profile` | Empty per-repo profile — **explicit isolation only** |

```bash
# Re-sync clone from real Chrome (close personal Chrome first)
bash scripts/chrome-debug.sh --refresh-from-default

# Isolated clean profile (only when requested)
bash scripts/chrome-debug.sh --repo-local-profile
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
| `CHROME` | *(auto-detect)* | Chrome/Chromium binary |

## Typical workflow

```bash
bash scripts/chrome-debug.sh          # or make chrome-debug
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
bash scripts/chrome-debug.sh --restart
playwright-cli attach
```

## Sync note

This script is the **SSOT** in `karlorz/agent-skills` (`skills/playwright-cli/scripts/chrome-debug.sh`). Consumer repos (trends, cmux, portfolio-lab, …) should re-copy when the contract version bumps:

```bash
cp path/to/agent-skills/skills/playwright-cli/scripts/chrome-debug.sh scripts/chrome-debug.sh
```
