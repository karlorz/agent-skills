#!/usr/bin/env bash
# Sets AGENT. Source from sibling rempin scripts after set -euo pipefail.
# Exits 1 if neither cursor-agent nor agent is available.
AGENT="${CURSOR_AGENT_BIN:-}"
if [[ -z "$AGENT" ]]; then
  if command -v cursor-agent >/dev/null 2>&1; then
    AGENT="cursor-agent"
  elif command -v agent >/dev/null 2>&1; then
    AGENT="agent"
  else
    echo "FAIL: cursor-agent/agent not on PATH" >&2
    exit 1
  fi
fi
