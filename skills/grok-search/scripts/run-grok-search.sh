#!/usr/bin/env bash
# Load env migrated from a prior user MCP install, then exec the uvx pin.
set -euo pipefail
ENV_FILE="${GROK_SEARCH_ENV_FILE:-${HOME}/.config/grok-search/mcp.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi
exec uvx --from git+https://github.com/karlorz/GrokSearch@grok-with-tavily grok-search
