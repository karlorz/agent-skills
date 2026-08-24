#!/usr/bin/env bash
# SessionStart: apply the URL default to Claude's env handoff; cannot change Grok parent env.
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
exec python3 "$ROOT/scripts/check_readiness.py" --apply --json
