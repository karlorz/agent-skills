#!/usr/bin/env bash
# grok-build-harness — fresh-host bootstrap for the karlorz subagent harness.
#
# Installs into $GROK_HOME (default ~/.grok):
#   agents/grok-build-byok.md, agents/scout.md   custom subagents (verbatim)
#   agentrules.md                                 global routing rules (verbatim)
#   AGENTS.md                                     subagent contract (spliced: user content preserved)
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
#              [--skip-plugins] [--no-config] [--dry-run] [--force] [--verify]
#              [--require-keys] [--restrictive] [--force-render]
#              [--with-grokgod] [--skip-grokgod] [-y]
#
# Keys can also come from HARNESS_HUB_KEY / HARNESS_NEW_KEY / HARNESS_CONTEXT7_KEY.
# Everything is testable against a scratch tree: GROK_HOME=/tmp/grok-home ./install.sh --dry-run

set -euo pipefail

ORIGINAL_ARGS=("$@")
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
ASSETS="$PLUGIN_ROOT/assets"
GENERATE="$HERE/generate-config.py"
MERGE="$HERE/merge-agents.py"
CHECK_CONFIG="$HERE/check-config.py"

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
FORCE_RENDER=0
VERIFY=0
STRICT=0
ASSUME_YES=0
REQUIRE_KEYS=0
RESTRICTIVE=0
WITH_GROKGOD=0
SKIP_GROKGOD=0

usage() {
  cat <<'EOF'
grok-build-harness — fresh-host bootstrap for the karlorz subagent harness.
Installs agents, rules, and a sanitized config into $GROK_HOME (default ~/.grok),
then adds companion marketplaces and installs the plugin set with --trust.

Usage:
  install.sh [--grok-home DIR] [--hub-key K] [--new-key K] [--context7-key K]
             [--skip-codex] [--skip-vault-sync] [--skip-playwright-cli]
             [--skip-plugins] [--no-config] [--dry-run] [--force] [--verify]
             [--require-keys] [--restrictive] [--force-render]
             [--with-grokgod] [--skip-grokgod] [--strict] [-y]

Options:
  --grok-home DIR        target grok home (default: $GROK_HOME or ~/.grok)
  --hub-key K            hub.karldigi.dev API key (or HARNESS_HUB_KEY)
  --new-key K            new.karldigi.dev API key (or HARNESS_NEW_KEY)
  --context7-key K       context7 MCP API key (or HARNESS_CONTEXT7_KEY)
  --require-keys         fail when hub/new gateway keys are missing (headless-safe)
  --restrictive          render permission_mode = "plan" instead of "always-approve"
  --force-render         rewrite an existing keyed config env-only when no keys
                         are provided (overrides the downgrade guard)
  --skip-codex           do not install/enable the codex plugin
  --skip-vault-sync      do not install/enable the vault-sync plugin
  --skip-playwright-cli  do not install/enable the playwright-cli plugin
  --skip-plugins         files + config only; no marketplace/plugin steps
  --no-config            do not touch config.toml
  --with-grokgod         force grokgod plan_mode implement_via_subagents merge
  --skip-grokgod         skip grokgod plan_mode merge even if detected
  --strict               fail verify if config has unexpected top-level keys
  --dry-run              print the plan; write nothing
  --force                overwrite existing files without prompting
  --verify               run verification after installing
  -y                     assume yes for all prompts
EOF
  exit 0
}

log()  { printf 'grok-build-harness: %s\n' "$*"; }
warn() { printf 'grok-build-harness: WARNING: %s\n' "$*" >&2; }
die()  { printf 'grok-build-harness: ERROR: %s\n' "$*" >&2; exit 1; }

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
    --force-render) FORCE_RENDER=1; shift ;;
    --verify) VERIFY=1; shift ;;
    --strict) STRICT=1; shift ;;
    --require-keys) REQUIRE_KEYS=1; shift ;;
    --restrictive) RESTRICTIVE=1; shift ;;
    --with-grokgod) WITH_GROKGOD=1; SKIP_GROKGOD=0; shift ;;
    --skip-grokgod) SKIP_GROKGOD=1; WITH_GROKGOD=0; shift ;;
    -y) ASSUME_YES=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown option: $1 (run with --help)" ;;
  esac
done

GROK_HOME="$(cd "$GROK_HOME" 2>/dev/null && pwd || printf '%s' "$GROK_HOME")"
# export so grok CLI subprocesses (marketplace add, plugin install, verify)
# target the same home as the files we install — --grok-home must behave
# exactly like the GROK_HOME env var
export GROK_HOME
BACKUP_DIR="$GROK_HOME/backups/grok-build-harness-$(date +%Y%m%d%H%M%S)"
PERMISSION_MODE="always-approve"
[ "$RESTRICTIVE" -eq 1 ] && PERMISSION_MODE="plan"

# name|source|skip-flag-name — one table drives both the enabled list and the
# install loop, so the two can never drift apart. SKIP_NONE is always 0.
SKIP_NONE=0
PLUGIN_SPECS=(
  "grok-build-harness|grok-build-harness|SKIP_NONE"
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
  # Splice the harness-owned contract into ~/.grok/AGENTS.md while preserving
  # everything else — user content and the llm-wiki skillwiki marker survive
  # (ADR-1). The asset is a marked block; v0.2.0 files with an unmarked
  # contract get a one-time block-match migration (ADR-2). The merged result
  # goes through copy_if_changed so identical/dry-run/prompt/backup behavior
  # is identical to the plain copies.
  local dst="$GROK_HOME/AGENTS.md" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/grok-build-harness-agents.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  if [ -f "$dst" ]; then
    python3 "$MERGE" "$ASSETS/AGENTS.md" "$dst" > "$tmp"
  else
    cp "$ASSETS/AGENTS.md" "$tmp"
  fi
  copy_if_changed "$tmp" "$dst" "AGENTS.md"
}

config_has_injected_keys() {
  # true when the config carries inline secrets — [model.*] api_key lines or
  # a context7 --api-key arg. Rewriting such a config env-only would silently
  # degrade it, so keyless re-runs skip the render instead (ADR-4).
  grep -Eq '^[[:space:]]*api_key[[:space:]]*=' "$1" || grep -Fq '"--api-key"' "$1"
}

render_config() {
  # Render to a temp file, then reuse copy_if_changed: identical configs are
  # skipped, user-modified configs are backed up before overwrite, and
  # --dry-run prints without writing — same semantics as every other file.
  local out="$GROK_HOME/config.toml"
  local tmp args
  tmp="$(mktemp "${TMPDIR:-/tmp}/grok-build-harness-config.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  # keyed-config downgrade guard: never silently replace a config that has
  # injected keys with an env-only render when this run provides no key at
  # all — skip the render and keep the working config (ADR-4)
  if [ "$FORCE_RENDER" -eq 0 ] && [ -f "$out" ] \
     && [ -z "$HUB_KEY" ] && [ -z "$NEW_KEY" ] && [ -z "$CONTEXT7_KEY" ] \
     && config_has_injected_keys "$out"; then
    warn "existing $out has injected keys but this run provides none — skipping config render to avoid an env-only downgrade"
    warn "re-run with --hub-key/--new-key/--context7-key (or HARNESS_* env), or pass --force-render to rewrite env-only"
    return 0
  fi
  args=(--out "$tmp")
  [ -n "$HUB_KEY" ] && args+=(--hub-key "$HUB_KEY")
  [ -n "$NEW_KEY" ] && args+=(--new-key "$NEW_KEY")
  [ -n "$CONTEXT7_KEY" ] && args+=(--context7-key "$CONTEXT7_KEY")
  args+=(--permission-mode "$PERMISSION_MODE")
  args+=(--enabled "$(IFS=,; printf '%s' "${ENABLED[*]}")")
  # keep host-set config state the template does not emit (marketplace
  # sources, [plugins].disabled, extra tables): re-rendering from the
  # template alone would drop them and churn config on every re-run
  [ -f "$out" ] && args+=(--preserve "$out")
  python3 "$GENERATE" --template "$ASSETS/config.toml.template" "${args[@]}" >/dev/null
  copy_if_changed "$tmp" "$out" "config.toml"
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

grokgod_detected() {
  if [ "$WITH_GROKGOD" -eq 1 ]; then
    return 0
  fi
  if [ "$SKIP_GROKGOD" -eq 1 ]; then
    return 1
  fi
  if command -v grokgod >/dev/null 2>&1 \
     || [ -x "$HOME/.grokgod/bin/grok" ] \
     || [ -f "$HOME/.grokgod/.source-version" ]; then
    return 0
  fi
  return 1
}

merge_grokgod_plan_mode() {
  local cfg="$GROK_HOME/config.toml"
  if ! grokgod_detected; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "plan_mode: would merge implement_via_subagents = true into $cfg"
    return 0
  fi
  if [ ! -f "$cfg" ]; then
    return 0
  fi
  if grep -q '^[[:space:]]*implement_via_subagents[[:space:]]*=' "$cfg" 2>/dev/null; then
    log "plan_mode: implement_via_subagents already set in $cfg"
    return 0
  fi
  if grep -q '^[[:space:]]*\[plan_mode\]' "$cfg"; then
    local tmp
    tmp="$(mktemp "$cfg.plan-mode.XXXXXX")"
    trap 'rm -f "$tmp"' RETURN
    awk '
      BEGIN { added=0 }
      /^[[:space:]]*\[plan_mode\]/ && added==0 {
        print
        print "implement_via_subagents = true"
        added=1
        next
      }
      { print }
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    trap - RETURN
    log "plan_mode: merged implement_via_subagents = true into existing [plan_mode] in $cfg"
    return 0
  fi
  {
    if [ -s "$cfg" ]; then
      printf '\n'
    fi
    printf '[plan_mode]\nimplement_via_subagents = true\n'
  } >> "$cfg"
  log "plan_mode: wrote [plan_mode] implement_via_subagents = true to $cfg"
}

write_stamp() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "stamp: would write $GROK_HOME/.grok-build-harness-stamp.json"
    return 0
  fi
  local stamp_file="$GROK_HOME/.grok-build-harness-stamp.json"
  local plugin_version="unknown"
  if [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
    plugin_version="$(python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print(data.get("version", "unknown"))
except Exception:
    print("unknown")
' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  fi
  local is_grokgod="false"
  if grokgod_detected; then
    is_grokgod="true"
  fi
  local installed_at
  installed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")"
  python3 -c '
import json, sys
stamp = {
    "schema": "grok-build-harness-stamp/v1",
    "plugin_version": sys.argv[1],
    "plugin_root": sys.argv[2],
    "installed_at": sys.argv[3],
    "grokgod_detected": sys.argv[4] == "true"
}
with open(sys.argv[5], "w", encoding="utf-8") as f:
    json.dump(stamp, f, indent=2)
    f.write("\n")
' "$plugin_version" "$PLUGIN_ROOT" "$installed_at" "$is_grokgod" "$stamp_file"
  log "stamp: wrote $stamp_file"
}

maybe_refresh_plugin() {
  # only when running from an installed plugin dir and not in dry-run / skip-plugins
  if [ "$SKIP_PLUGINS" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if [ -n "${HARNESS_REFRESHED:-}" ]; then
    return 0
  fi
  if [[ "$HERE" != *"/installed-plugins/"* ]]; then
    return 0
  fi
  local grok_bin
  grok_bin="$(find_grok)"
  if [ -z "$grok_bin" ]; then
    return 0
  fi
  log "plugin refresh: checking for grok-build-harness updates via grok plugin update"
  if ! "$grok_bin" plugin update grok-build-harness 2>&1; then
    warn "plugin update grok-build-harness failed; continuing with current version"
  fi

  local new_install
  new_install="$(find "$GROK_HOME/installed-plugins" -maxdepth 3 -type f -name install.sh -path '*grok-build-harness*' 2>/dev/null | head -1 || true)"
  if [ -n "$new_install" ] && [ -f "$new_install" ] && ! [ "$new_install" -ef "$HERE/install.sh" ]; then
    log "re-executing updated installer from $new_install"
    export HARNESS_REFRESHED=1
    exec bash "$new_install" "${ORIGINAL_ARGS[@]}"
  fi
}

marketplace_add() {
  local url="$1" name="$2" sources
  if [ "$DRY_RUN" -eq 1 ]; then
    log "marketplace: would add $name ($url)"
    return 0
  fi
  sources="$("$GROK" plugin marketplace list 2>/dev/null || true)"
  if [[ "$sources" == *"$url"* ]]; then
    log "marketplace: $name already present, skipping"
    return 0
  fi
  "$GROK" plugin marketplace add "$url"
  log "marketplace: added $name"
}

install_plugin() {
  local plugin="$1" source="$2" list
  if [ "$DRY_RUN" -eq 1 ]; then
    log "plugin: would install $plugin ($source) --trust"
    return 0
  fi
  # capture first, then match in-shell: grep -q on a live pipe closes it early
  # and makes grok abort on SIGPIPE
  list="$("$GROK" plugin list 2>/dev/null || true)"
  if [[ "$list" == *": $plugin ["* ]]; then
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
  local stamp_file="$GROK_HOME/.grok-build-harness-stamp.json"
  if [ -f "$stamp_file" ]; then
    log "stamp file ($stamp_file):"
    python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print("  schema:           {}".format(data.get("schema", "?")))
    print("  plugin_version:   {}".format(data.get("plugin_version", "?")))
    print("  installed_at:     {}".format(data.get("installed_at", "?")))
    print("  grokgod_detected: {}".format(data.get("grokgod_detected", False)))
    print("  plugin_root:      {}".format(data.get("plugin_root", "?")))
except Exception as e:
    print("  invalid stamp: {}".format(e))
' "$stamp_file" || true
  else
    log "stamp file: not found"
  fi

  for f in "agents/grok-build-byok.md" "agents/scout.md" "agentrules.md" "AGENTS.md" "config.toml"; do
    if [ -f "$GROK_HOME/$f" ]; then
      log "  ok  $f"
    else
      warn "  MISSING $f"
      missing=1
    fi
  done
  if [ -f "$GROK_HOME/config.toml" ]; then
    # the template's comment header documents the token names; only
    # non-comment lines may carry unresolved tokens
    if grep -vE '^[[:space:]]*#' "$GROK_HOME/config.toml" | grep -Eq '__[A-Z][A-Z0-9_]*__'; then
      warn "config.toml still contains unresolved key tokens"
      missing=1
    fi

    # Check for incompatible codex agent_type when grok-build-byok is configured
    local byok_agent=0
    if grep -vE '^[[:space:]]*#' "$GROK_HOME/config.toml" | grep -Eq '^[[:space:]]*name[[:space:]]*=[[:space:]]*"grok-build-byok"'; then
      byok_agent=1
    fi
    if [ "$byok_agent" -eq 1 ]; then
      if grep -vE '^[[:space:]]*#' "$GROK_HOME/config.toml" | grep -Eq '^[[:space:]]*agent_type[[:space:]]*=[[:space:]]*"codex"'; then
        warn "config.toml pairs [agent] name = \"grok-build-byok\" with agent_type = \"codex\" — codex strict harness blocks byok parent; remove agent_type = \"codex\""
      fi
    fi

    if grokgod_detected; then
      if ! grep -vE '^[[:space:]]*#' "$GROK_HOME/config.toml" | grep -Eq '^[[:space:]]*implement_via_subagents[[:space:]]*=[[:space:]]*true'; then
        warn "grokgod is detected but [plan_mode] implement_via_subagents = true is missing in config.toml"
        missing=1
      else
        log "  ok  plan_mode.implement_via_subagents = true"
      fi
    fi

    # Schema-check config.toml across template, docs-known, and runtime extras layers
    local check_args=(--config "$GROK_HOME/config.toml" --grok-home "$GROK_HOME")
    [ "$STRICT" -eq 1 ] && check_args+=(--strict)
    if grokgod_detected; then
      check_args+=(--grokgod)
    fi
    if ! python3 "$CHECK_CONFIG" "${check_args[@]}"; then
      warn "config.toml schema check failed"
      missing=1
    else
      log "  ok  config.toml schema check"
    fi
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
    # assert every enabled plugin actually landed — a failed install must
    # surface here, not just in a warning
    local expected name _src flag_name
    expected=()
    for spec in "${PLUGIN_SPECS[@]}"; do
      IFS='|' read -r name _src flag_name <<< "$spec"
      [ "${!flag_name}" -eq 1 ] || expected+=("$name")
    done
    local missing_plugins
    missing_plugins="$(
      "$GROK" plugin list --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
installed = {entry.get("name") for entry in data}
expected = sys.argv[1:]
print("\n".join(sorted(name for name in expected if name not in installed)))
' "${expected[@]}"
    )"
    if [ -n "$missing_plugins" ]; then
      while IFS= read -r name; do
        warn "  PLUGIN MISSING: $name"
      done <<< "$missing_plugins"
      missing=1
    fi
    local inspect_json
    inspect_json="$("$GROK" inspect --json 2>/dev/null || true)"
    if [ -n "$inspect_json" ]; then
      local inspect_meta
      inspect_meta="$(python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("found=false")
    print("agents=0")
    print("warns=0")
    sys.exit(0)
found = any(
    a.get("name") == "grok-build-byok" and a.get("source", {}).get("type") == "user"
    for a in data.get("agents", [])
)
print("found=" + ("true" if found else "false"))
print("agents=" + str(len(data.get("agents", []))))
print("warns=" + str(len(data.get("configWarnings") or [])))
' "$inspect_json")"
      local found=false agents=0 warns=0
      eval "$inspect_meta"
      if [ "$found" = "true" ]; then
        log "  ok  user agent grok-build-byok discovered"
      else
        warn "  AGENT MISSING: grok-build-byok user agent not found in grok inspect"
        missing=1
      fi
      log "  agents discovered: $agents"
      log "  config warnings: $warns"
      classify_args=(--grok-home "$GROK_HOME" --classify-inspect -)
      if grokgod_detected; then
        classify_args+=(--grokgod)
      fi
      printf '%s\n' "$inspect_json" | python3 "$CHECK_CONFIG" "${classify_args[@]}" 2>/dev/null | sed 's/^/    /' || true
    fi
    # the pin aliases are load-bearing: [subagents.models] resolves through
    # them, so a missing alias breaks the whole routing economy
    local models alias found
    models="$("$GROK" models 2>/dev/null || true)"
    for alias in sonnet haiku deepseek-v4-flash; do
      found=0
      while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]*"$alias"([[:space:]]|$) ]]; then
          found=1
        fi
      done <<< "$models"
      if [ "$found" -eq 1 ]; then
        log "  model ok    $alias"
      else
        warn "  MODEL MISSING: $alias (pin aliases must resolve)"
        missing=1
      fi
    done
  fi
  [ "$missing" -eq 1 ] && warn "verification found problems (see above)"
  log "done. Start a new grok-build session for the harness to take effect."
  return "$missing"
}

# --- plan --------------------------------------------------------------------
maybe_refresh_plugin

log "grok-build-harness bootstrap"
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

# warn loudly when gateway keys are missing; --require-keys hard-fails.
# context7 stays optional (it only feeds the MCP server).
if [ -z "$HUB_KEY" ] || [ -z "$NEW_KEY" ]; then
  missing_keys=""
  [ -z "$HUB_KEY" ] && missing_keys="$missing_keys HUB(hub.karldigi.dev)"
  [ -z "$NEW_KEY" ] && missing_keys="$missing_keys NEW(new.karldigi.dev)"
  warn "gateway keys missing:$missing_keys — config will be env-only and model aliases won't resolve until keys are provided"
  warn "pass --hub-key/--new-key or export HARNESS_HUB_KEY/HARNESS_NEW_KEY; use --require-keys to fail instead of continuing"
  [ "$REQUIRE_KEYS" -eq 1 ] && die "--require-keys: hub/new gateway keys are required"
fi
if [ -z "$CONTEXT7_KEY" ]; then
  warn "context7 key missing — MCP server will launch without --api-key and may fail at runtime"
fi

# --- files -------------------------------------------------------------------
log "installing harness files"
copy_if_changed "$ASSETS/agents/grok-build-byok.md" "$GROK_HOME/agents/grok-build-byok.md" "agent grok-build-byok"
copy_if_changed "$ASSETS/agents/scout.md"          "$GROK_HOME/agents/scout.md"          "agent scout"
copy_if_changed "$ASSETS/agentrules.md"            "$GROK_HOME/agentrules.md"            "agentrules"
merge_agents_md

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

# --- config ------------------------------------------------------------------
# Rendered after the marketplace/plugin steps: `grok plugin marketplace add`
# rewrites config.toml with its own TOML serializer, so rendering last leaves
# our format as the final state and keeps re-runs fully idempotent.
if [ "$NO_CONFIG" -eq 0 ]; then
  render_config
  merge_grokgod_plan_mode
fi

write_stamp

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry run complete — no changes were made"
  exit 0
fi

[ "$VERIFY" -eq 1 ] && verify
log "bootstrap complete. Start a new session (or press r in the Plugins tab) to load the harness."