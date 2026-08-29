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
skills_unresolved=0
enabled=()

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
catalog_git_ref=""
catalog_scope=""
mkt_has_llm_wiki=0
mkt_has_agent_skills=0
catalog_agent=""
if [[ -n "${CURSOR_AGENT_BIN:-}" ]]; then
  catalog_agent="$CURSOR_AGENT_BIN"
elif command -v cursor-agent >/dev/null 2>&1; then
  catalog_agent="cursor-agent"
elif command -v agent >/dev/null 2>&1; then
  catalog_agent="agent"
fi

if [[ -n "$catalog_agent" ]] && command -v python3 >/dev/null 2>&1; then
  while IFS=$'\t' read -r mkt_name mkt_ref mkt_scope; do
    [[ -z "$mkt_name" ]] && continue
    case "$mkt_name" in
      llm-wiki)
        catalog_git_ref="$mkt_ref"
        catalog_scope="$mkt_scope"
        mkt_has_llm_wiki=1
        ;;
      karlorz-agent-skills)
        mkt_has_agent_skills=1
        ;;
    esac
  done < <("$catalog_agent" plugin marketplace list --format json 2>/dev/null | python3 -c '
import json,sys
try:
    rows=json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for row in rows if isinstance(rows, list) else []:
    if not isinstance(row, dict):
        continue
    name=row.get("name") or ""
    if name in ("llm-wiki", "karlorz-agent-skills"):
        print("%s\t%s\t%s" % (name, row.get("gitRef") or "", row.get("scope") or ""))
' 2>/dev/null || true)
fi

if [[ -d "$CURSOR_MKT_ROOT" ]]; then
  latest_cmkt=""
  if [[ -n "$catalog_git_ref" && -d "${CURSOR_MKT_ROOT}/${catalog_git_ref}" ]]; then
    latest_cmkt="${CURSOR_MKT_ROOT}/${catalog_git_ref}"
  else
    latest_cmkt=$(ls -d "${CURSOR_MKT_ROOT}"/*/ 2>/dev/null | sort | tail -1 || true)
    latest_cmkt="${latest_cmkt%/}"
  fi
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

# --- Cursor one-level skills discoverability for every enabled Claude plugin ---
# Cursor scans immediate children of plugin.json "skills" (default ./skills/).
# skills="./" with only nested skills/<name>/SKILL.md is skipped on import.
if command -v python3 >/dev/null 2>&1 && (( ${#enabled[@]} > 0 )); then
  while IFS=$'\t' read -r status name detail; do
    [[ -n "${status:-}" ]] || continue
    row "$status" "$name" "$detail"
    if [[ "$status" == "WARN" && "$name" == "plugin.skills_unresolved" ]]; then
      skills_unresolved=$((skills_unresolved + 1))
    fi
  done < <(python3 - "$HOME_DIR" "${enabled[@]}" <<'PY'
import json, sys
from pathlib import Path

home = Path(sys.argv[1])
enabled = sys.argv[2:]
cache_root = home / ".claude" / "plugins" / "cache"
mkt_root = home / ".claude" / "plugins" / "marketplaces"
installed_path = home / ".claude" / "plugins" / "installed_plugins.json"
installed = {}
if installed_path.is_file():
    try:
        blob = json.loads(installed_path.read_text(encoding="utf-8"))
        for key, recs in (blob.get("plugins") or {}).items():
            if recs and isinstance(recs, list) and recs[0].get("installPath"):
                installed[key] = Path(recs[0]["installPath"])
    except Exception:
        pass


def skill_dirs_at(base: Path):
    if not base.is_dir():
        return []
    names = []
    for child in sorted(base.iterdir()):
        if child.is_dir() and (child / "SKILL.md").is_file():
            names.append(child.name)
    return names


def latest_version_dir(plugin_cache: Path):
    if not plugin_cache.is_dir():
        return None
    versions = [p for p in plugin_cache.iterdir() if p.is_dir() and not p.name.startswith(".")]
    if not versions:
        return None
    def key(p):
        parts = []
        for bit in p.name.replace("-", ".").split("."):
            parts.append(int(bit) if bit.isdigit() else bit)
        return parts
    try:
        return sorted(versions, key=key)[-1]
    except Exception:
        return sorted(versions, key=lambda p: p.name)[-1]


def marketplace_skills_field(marketplace: str, plugin: str):
    root = mkt_root / marketplace
    mfile = root / ".claude-plugin" / "marketplace.json"
    source = None
    if mfile.is_file():
        try:
            data = json.loads(mfile.read_text(encoding="utf-8"))
            for entry in data.get("plugins") or []:
                if isinstance(entry, dict) and entry.get("name") == plugin:
                    source = entry.get("source")
                    break
        except Exception:
            source = None
    if not source:
        nested = root / "skills" / plugin / ".claude-plugin" / "plugin.json"
        if nested.is_file():
            try:
                return json.loads(nested.read_text(encoding="utf-8")).get("skills")
            except Exception:
                return None
        return None
    src_path = (root / source).resolve()
    pj = src_path / ".claude-plugin" / "plugin.json"
    if pj.is_file():
        try:
            return json.loads(pj.read_text(encoding="utf-8")).get("skills")
        except Exception:
            return None
    return None


def emit(status, name, detail):
    print(f"{status}\t{name}\t{detail}")


for key in enabled:
    if "@" not in key:
        continue
    plugin, marketplace = key.split("@", 1)
    plugin_root = installed.get(key)
    if plugin_root is None:
        plugin_root = latest_version_dir(cache_root / marketplace / plugin)
    if plugin_root is None or not plugin_root.is_dir():
        emit("INFO", f"plugin.cache.{plugin}", f"{key} enabled but no cache dir")
        continue
    pj = plugin_root / ".claude-plugin" / "plugin.json"
    declared = None
    if pj.is_file():
        try:
            declared = json.loads(pj.read_text(encoding="utf-8")).get("skills")
        except Exception:
            declared = None
    if not isinstance(declared, str) or not declared.strip():
        at_skills = skill_dirs_at(plugin_root / "skills")
        at_root = skill_dirs_at(plugin_root)
        if at_skills or at_root:
            loc = "./skills/" if at_skills else "./"
            found = at_skills or at_root
            emit("PASS", f"plugin.skills.{plugin}", f"{key} default {loc} -> {','.join(found)}")
        else:
            emit("INFO", f"plugin.skills.{plugin}", f"{key} has no skills component")
        continue
    rel = declared[2:] if declared.startswith("./") else declared
    rel = rel.rstrip("/") or "."
    scan = plugin_root if rel in (".", "") else plugin_root / rel
    found = skill_dirs_at(scan)
    nested = skill_dirs_at(plugin_root / "skills")
    if found:
        emit("PASS", f"plugin.skills.{plugin}", f"{key} {declared} -> {','.join(found)}")
    elif nested:
        emit(
            "WARN",
            "plugin.skills_unresolved",
            f"{key} skills={declared!r} has no SKILL.md one level under that path; "
            f"Cursor import skips it. Nested skills/ has {','.join(nested)}. "
            f"Reinstall/update the Claude plugin cache (do not convert/symlink).",
        )
    else:
        emit("INFO", f"plugin.skills.{plugin}", f"{key} skills={declared!r} but no SKILL.md found")

    mkt_skills = marketplace_skills_field(marketplace, plugin)
    if (
        isinstance(mkt_skills, str)
        and isinstance(declared, str)
        and mkt_skills.rstrip("/") != declared.rstrip("/")
    ):
        emit(
            "WARN",
            "plugin.cache_stale",
            f"{key} cache skills={declared!r} != marketplace source {mkt_skills!r}; "
            f"reinstall/update Claude plugin so Cursor can import",
        )
PY
)
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

# --- Marketplace registration (same JSON list as catalog gitRef) ---
if [[ -n "$catalog_agent" ]]; then
  if [[ "$mkt_has_agent_skills" -eq 1 ]]; then
    row "PASS" "marketplace.karlorz-agent-skills" "registered (≠ Cursor-native install)"
  else
    row "INFO" "marketplace.karlorz-agent-skills" "not listed"
  fi
  if [[ "$mkt_has_llm_wiki" -eq 1 ]]; then
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
if [[ "$fail" -eq 0 && "$skills_unresolved" -gt 0 ]]; then
  echo "Verdict: Claude plugin cache exists, but Cursor import will skip ${skills_unresolved} plugin(s) with unresolved skills paths. Reinstall/update those Claude plugins."
elif [[ "$fail" -eq 0 ]]; then
  echo "Verdict: Claude plugin cache / enabledPlugins look healthy."
else
  echo "Verdict: FAIL rows need investigation before any dual-path links."
fi

# Footer / Operator instructions
echo
if [[ "$stale_cursor_pack" -eq 1 ]]; then
  echo "Catalog-refresh reminder: Cursor SkillWiki pack snapshot is stale."
  echo "Reinstalling does not move the snapshot. Do not write local cache files while the catalog pin is still old."
else
  echo "Catalog-refresh reminder: Cursor CLI does not auto-update marketplace plugins."
fi
case "$catalog_scope" in
  team)
    echo "Team marketplace admin row: Dashboard → Plugins → Refresh or Enable Auto Refresh."
    ;;
  *)
    echo "User GitHub adds (scope=user for llm-wiki / karlorz-agent-skills): run cursor-github-marketplace-repin scripts/status.sh, then remove+add --git-ref if STALE."
    ;;
esac

echo
# ln-withhold rule
if [[ "$claude_settings_ok" -eq 1 && "$skillwiki_cache_ok" -eq 1 && -d "$AGENT_SKILLS_CACHE" ]]; then
  echo "Suggested dual-path links are withheld by default (Claude discovery healthy; no convert needed)."
else
  echo "Suggested dual-path links are available only when Claude settings/cache discovery fails."
fi

if [[ "$skills_unresolved" -gt 0 ]]; then
  echo
  echo "Cursor import skip: ${skills_unresolved} enabled plugin(s) declare a skills path with no SKILL.md one level down."
  echo "Fix: reinstall/update that plugin in Claude Code so cache plugin.json uses \"./skills/\" (or flatten SKILL.md to the declared path)."
  echo "Do not convert or symlink into ~/.cursor/plugins/local for this packaging skip."
fi

exit 0
