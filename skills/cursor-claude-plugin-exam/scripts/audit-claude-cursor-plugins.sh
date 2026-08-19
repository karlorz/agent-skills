#!/usr/bin/env bash
# audit-claude-cursor-plugins.sh — read-only Claude→Cursor plugin discovery exam
# Exit 0 unless fatal tooling error. Does not convert or create symlinks.
set -euo pipefail

HOME_DIR="${HOME:-}"
CLAUDE_SKILLS="${HOME_DIR}/.claude/skills"
CLAUDE_SETTINGS="${HOME_DIR}/.claude/settings.json"
CURSOR_LOCAL="${HOME_DIR}/.cursor/plugins/local"
CURSOR_SKILLS="${HOME_DIR}/.cursor/skills"
CURSOR_MCP="${HOME_DIR}/.cursor/mcp.json"
AGENT_SKILLS_CACHE="${HOME_DIR}/.claude/plugins/cache/karlorz-agent-skills"
SKILLWIKI_CACHE_ROOT="${HOME_DIR}/.claude/plugins/cache/llm-wiki/skillwiki"
CURSOR_MKT_ROOT="${HOME_DIR}/.cursor/plugins/marketplaces/github.com/karlorz/llm-wiki"
CURSOR_CACHE_ROOT="${HOME_DIR}/.cursor/plugins/cache/llm-wiki/skillwiki"

pass=0
info=0
optional=0
warn=0
fail=0
stale_cursor_pack=0

row() {
  local status="$1" name="$2" detail="$3"
  printf '%-8s  %-42s  %s\n' "$status" "$name" "$detail"
  case "$status" in
    PASS)     pass=$((pass + 1)) ;;
    INFO)     info=$((info + 1)) ;;
    OPTIONAL) optional=$((optional + 1)) ;;
    WARN)     warn=$((warn + 1)) ;;
    FAIL)     fail=$((fail + 1)) ;;
  esac
}

read_plugin_json_version() {
  local dir="$1"
  python3 - "$dir" <<'PY' 2>/dev/null || true
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
candidates = [
    root / ".claude-plugin" / "plugin.json",
    root / "plugin.json",
    root / ".claude-plugin" / "marketplace.json",
]
for path in candidates:
    if not path.is_file():
        continue
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    if isinstance(data.get("version"), str) and data["version"]:
        print(data["version"])
        raise SystemExit(0)
    meta = data.get("metadata") or {}
    if isinstance(meta.get("version"), str) and meta["version"]:
        print(meta["version"])
        raise SystemExit(0)
    for plugin in data.get("plugins") or []:
        if isinstance(plugin, dict) and plugin.get("name") == "skillwiki" and isinstance(plugin.get("version"), str):
            print(plugin["version"])
            raise SystemExit(0)
print("")
PY
}

echo "Claude → Cursor plugin exam (read-only; no convert)"
echo "Host: $(hostname 2>/dev/null || echo unknown)  User: ${USER:-unknown}"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "Rule: missing ~/.cursor/plugins is OPTIONAL when Claude cache discovery works."
echo

# --- Claude settings / enabledPlugins ---
claude_settings_ok=0
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  row "PASS" "claude.settings" "found ~/.claude/settings.json"
  if command -v python3 >/dev/null 2>&1; then
    mapfile -t enabled < <(python3 - "$CLAUDE_SETTINGS" <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        s = json.load(f)
    for k, v in sorted((s.get('enabledPlugins') or {}).items()):
        if v:
            print(k)
except Exception:
    pass
PY
)
    if [[ ${#enabled[@]} -gt 0 ]]; then
      claude_settings_ok=1
      row "PASS" "claude.enabledPlugins" "${#enabled[@]} enabled (Claude SSOT for plugin-on)"
      for p in "${enabled[@]}"; do
        case "$p" in
          skillwiki@llm-wiki|dev-loop@*|deep-research-dev@*|deep-research@*|vault-sync@*|grok-search@*)
            row "INFO" "claude.enabled.${p%%@*}" "$p"
            ;;
        esac
      done
    else
      row "FAIL" "claude.enabledPlugins" "no enabledPlugins entries"
    fi
  else
    row "INFO" "claude.enabledPlugins" "python3 unavailable; inspect settings.json manually"
  fi
  if grep -q '"hooks"' "$CLAUDE_SETTINGS" 2>/dev/null; then
    row "INFO" "claude.settings.hooks" "hooks key present (Cursor third-party may load)"
  else
    row "INFO" "claude.settings.hooks" "no hooks key"
  fi
else
  row "FAIL" "claude.settings" "missing ~/.claude/settings.json"
fi

# --- Home skills (separate from plugin cache) ---
if [[ -d "$CLAUDE_SKILLS" ]]; then
  count=$(find "$CLAUDE_SKILLS" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l | tr -d ' ')
  row "PASS" "claude.home_skills" "${count} entries under ~/.claude/skills (cc-switch / home skills, separate from plugin cache)"
else
  row "INFO" "claude.home_skills" "no ~/.claude/skills (cc-switch / home skills, separate from plugin cache)"
fi

# --- SkillWiki Claude cache vs Cursor marketplace/plugin cache ---
skillwiki_cache_ok=0
claude_sw_version=""
if [[ -d "$SKILLWIKI_CACHE_ROOT" ]]; then
  latest_sw=$(ls -d "${SKILLWIKI_CACHE_ROOT}"/*/ 2>/dev/null | sort -V | tail -1 || true)
  latest_sw="${latest_sw%/}"
  if [[ -n "${latest_sw:-}" ]]; then
    ver=$(basename "$latest_sw")
    claude_sw_version="$ver"
    if command -v python3 >/dev/null 2>&1; then
      pkg_ver="$(read_plugin_json_version "$latest_sw")"
      if [[ -n "$pkg_ver" ]]; then
        claude_sw_version="$pkg_ver"
      fi
    fi
    skillwiki_cache_ok=1
    row "PASS" "skillwiki.cache" "present ($ver)"
    if [[ -f "${latest_sw}/using-skillwiki/SKILL.md" ]]; then
      row "PASS" "skillwiki.using-skillwiki" "${latest_sw}/using-skillwiki/SKILL.md"
    else
      row "FAIL" "skillwiki.using-skillwiki" "SKILL.md missing under $ver"
    fi
  else
    row "FAIL" "skillwiki.cache" "llm-wiki/skillwiki cache empty"
  fi
else
  row "FAIL" "skillwiki.cache" "missing ~/.claude/plugins/cache/llm-wiki/skillwiki"
fi

# Compare Cursor marketplace/plugin cache packs if present
cursor_pack_found=0
cursor_pack_ver=""
cursor_pack_path=""

if [[ -d "$CURSOR_MKT_ROOT" ]]; then
  latest_cmkt=$(ls -d "${CURSOR_MKT_ROOT}"/*/ 2>/dev/null | sort | tail -1 || true)
  latest_cmkt="${latest_cmkt%/}"
  if [[ -n "${latest_cmkt:-}" ]]; then
    cursor_pack_found=1
    cursor_pack_path="$latest_cmkt"
    if command -v python3 >/dev/null 2>&1; then
      cursor_pack_ver="$(read_plugin_json_version "$latest_cmkt")"
    fi
    if [[ -z "$cursor_pack_ver" ]]; then
      cursor_pack_ver="$(basename "$latest_cmkt")"
    fi
  fi
fi

if [[ "$cursor_pack_found" -eq 0 && -d "$CURSOR_CACHE_ROOT" ]]; then
  latest_ccache=$(ls -d "${CURSOR_CACHE_ROOT}"/*/ 2>/dev/null | sort | tail -1 || true)
  latest_ccache="${latest_ccache%/}"
  if [[ -n "${latest_ccache:-}" ]]; then
    cursor_pack_found=1
    cursor_pack_path="$latest_ccache"
    if command -v python3 >/dev/null 2>&1; then
      cursor_pack_ver="$(read_plugin_json_version "$latest_ccache")"
    fi
    if [[ -z "$cursor_pack_ver" ]]; then
      cursor_pack_ver="$(basename "$latest_ccache")"
    fi
  fi
fi

if [[ "$cursor_pack_found" -eq 1 ]]; then
  if [[ -n "$claude_sw_version" && -n "$cursor_pack_ver" ]]; then
    is_stale=$(python3 -c '
import sys
v_claude = sys.argv[1]
v_cursor = sys.argv[2]
def parse_ver(v):
    return [int(x) if x.isdigit() else x for x in v.replace("-", ".").split(".")]
try:
    print(1 if parse_ver(v_cursor) < parse_ver(v_claude) else 0)
except Exception:
    print(0)
' "$claude_sw_version" "$cursor_pack_ver" 2>/dev/null || echo 0)

    if [[ "$is_stale" == "1" ]]; then
      stale_cursor_pack=1
      row "WARN" "skillwiki.cursor_pack_stale" "Cursor pack ($cursor_pack_ver at $cursor_pack_path) is older than Claude cache ($claude_sw_version)"
    else
      row "PASS" "skillwiki.cursor_pack" "Cursor pack ($cursor_pack_ver) matches/newer than Claude cache ($claude_sw_version)"
    fi
  else
    row "INFO" "skillwiki.cursor_pack" "found Cursor pack ($cursor_pack_ver at $cursor_pack_path)"
  fi
else
  row "INFO" "skillwiki.cursor_pack" "Cursor marketplace pack absent (optional Team snapshot)"
fi

# --- Key agent-skills cache entries ---
EXPECTED_PLUGINS=(
  deep-research-dev
  deep-research
  dev-loop
  simplify
)

if [[ -d "$AGENT_SKILLS_CACHE" ]]; then
  row "PASS" "agent-skills.cache" "found $AGENT_SKILLS_CACHE"
  for name in "${EXPECTED_PLUGINS[@]}"; do
    plugin_root="${AGENT_SKILLS_CACHE}/${name}"
    if [[ ! -d "$plugin_root" ]]; then
      row "INFO" "agent-skills.${name}" "not in cache (optional)"
      continue
    fi
    latest=$(ls -d "${plugin_root}"/*/ 2>/dev/null | sort -V | tail -1 || true)
    latest="${latest%/}"
    if [[ -n "${latest:-}" ]] && [[ -f "${latest}/skills/${name}/SKILL.md" || -f "${latest}/SKILL.md" ]]; then
      row "PASS" "agent-skills.${name}" "cache $(basename "$latest")"
    elif [[ -n "${latest:-}" ]]; then
      row "PASS" "agent-skills.${name}" "cache version dir $(basename "$latest")"
    else
      row "INFO" "agent-skills.${name}" "cache present but no version dir"
    fi
  done
else
  row "FAIL" "agent-skills.cache" "missing $AGENT_SKILLS_CACHE"
fi

# --- grok-search MCP rows ---
grok_mcp_found=0
# 1. Claude cache
if [[ -d "${AGENT_SKILLS_CACHE}/grok-search" ]]; then
  latest_gs=$(ls -d "${AGENT_SKILLS_CACHE}/grok-search"/*/ 2>/dev/null | sort -V | tail -1 || true)
  latest_gs="${latest_gs%/}"
  if [[ -n "${latest_gs:-}" && -f "${latest_gs}/.mcp.json" ]]; then
    grok_mcp_found=1
    row "PASS" "grok-search.mcp" "found .mcp.json in Claude cache ($(basename "$latest_gs"))"
  fi
fi

# 2. Cursor local / cache
if [[ "$grok_mcp_found" -eq 0 && -d "${CURSOR_LOCAL}/grok-search" && -f "${CURSOR_LOCAL}/grok-search/.mcp.json" ]]; then
  grok_mcp_found=1
  row "PASS" "grok-search.mcp" "found .mcp.json in ~/.cursor/plugins/local/grok-search"
fi
if [[ "$grok_mcp_found" -eq 0 && -d "${HOME_DIR}/.cursor/plugins/cache/karlorz-agent-skills/grok-search" ]]; then
  latest_cgs=$(ls -d "${HOME_DIR}/.cursor/plugins/cache/karlorz-agent-skills/grok-search"/*/ 2>/dev/null | sort -V | tail -1 || true)
  latest_cgs="${latest_cgs%/}"
  if [[ -n "${latest_cgs:-}" && -f "${latest_cgs}/.mcp.json" ]]; then
    grok_mcp_found=1
    row "PASS" "grok-search.mcp" "found .mcp.json in Cursor plugin cache ($(basename "$latest_cgs"))"
  fi
fi

if [[ "$grok_mcp_found" -eq 0 ]]; then
  row "INFO" "grok-search.mcp" "grok-search plugin not installed (optional)"
fi

# grok-search local link
if [[ -e "${CURSOR_LOCAL}/grok-search" ]]; then
  row "OPTIONAL" "grok-search.local_link" "present in ~/.cursor/plugins/local/grok-search (optional)"
else
  row "OPTIONAL" "grok-search.local_link" "absent (optional; not required for plugin-chain)"
fi

# grok-search in ~/.cursor/mcp.json
if [[ -f "$CURSOR_MCP" ]] && grep -q 'grok-search' "$CURSOR_MCP" 2>/dev/null; then
  row "INFO" "grok-search.user_mcp" "user mcp.json wrapper present (optional; plugin-chain TUI does not need it)"
fi

# --- Cursor-native paths (OPTIONAL dual-path, not required) ---
if [[ -d "$CURSOR_LOCAL" ]]; then
  local_count=$(find "$CURSOR_LOCAL" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l | tr -d ' ')
  row "OPTIONAL" "cursor.plugins.local" "${local_count} entries (dual-path fallback only)"
else
  row "OPTIONAL" "cursor.plugins.local" "absent — OK if Claude-cache discovery already works"
fi

if [[ -d "${HOME_DIR}/.cursor/plugins" ]]; then
  row "INFO" "cursor.plugins" "directory exists"
else
  row "OPTIONAL" "cursor.plugins" "absent — not a convert failure by itself"
fi

if [[ -d "$CURSOR_SKILLS" ]]; then
  cs=$(find "$CURSOR_SKILLS" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l | tr -d ' ')
  row "INFO" "cursor.user_skills" "${cs} entries under ~/.cursor/skills"
else
  row "INFO" "cursor.user_skills" "no ~/.cursor/skills"
fi

# --- Marketplace registration ---
if command -v agent >/dev/null 2>&1; then
  mkt=$(agent plugin marketplace list 2>/dev/null || true)
  if echo "$mkt" | grep -q 'karlorz-agent-skills'; then
    row "PASS" "marketplace.karlorz-agent-skills" "registered (≠ Cursor-native install)"
  else
    row "INFO" "marketplace.karlorz-agent-skills" "not listed"
  fi
  if echo "$mkt" | grep -q 'llm-wiki'; then
    row "PASS" "marketplace.llm-wiki" "registered (≠ Cursor-native install)"
  else
    row "INFO" "marketplace.llm-wiki" "not listed"
  fi
else
  row "INFO" "agent.cli" "agent binary not on PATH"
fi

echo
echo "Summary: PASS=${pass}  INFO=${info}  OPTIONAL=${optional}  WARN=${warn}  FAIL=${fail}"
echo
if [[ "$fail" -eq 0 ]]; then
  echo "Verdict: Claude plugin cache / enabledPlugins look healthy."
else
  echo "Verdict: FAIL rows need investigation before any dual-path links."
fi

# Footer / Operator instructions
if [[ "$stale_cursor_pack" -eq 1 ]]; then
  echo
  echo "Catalog-refresh reminder: Cursor SkillWiki pack snapshot is stale."
  echo "Team marketplace refresh path: Dashboard → Plugins → karlorz/llm-wiki → Refresh or Enable Auto Refresh."
  echo "Reinstalling does not move the snapshot. Do not write local files."
else
  echo
  echo "Catalog-refresh reminder: If updating marketplace plugins in Cursor Team,"
  echo "navigate to Dashboard → Plugins → [plugin] → Refresh or Enable Auto Refresh."
fi

echo
# ln-withhold rule
if [[ "$claude_settings_ok" -eq 1 && "$skillwiki_cache_ok" -eq 1 && -d "$AGENT_SKILLS_CACHE" ]]; then
  echo "Suggested dual-path links are withheld by default (Claude discovery healthy; no convert needed)."
else
  echo "Suggested dual-path links are available only when Claude settings/cache discovery fails."
fi

exit 0
