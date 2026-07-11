#!/usr/bin/env bash
# sync-plugin-cache.sh — Copy dev-loop skill files from source to Claude Code plugin cache.
# Usage: ./sync-plugin-cache.sh [version]
#   version: plugin version to sync (default: reads from .claude-plugin/plugin.json)
#
# After running this script, invoke /reload-plugins in Claude Code to pick up changes.
#
# Layout (nested-only): skills/dev-loop/skills/{dev-loop,investigate,...}/SKILL.md

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

# Auto-create the version directory if it doesn't exist yet (e.g., after a
# version bump before the plugin has been reinstalled from marketplace).
if [[ ! -d "$CACHE_DIR" ]]; then
  echo " Cache directory not found — creating ${CACHE_DIR}"
  mkdir -p "$CACHE_DIR"
fi

echo "Syncing dev-loop v${VERSION}..."
echo "  Source: ${SOURCE_DIR}"
echo "  Cache:  ${CACHE_DIR}"

# Sync manifests + dependencies
for file in dependencies.yaml .claude-plugin/plugin.json .codex-plugin/plugin.json; do
  src="${SOURCE_DIR}/${file}"
  dst="${CACHE_DIR}/${file}"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  ✓ ${file}"
  fi
done

# Remove the pre-1.24.2 companion path whose directory name did not match
# frontmatter name: setup-dev-loop.
if [[ -d "${CACHE_DIR}/setup" ]]; then
  rm -rf "${CACHE_DIR}/setup"
  echo "  ✓ removed legacy setup/"
fi

# Nested skills/ is the sole skill surface (Claude + Codex + Grok)
if [[ -d "${SOURCE_DIR}/skills" ]]; then
  rm -rf "${CACHE_DIR}/skills"
  mkdir -p "${CACHE_DIR}/skills"
  cp -R "${SOURCE_DIR}/skills/." "${CACHE_DIR}/skills/"
  echo "  ✓ skills/ (nested-only skill surface)"
fi

# Remove legacy root skill mirrors if present in older cache installs
for legacy in SKILL.md research setup-dev-loop investigate office-hours status; do
  if [[ -e "${CACHE_DIR}/${legacy}" ]]; then
    rm -rf "${CACHE_DIR}/${legacy}"
    echo "  ✓ removed legacy ${legacy}"
  fi
done

# Sync agents directory
if [[ -d "${SOURCE_DIR}/agents" ]]; then
  mkdir -p "${CACHE_DIR}/agents"
  cp "${SOURCE_DIR}/agents/"* "${CACHE_DIR}/agents/"
  echo "  ✓ agents/"
fi

# Sync scripts directory
if [[ -d "${SOURCE_DIR}/scripts" ]]; then
  rm -rf "${CACHE_DIR}/scripts"
  mkdir -p "${CACHE_DIR}/scripts"
  cp -R "${SOURCE_DIR}/scripts/." "${CACHE_DIR}/scripts/"
  echo "  ✓ scripts/"
fi

# Sync templates directory
if [[ -d "${SOURCE_DIR}/templates" ]]; then
  mkdir -p "${CACHE_DIR}/templates"
  cp "${SOURCE_DIR}/templates/"* "${CACHE_DIR}/templates/"
  echo "  ✓ templates/"
fi

# Sync references directory
if [[ -d "${SOURCE_DIR}/references" ]]; then
  rm -rf "${CACHE_DIR}/references"
  mkdir -p "${CACHE_DIR}/references"
  cp -R "${SOURCE_DIR}/references/." "${CACHE_DIR}/references/"
  echo "  ✓ references/"
fi

echo "Done. Run /reload-plugins in Claude Code to pick up changes."
