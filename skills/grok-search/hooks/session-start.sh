#!/usr/bin/env bash
# SessionStart: apply in-process GROK_SEARCH_MCP_URL default when TOKEN is set.
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
exec python3 "$ROOT/scripts/check_readiness.py" --apply --json
