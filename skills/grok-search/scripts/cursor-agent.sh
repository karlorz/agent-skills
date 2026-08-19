#!/usr/bin/env bash
# Launch Cursor Agent CLI with grok-search plugin dir + MCP approval.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec agent --plugin-dir "$ROOT" --approve-mcps --trust "$@"
