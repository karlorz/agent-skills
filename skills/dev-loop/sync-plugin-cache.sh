#!/usr/bin/env bash
# sync-plugin-cache.sh — Copy dev-loop skill files from source to Claude Code plugin cache.
# Usage: ./sync-plugin-cache.sh [version]
#   version: plugin version to sync (default: reads from .claude-plugin/plugin.json)
#
# After running this script, invoke /reload-plugins in Claude Code to pick up changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}"
PLUGIN_JSON="${SOURCE_DIR}/.claude-plugin/plugin.json"

if [[ ! -f "$PLUGIN_JSON" ]]; then
  echo "ERROR: plugin.json not found at ${PLUGIN_JSON}" >&2
  exit 1
fi

VERSION="${1:-$(grep -o '"version": *"[^"]*"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version": *"\([^"]*\)"/\1/')}"

CACHE_DIR="${HOME}/.claude/plugins/cache/karlorz-agent-skills/dev-loop/${VERSION}"

if [[ ! -d "$CACHE_DIR" ]]; then
  echo "ERROR: Cache directory not found: ${CACHE_DIR}" >&2
  echo "  Install the plugin first: claude plugin install dev-loop@agent-skills" >&2
  exit 1
fi

echo "Syncing dev-loop v${VERSION}..."
echo "  Source: ${SOURCE_DIR}"
echo "  Cache:  ${CACHE_DIR}"

# Sync core files (preserving cache-only files like package.json if present)
for file in SKILL.md research.md .claude-plugin/plugin.json; do
  src="${SOURCE_DIR}/${file}"
  dst="${CACHE_DIR}/${file}"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  ✓ ${file}"
  fi
done

# Sync templates directory
if [[ -d "${SOURCE_DIR}/templates" ]]; then
  mkdir -p "${CACHE_DIR}/templates"
  cp "${SOURCE_DIR}/templates/"* "${CACHE_DIR}/templates/"
  echo "  ✓ templates/"
fi

echo ""
echo "Done. Now run /reload-plugins in Claude Code to activate changes."
