#!/usr/bin/env bash
set -euo pipefail

TARGET_BIN="$HOME/Library/Application Support/cursor-box-channel/bin/cursor-box-mcp"

if [ ! -x "$TARGET_BIN" ]; then
  printf 'cursor-box-channel: runner executable not found at "%s".\n' "$TARGET_BIN" >&2
  printf 'Please install the daemon and adapter from karlorz/cursor-box-channel.\n' >&2
  exit 1
fi

exec "$TARGET_BIN" "$@"
