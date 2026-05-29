#!/usr/bin/env bash
#
# bump-version.sh — bump a skill's version across its three manifests.
#
# A skill version lives in three places that must stay in sync:
#   1. skills/<skill>/SKILL.md                  frontmatter:  version: "X.Y.Z"
#   2. skills/<skill>/.claude-plugin/plugin.json              "version": "X.Y.Z"
#   3. .claude-plugin/marketplace.json          matching plugin entry's "version"
#
# This script reads the current version from SKILL.md (source of truth),
# computes the next version, and rewrites all three files in place while
# preserving their exact formatting. It does NOT git add/commit/tag/push —
# the dev-loop PUSH step owns that. It prints the suggested tag in the
# repo's tag_format ({skill}-{version}, e.g. dev-loop-1.20.1).
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

[ -d "$SKILL_DIR" ]    || die "skill not found: skills/$SKILL/"
[ -f "$SKILL_MD" ]     || die "missing $SKILL_MD"
[ -f "$PLUGIN_JSON" ]  || die "missing $PLUGIN_JSON"
[ -f "$MARKETPLACE" ]  || die "missing $MARKETPLACE"

# --- read current versions ---------------------------------------------------
read_skill_version() {
  awk -F'"' '/^version:[[:space:]]*"/{print $2; exit}' "$SKILL_MD"
}
read_plugin_version() {
  awk -F'"' '/"version"[[:space:]]*:/{print $4; exit}' "$PLUGIN_JSON"
}
read_market_version() {
  awk -v name="$SKILL" '
    $0 ~ "\"name\"[[:space:]]*:[[:space:]]*\"" name "\"" {inb=1}
    inb && /"version"[[:space:]]*:/ {
      n=split($0,a,"\""); print a[4]; exit
    }' "$MARKETPLACE"
}

CUR="$(read_skill_version)"
[ -n "$CUR" ] || die "could not read current version from $SKILL_MD"
P_CUR="$(read_plugin_version)"
M_CUR="$(read_market_version)"
[ -n "$M_CUR" ] || die "no marketplace.json entry for plugin '$SKILL'"

# --- pre-check: warn on pre-existing drift -----------------------------------
if [ "$P_CUR" != "$CUR" ]; then
  printf 'bump-version: WARNING plugin.json (%s) != SKILL.md (%s) before bump\n' "$P_CUR" "$CUR" >&2
fi
if [ "$M_CUR" != "$CUR" ]; then
  printf 'bump-version: WARNING marketplace.json (%s) != SKILL.md (%s) before bump\n' "$M_CUR" "$CUR" >&2
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
printf 'files:    skills/%s/SKILL.md, skills/%s/.claude-plugin/plugin.json, .claude-plugin/marketplace.json\n' "$SKILL" "$SKILL"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n[dry-run] no files written.\n'
  exit 0
fi

# --- apply edits (in-place, formatting-preserving) ---------------------------
# SKILL.md: replace the frontmatter version line.
tmp="$(mktemp)"
awk -v ver="$NEW" '
  !done && /^version:[[:space:]]*"/ { print "version: \"" ver "\""; done=1; next }
  { print }
' "$SKILL_MD" > "$tmp" && mv "$tmp" "$SKILL_MD"

# plugin.json: replace the first "version": "..." occurrence.
tmp="$(mktemp)"
awk -v ver="$NEW" '
  !done && /"version"[[:space:]]*:/ {
    sub(/"version"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"version\": \"" ver "\"")
    done=1
  }
  { print }
' "$PLUGIN_JSON" > "$tmp" && mv "$tmp" "$PLUGIN_JSON"

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

# --- verify all three now agree ----------------------------------------------
S_NEW="$(read_skill_version)"
P_NEW="$(read_plugin_version)"
M_NEW="$(read_market_version)"
if [ "$S_NEW" != "$NEW" ] || [ "$P_NEW" != "$NEW" ] || [ "$M_NEW" != "$NEW" ]; then
  die "post-edit mismatch: SKILL.md=$S_NEW plugin.json=$P_NEW marketplace.json=$M_NEW (wanted $NEW)"
fi

printf '\nbumped %s to %s (3 files updated, in sync).\n' "$SKILL" "$NEW"
printf 'next: git add -A && git commit && git tag %s\n' "$TAG"
