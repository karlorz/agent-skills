#!/usr/bin/env bash
#
# bump-version.sh — bump a skill's version across its manifests.
#
# A plugin version lives in two or three manifests that must stay in sync:
#   1. skills/<skill>/.claude-plugin/plugin.json              "version": "X.Y.Z"
#   2. skills/<skill>/.codex-plugin/plugin.json               "version": "X.Y.Z" (if present)
#   3. .claude-plugin/marketplace.json          matching plugin entry's "version"
#
# This script reads the current version from .claude-plugin/plugin.json,
# computes the next version, and rewrites all manifest files in place while
# preserving their exact formatting. SKILL.md frontmatter follows the Agent
# Skills schema and must not carry release version fields. This script does
# NOT git add/commit/tag/push — the dev-loop PUSH step owns that. It prints
# the suggested tag in the repo's tag_format ({skill}-{version}, e.g.
# dev-loop-1.20.1).
#
# Usage:
#   scripts/bump-version.sh <skill> [patch|minor|major] [options]
#   scripts/bump-version.sh <skill> --set <X.Y.Z[-beta.N]> [options]
#
# Options:
#   --set <version>   Set an explicit version (skips the computed bump).
#   --dry-run         Print the planned edits; write nothing.
#   -h, --help        Show this help.
#
# Environment:
#   RELEASE_CHANNEL   stable (default) | beta
#     stable: normal X.Y.Z bump; a bump from a -beta.N version strips the
#             prerelease and keeps the bumped base (promote beta -> stable).
#     beta:   from X.Y.Z       -> bump base per level, then -beta.1
#             from X.Y.Z-beta.N -> X.Y.Z-beta.(N+1)  (level ignored, same base)
#
set -euo pipefail

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'
}

die() { printf 'bump-version: %s\n' "$1" >&2; exit 1; }

# --- locate repo root (dir containing .claude-plugin/marketplace.json) -------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

# --- parse args --------------------------------------------------------------
SKILL=""
LEVEL="patch"
SET_VERSION=""
DRY_RUN=0
CHANNEL="${RELEASE_CHANNEL:-stable}"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --set)
      [ $# -ge 2 ] || die "--set requires a version argument"
      SET_VERSION="$2"; shift 2 ;;
    patch|minor|major) LEVEL="$1"; shift ;;
    -*) die "unknown option: $1" ;;
    *)
      if [ -z "$SKILL" ]; then SKILL="$1"; shift
      else die "unexpected argument: $1"; fi ;;
  esac
done

[ -n "$SKILL" ] || { usage >&2; exit 1; }
case "$CHANNEL" in stable|beta) ;; *) die "RELEASE_CHANNEL must be 'stable' or 'beta' (got '$CHANNEL')" ;; esac

# --- resolve manifest paths --------------------------------------------------
SKILL_DIR="$REPO_ROOT/skills/$SKILL"
SKILL_MD="$SKILL_DIR/SKILL.md"
PLUGIN_JSON="$SKILL_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$SKILL_DIR/.codex-plugin/plugin.json"

[ -d "$SKILL_DIR" ]    || die "skill not found: skills/$SKILL/"
[ -f "$SKILL_MD" ]     || die "missing $SKILL_MD"
[ -f "$PLUGIN_JSON" ]  || die "missing $PLUGIN_JSON"
[ -f "$MARKETPLACE" ]  || die "missing $MARKETPLACE"

if [ -f "$CODEX_PLUGIN_JSON" ]; then
  HAS_CODEX_PLUGIN=1
else
  HAS_CODEX_PLUGIN=0
fi

# --- read current versions ---------------------------------------------------
read_plugin_version() {
  awk -F'"' '/"version"[[:space:]]*:/{print $4; exit}' "$PLUGIN_JSON"
}
read_codex_plugin_version() {
  awk -F'"' '/"version"[[:space:]]*:/{print $4; exit}' "$CODEX_PLUGIN_JSON"
}
read_market_version() {
  awk -v name="$SKILL" '
    $0 ~ "\"name\"[[:space:]]*:[[:space:]]*\"" name "\"" {inb=1}
    inb && /"version"[[:space:]]*:/ {
      n=split($0,a,"\""); print a[4]; exit
    }' "$MARKETPLACE"
}

CUR="$(read_plugin_version)"
[ -n "$CUR" ] || die "could not read current version from $PLUGIN_JSON"
P_CUR="$(read_plugin_version)"
M_CUR="$(read_market_version)"
[ -n "$M_CUR" ] || die "no marketplace.json entry for plugin '$SKILL'"
if [ "$HAS_CODEX_PLUGIN" -eq 1 ]; then
  C_CUR="$(read_codex_plugin_version)"
else
  C_CUR=""
fi

# --- pre-check: warn on pre-existing drift -----------------------------------
if [ "$HAS_CODEX_PLUGIN" -eq 1 ] && [ "$C_CUR" != "$CUR" ]; then
  printf 'bump-version: WARNING .codex-plugin/plugin.json (%s) != .claude-plugin/plugin.json (%s) before bump\n' "$C_CUR" "$CUR" >&2
fi
if [ "$M_CUR" != "$CUR" ]; then
  printf 'bump-version: WARNING marketplace.json (%s) != .claude-plugin/plugin.json (%s) before bump\n' "$M_CUR" "$CUR" >&2
fi

# --- semver validation -------------------------------------------------------
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'
validate_semver() {
  printf '%s' "$1" | grep -Eq "$SEMVER_RE" || die "not a valid version: '$1' (want X.Y.Z or X.Y.Z-beta.N)"
}
validate_semver "$CUR"

# --- compute next version ----------------------------------------------------
compute_next() {
  local cur="$1" level="$2" channel="$3"
  local base pre major minor patch betanum
  base="${cur%%-*}"                       # X.Y.Z
  if [ "$cur" = "$base" ]; then pre=""; else pre="${cur#*-}"; fi  # beta.N or empty
  IFS='.' read -r major minor patch <<EOF
$base
EOF

  if [ "$channel" = "beta" ] && [ -n "$pre" ]; then
    # already a beta -> just increment the beta counter, keep base + level ignored
    betanum="${pre#beta.}"
    printf '%s.%s.%s-beta.%d' "$major" "$minor" "$patch" "$((betanum + 1))"
    return
  fi

  # bump the base (stable bump from a beta drops the prerelease, no base bump
  # beyond the requested level — promote-to-stable keeps the beta's base)
  if [ "$channel" = "stable" ] && [ -n "$pre" ]; then
    # promote: strip prerelease, keep base as-is for the level requested
    case "$level" in
      patch|minor|major) base="$major.$minor.$patch" ;;
    esac
    printf '%s' "$base"
    return
  fi

  # normal numeric bump on a stable current
  case "$level" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac

  if [ "$channel" = "beta" ]; then
    printf '%s.%s.%s-beta.1' "$major" "$minor" "$patch"
  else
    printf '%s.%s.%s' "$major" "$minor" "$patch"
  fi
}

if [ -n "$SET_VERSION" ]; then
  validate_semver "$SET_VERSION"
  NEW="$SET_VERSION"
else
  NEW="$(compute_next "$CUR" "$LEVEL" "$CHANNEL")"
fi
validate_semver "$NEW"

[ "$NEW" != "$CUR" ] || die "new version equals current ($CUR) — nothing to do"

# --- report ------------------------------------------------------------------
TAG="$SKILL-$NEW"
printf 'skill:    %s\n' "$SKILL"
printf 'channel:  %s\n' "$CHANNEL"
printf 'version:  %s -> %s\n' "$CUR" "$NEW"
printf 'tag:      %s\n' "$TAG"
FILES="skills/$SKILL/.claude-plugin/plugin.json"
if [ "$HAS_CODEX_PLUGIN" -eq 1 ]; then
  FILES="$FILES, skills/$SKILL/.codex-plugin/plugin.json"
fi
FILES="$FILES, .claude-plugin/marketplace.json"
printf 'files:    %s\n' "$FILES"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n[dry-run] no files written.\n'
  exit 0
fi

# --- apply edits (in-place, formatting-preserving) ---------------------------
# plugin.json: replace the first "version": "..." occurrence.
tmp="$(mktemp)"
awk -v ver="$NEW" '
  !done && /"version"[[:space:]]*:/ {
    sub(/"version"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"version\": \"" ver "\"")
    done=1
  }
  { print }
' "$PLUGIN_JSON" > "$tmp" && mv "$tmp" "$PLUGIN_JSON"

if [ "$HAS_CODEX_PLUGIN" -eq 1 ]; then
  # .codex-plugin/plugin.json: replace the first "version": "..." occurrence.
  tmp="$(mktemp)"
  awk -v ver="$NEW" '
    !done && /"version"[[:space:]]*:/ {
      sub(/"version"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"version\": \"" ver "\"")
      done=1
    }
    { print }
  ' "$CODEX_PLUGIN_JSON" > "$tmp" && mv "$tmp" "$CODEX_PLUGIN_JSON"
fi

# marketplace.json: replace "version" only inside the matching plugin block.
tmp="$(mktemp)"
awk -v name="$SKILL" -v ver="$NEW" '
  $0 ~ "\"name\"[[:space:]]*:[[:space:]]*\"" name "\"" { inb=1 }
  inb && /"version"[[:space:]]*:/ {
    sub(/"version"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"version\": \"" ver "\"")
    inb=0
  }
  { print }
' "$MARKETPLACE" > "$tmp" && mv "$tmp" "$MARKETPLACE"

# --- verify all manifests now agree ------------------------------------------
P_NEW="$(read_plugin_version)"
M_NEW="$(read_market_version)"
C_NEW=""
if [ "$HAS_CODEX_PLUGIN" -eq 1 ]; then
  C_NEW="$(read_codex_plugin_version)"
fi
if [ "$P_NEW" != "$NEW" ] || [ "$M_NEW" != "$NEW" ]; then
  die "post-edit mismatch: plugin.json=$P_NEW marketplace.json=$M_NEW (wanted $NEW)"
fi
if [ "$HAS_CODEX_PLUGIN" -eq 1 ] && [ "$C_NEW" != "$NEW" ]; then
  die "post-edit mismatch: .codex-plugin/plugin.json=$C_NEW (wanted $NEW)"
fi

UPDATED_COUNT=3
if [ "$HAS_CODEX_PLUGIN" -eq 1 ]; then
  UPDATED_COUNT=4
fi
printf '\nbumped %s to %s (%s files updated, in sync).\n' "$SKILL" "$NEW" "$UPDATED_COUNT"
printf 'next: git add -A && git commit && git tag %s\n' "$TAG"
