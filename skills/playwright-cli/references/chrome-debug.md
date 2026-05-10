# Chrome Debug Launcher

Start Chrome with remote debugging enabled, ready for `playwright-cli attach`.

The bundled `scripts/chrome-debug.sh` script handles Chrome detection, profile management, port health checks, and detached launch. It is the recommended way to start Chrome before using `playwright-cli attach`.

**Always run this script via `bash scripts/chrome-debug.sh` (not `make`, not `./scripts/` which may lack execute permission).**

## Quick Start

```bash
# Start Chrome with debug port 9222 (default)
bash scripts/chrome-debug.sh

# Then attach playwright-cli
playwright-cli attach
```

## Common Flags

```bash
# Check if debug port is already in use
bash scripts/chrome-debug.sh --check-port

# Diagnose issues without launching
bash scripts/chrome-debug.sh --explain

# Print resolved config as JSON
bash scripts/chrome-debug.sh --dry-run --json

# Start with a specific URL
bash scripts/chrome-debug.sh https://example.com

# Launch with diagnosis first
bash scripts/chrome-debug.sh --launch-and-explain

# Kill existing Chrome + stale playwright-cli daemons and launch fresh
bash scripts/chrome-debug.sh --restart
```

## Profile Modes

The script supports three profile modes, controlled by flags or `CHROME_DEBUG_PROFILE_MODE`:

| Mode | Flag | Description |
|------|------|-------------|
| `default-user` | `--default-user-profile` | Clones your real Chrome profile (cookies, bookmarks, extensions). **Default mode.** |
| `repo-local` | `--repo-local-profile` | Uses `<repo>/.chrome-debug-profile/`. Clean slate per project. |
| `dedicated` | `--dedicated-profile` | Persistent OS-native profile for cmux/debug-only use. |

```bash
# Use a clean profile (no cookies/history from personal Chrome)
bash scripts/chrome-debug.sh --repo-local-profile

# Refresh cloned profile from real Chrome (must close Chrome first)
bash scripts/chrome-debug.sh --refresh-from-default
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CHROME_DEBUG_PORT` | `9222` | Remote debugging port |
| `CHROME_DEBUG_PROFILE_MODE` | `default-user` | Profile mode |
| `CHROME_DEBUG_PROFILE` | *(auto)* | Custom user-data directory path |
| `CHROME_DEBUG_URL` | `about:blank` | Starting URL |
| `CHROME_DEBUG_PROFILE_DIRECTORY` | `Default` | Chrome profile subdirectory name |
| `CHROME_DEBUG_REFRESH_FROM_DEFAULT` | `0` | Re-sync cloned profile on launch |
| `CHROME` | *(auto-detect)* | Path to Chrome/Chromium binary |

## Typical Workflow with playwright-cli

```bash
# 1. Ensure Chrome is running with debugging
bash scripts/chrome-debug.sh

# 2. Attach playwright-cli to the running Chrome
playwright-cli attach

# 3. Interact with pages
playwright-cli goto https://example.com
playwright-cli snapshot

# 4. Chrome stays running — re-attach anytime
# Only use close to shut Chrome down
playwright-cli close
```

## Sync Note

This script is bundled from `cmux/scripts/chrome-debug.sh`. When the upstream script is updated, re-copy it:

```bash
cp /path/to/cmux/scripts/chrome-debug.sh scripts/chrome-debug.sh
```
