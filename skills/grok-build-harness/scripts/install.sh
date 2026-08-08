#!/usr/bin/env bash
# grok-build-harness — fresh-host bootstrap for the karlorz subagent harness.
#
# Installs into $GROK_HOME (default ~/.grok):
#   agents/grok-build-byok.md, agents/scout.md   custom subagents (verbatim)
#   agentrules.md                                 global routing rules (verbatim)
#   AGENTS.md                                     subagent contract (skillwiki marker preserved)
#   config.toml                                   rendered from the sanitized template
#
# Then adds the companion marketplaces and installs the plugin set with
# --trust, honoring the skip flags. Backup-first and idempotent: existing
# files are copied to $GROK_HOME/backups/grok-build-harness-<timestamp>/ and
# identical files are left untouched.
#
# Usage:
#   install.sh [--grok-home DIR] [--hub-key K] [--new-key K] [--context7-key K]
#              [--skip-codex] [--skip-vault-sync] [--skip-playwright-cli]
#              [--skip-plugins] [--no-config] [--dry-run] [--force] [--verify] [-y]
#
# Keys can also come from HARNESS_HUB_KEY / HARNESS_NEW_KEY / HARNESS_CONTEXT7_KEY.
# Everything is testable against a scratch tree: GROK_HOME=/tmp/grok-home ./install.sh --dry-run

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
ASSETS="$PLUGIN_ROOT/assets"
GENERATE="$HERE/generate-config.py"

# --- options -----------------------------------------------------------------
GROK_HOME="${GROK_HOME:-$HOME/.grok}"
HUB_KEY="${HARNESS_HUB_KEY:-}"
NEW_KEY="${HARNESS_NEW_KEY:-}"
CONTEXT7_KEY="${HARNESS_CONTEXT7_KEY:-}"
SKIP_CODEX=0
SKIP_VAULT_SYNC=0
SKIP_PLAYWRIGHT=0
SKIP_PLUGINS=0
NO_CONFIG=0
DRY_RUN=0
FORCE=0
VERIFY=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
grok-build-harness — fresh-host bootstrap for the karlorz subagent harness.
Installs agents, rules, and a sanitized config into $GROK_HOME (default ~/.grok),
then adds companion marketplaces and installs the plugin set with --trust.

Usage:
  install.sh [--grok-home DIR] [--hub-key K] [--new-key K] [--context7-key K]
             [--skip-codex] [--skip-vault-sync] [--skip-playwright-cli]
             [--skip-plugins] [--no-config] [--dry-run] [--force] [--verify] [-y]

Options:
  --grok-home DIR        target grok home (default: $GROK_HOME or ~/.grok)
  --hub-key K            hub.karldigi.dev API key (or HARNESS_HUB_KEY)
  --new-key K            new.karldigi.dev API key (or HARNESS_NEW_KEY)
  --context7-key K       context7 MCP API key (or HARNESS_CONTEXT7_KEY)
  --skip-codex           do not install/enable the codex plugin
  --skip-vault-sync      do not install/enable the vault-sync plugin
  --skip-playwright-cli  do not install/enable the playwright-cli plugin
  --skip-plugins         files + config only; no marketplace/plugin steps
  --no-config            do not touch config.toml
  --dry-run              print the plan; write nothing
  --force                overwrite existing files without prompting
  --verify               run verification after installing
  -y                     assume yes for all prompts
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --grok-home) GROK_HOME="$2"; shift 2 ;;
    --hub-key) HUB_KEY="$2"; shift 2 ;;
    --new-key) NEW_KEY="$2"; shift 2 ;;
    --context7-key) CONTEXT7_KEY="$2"; shift 2 ;;
    --skip-codex) SKIP_CODEX=1; shift ;;
    --skip-vault-sync) SKIP_VAULT_SYNC=1; shift ;;
    --skip-playwright-cli) SKIP_PLAYWRIGHT=1; shift ;;
    --skip-plugins) SKIP_PLUGINS=1; shift ;;
    --no-config) NO_CONFIG=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    --verify) VERIFY=1; shift ;;
    -y) ASSUME_YES=1; shift ;;
    -h|--help) usage ;;
    *) echo "install.sh: unknown option: $1" >&2; usage ;;
  esac
done

GROK_HOME="$(cd "$GROK_HOME" 2>/dev/null && pwd || printf '%s' "$GROK_HOME")"
BACKUP_DIR="$GROK_HOME/backups/grok-build-harness-$(date +%Y%m%d%H%M%S)"

# name|source|skip-flag-name — one table drives both the enabled list and the
# install loop, so the two can never drift apart. SKIP_NONE is always 0.
SKIP_NONE=0
PLUGIN_SPECS=(
  "superpowers|superpowers@anthropics/claude-plugins-official|SKIP_NONE"
  "simplify|simplify|SKIP_NONE"
  "deep-research|deep-research|SKIP_NONE"
  "dev-loop|dev-loop|SKIP_NONE"
  "claude-md-management|claude-md-management@karlorz/agent-skills|SKIP_NONE"
  "grill-me|grill-me|SKIP_NONE"
  "codebase-architecture|codebase-architecture|SKIP_NONE"
  "hermes-cli|hermes-cli|SKIP_NONE"
  "skillwiki|karlorz/llm-wiki#packages/skills|SKIP_NONE"
  "context7|context7|SKIP_NONE"
  "vault-sync|karlorz/llm-wiki#packages/vault-sync|SKIP_VAULT_SYNC"
  "codex|openai/codex-plugin-cc#plugins/codex|SKIP_CODEX"
  "playwright-cli|playwright-cli|SKIP_PLAYWRIGHT"
)

ENABLED=()
for spec in "${PLUGIN_SPECS[@]}"; do
  IFS='|' read -r name _source flag_name <<< "$spec"
  [ "${!flag_name}" -eq 1 ] || ENABLED+=("$name")
done

log()  { printf 'grok-build-harness: %s\n' "$*"; }
warn() { printf 'grok-build-harness: WARNING: %s\n' "$*" >&2; }
die()  { printf 'grok-build-harness: ERROR: %s\n' "$*" >&2; exit 1; }

prompt_yes() {
  # $1 = question; returns 0 on yes
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ "$FORCE" -eq 1 ] && return 0
  local answer
  read -r -p "grok-build-harness: $1 [y/N] " answer || return 1
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

copy_if_changed() {
  local src="$1" dst="$2" label="$3"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    log "$label: identical, skipping ($dst)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "$label: would install -> $dst"
    return 0
  fi
  if [ -f "$dst" ] && ! prompt_yes "overwrite existing $dst?"; then
    warn "$label: skipped (kept $dst)"
    return 0
  fi
  if [ -f "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -p "$dst" "$BACKUP_DIR/$(basename "$dst")"
    log "$label: backed up existing file to $BACKUP_DIR"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
  log "$label: installed -> $dst"
}

merge_agents_md() {
  # Keep any skillwiki:begin...end marker block the skillwiki plugin owns;
  # replace the rest of ~/.grok/AGENTS.md with the bundled subagent contract.
  # The merged result goes through copy_if_changed so identical/dry-run/
  # prompt/backup behavior is identical to the plain copies.
  local dst="$GROK_HOME/AGENTS.md"
  local block="" merged tmp
  if [ -f "$dst" ]; then
    block="$(sed -n '/<!-- skillwiki:begin -->/,/<!-- skillwiki:end -->/p' "$dst")"
  fi
  if [ -n "$block" ]; then
    merged="$(printf '%s\n\n%s\n' "$block" "$(cat "$ASSETS/AGENTS.md")")"
  else
    merged="$(cat "$ASSETS/AGENTS.md")"
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/grok-build-harness-agents.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  printf '%s\n' "$merged" > "$tmp"
  copy_if_changed "$tmp" "$dst" "AGENTS.md"
}

render_config() {
  local out="$GROK_HOME/config.toml"
  local args=(--out "$out")
  [ -n "$HUB_KEY" ] && args+=(--hub-key "$HUB_KEY")
  [ -n "$NEW_KEY" ] && args+=(--new-key "$NEW_KEY")
  [ -n "$CONTEXT7_KEY" ] && args+=(--context7-key "$CONTEXT7_KEY")
  args+=(--enabled "$(IFS=,; printf '%s' "${ENABLED[*]}")")

  if [ "$DRY_RUN" -eq 1 ]; then
    log "config.toml: would render from template -> $out (enabled: ${ENABLED[*]})"
    return 0
  fi
  local rendered
  rendered="$(python3 "$GENERATE" --template "$ASSETS/config.toml.template" "${args[@]}")"
  log "config.toml: $rendered"
}

find_grok() {
  if [ -x "$GROK_HOME/bin/grok" ]; then
    printf '%s' "$GROK_HOME/bin/grok"
  elif command -v grok >/dev/null 2>&1; then
    printf '%s' "$(command -v grok)"
  else
    printf '%s' ""
  fi
}

marketplace_add() {
  local url="$1" name="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "marketplace: would add $name ($url)"
    return 0
  fi
  if "$GROK" plugin marketplace list 2>/dev/null | grep -Fq "$url"; then
    log "marketplace: $name already present, skipping"
    return 0
  fi
  "$GROK" plugin marketplace add "$url"
  log "marketplace: added $name"
}

install_plugin() {
  local plugin="$1" source="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "plugin: would install $plugin ($source) --trust"
    return 0
  fi
  if "$GROK" plugin list 2>/dev/null | grep -Fq "$plugin"; then
    log "plugin: $plugin already installed, skipping"
    return 0
  fi
  if ! "$GROK" plugin install "$source" --trust; then
    warn "plugin: $plugin install failed; continuing"
  else
    log "plugin: installed $plugin"
  fi
}

verify() {
  log "verifying install in $GROK_HOME"
  local missing=0
  for f in "agents/grok-build-byok.md" "agents/scout.md" "agentrules.md" "AGENTS.md" "config.toml"; do
    if [ -f "$GROK_HOME/$f" ]; then
      log "  ok  $f"
    else
      warn "  MISSING $f"
      missing=1
    fi
  done
  if [ -f "$GROK_HOME/config.toml" ] && grep -Eq '__[A-Z][A-Z0-9_]*__' "$GROK_HOME/config.toml"; then
    warn "config.toml still contains unresolved key tokens"
    missing=1
  fi
  if [ "$SKIP_PLUGINS" -eq 0 ] && [ -n "$GROK" ]; then
    log "plugins:"
    "$GROK" plugin list --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for entry in data:
    print("  {:8s} {}  v{}".format(entry.get("status", "?"), entry.get("name", "?"), entry.get("version", "?")))
' || "$GROK" plugin list 2>/dev/null | sed 's/^/  /' || true
    "$GROK" inspect --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print("  agents discovered: {}".format(len(data.get("agents", []))))
warnings = data.get("configWarnings", [])
print("  config warnings: {}".format(len(warnings)))
for w in warnings:
    print("    {}: {} {}".format(w.get("kind", "?"), w.get("path", ""), w.get("message", "")))
' || true
  fi
  [ "$missing" -eq 1 ] && warn "verification found problems (see above)"
  log "done. Start a new grok-build session for the harness to take effect."
  return "$missing"
}

# --- plan --------------------------------------------------------------------
log "grok-build-harness v0.1.0 bootstrap"
log "target: $GROK_HOME"
log "plugins: ${ENABLED[*]}"
[ "$DRY_RUN" -eq 1 ] && log "DRY RUN: no writes will be performed"

if [ ! -d "$GROK_HOME" ] && [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$GROK_HOME" || die "cannot create $GROK_HOME"
fi

# keys: prompt for missing ones when interactive
if [ -z "$HUB_KEY" ] && [ -t 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  read -r -s -p "grok-build-harness: hub.karldigi.dev API key (leave empty for env-only): " HUB_KEY; echo
fi
if [ -z "$NEW_KEY" ] && [ -t 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  read -r -s -p "grok-build-harness: new.karldigi.dev API key (leave empty for env-only): " NEW_KEY; echo
fi
if [ -z "$CONTEXT7_KEY" ] && [ -t 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  read -r -s -p "grok-build-harness: context7 MCP API key (leave empty to skip the MCP): " CONTEXT7_KEY; echo
fi

# --- files -------------------------------------------------------------------
log "installing harness files"
mkdir -p "$GROK_HOME/agents"
copy_if_changed "$ASSETS/agents/grok-build-byok.md" "$GROK_HOME/agents/grok-build-byok.md" "agent grok-build-byok"
copy_if_changed "$ASSETS/agents/scout.md"          "$GROK_HOME/agents/scout.md"          "agent scout"
copy_if_changed "$ASSETS/agentrules.md"            "$GROK_HOME/agentrules.md"            "agentrules"
merge_agents_md

if [ "$NO_CONFIG" -eq 0 ]; then
  render_config
fi

# --- plugins -----------------------------------------------------------------
if [ "$SKIP_PLUGINS" -eq 0 ]; then
  GROK="$(find_grok)"
  [ -n "$GROK" ] || die "grok binary not found (looked in $GROK_HOME/bin and PATH); pass --skip-plugins to install files only"

  log "adding marketplaces"
  marketplace_add "https://github.com/karlorz/agent-skills.git" "karlorz-agent-skills"
  marketplace_add "https://github.com/karlorz/llm-wiki.git" "llm-wiki"
  marketplace_add "https://github.com/openai/codex-plugin-cc.git" "openai-codex"
  marketplace_add "https://github.com/anthropics/claude-plugins-official.git" "claude-plugins-official"

  log "installing plugins"
  for spec in "${PLUGIN_SPECS[@]}"; do
    IFS='|' read -r name source flag_name <<< "$spec"
    [ "${!flag_name}" -eq 1 ] || install_plugin "$name" "$source"
  done
else
  log "plugins skipped (--skip-plugins)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry run complete — no changes were made"
  exit 0
fi

[ "$VERIFY" -eq 1 ] && verify
log "bootstrap complete. Start a new session (or press r in the Plugins tab) to load the harness."