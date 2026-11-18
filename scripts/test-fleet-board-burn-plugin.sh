#!/usr/bin/env bash
# fleet-board-burn portable MCP launcher fixture. Off-box: JSON parity plus
# Darwin/Linux uname stubs. Do not run on BOX; parent executes on Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/scripts/test-fleet-board-burn-plugin.py" "$@"
