#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'test-dev-loop-release-tooling: %s\n' "$1" >&2
  exit 1
}

# This test verifies the awk-written versions by reading them back with jq (an
# independent implementation, so a shared bug can't hide). bump-version.sh
# itself stays jq-free; the dependency is the test's alone, so fail clearly if
# jq is absent rather than letting a downstream jq invocation error out.
command -v jq >/dev/null 2>&1 || fail "jq is required to run this test; install it (e.g. 'brew install jq')"

read_skill_version() {
  awk -F'"' '/^version:[[:space:]]*"/{print $2; exit}' "$1"
}

read_json_version() {
  jq -r '.version' "$1"
}

read_market_version() {
  local marketplace="$1" name="$2"
  jq -r --arg name "$name" '.plugins[] | select(.name == $name) | .version' "$marketplace"
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" != "$expected" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    fail "$label: missing '$needle'"
  fi
}

active_plugin_roots() {
  local source
  jq -r '.plugins[] | select(.source | startswith("./skills/")) | .source' "$ROOT/.claude-plugin/marketplace.json" |
    while IFS= read -r source; do
      printf '%s/%s\n' "$ROOT" "${source#./}"
    done | sort
}

read_frontmatter_name() {
  awk '
    /^name:[[:space:]]*/ {
      sub(/^name:[[:space:]]*/, "", $0)
      gsub(/^["'\''[:space:]]+|["'\''[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$1"
}

validate_skill_frontmatter() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"{sys.argv[1]}: could not import yaml parser: {exc}")

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()

if not lines or lines[0].strip() != "---":
    raise SystemExit(f"{path}: missing YAML frontmatter")

end_idx = next((idx for idx, line in enumerate(lines[1:], start=1) if line.strip() == "---"), None)
if end_idx is None:
    raise SystemExit(f"{path}: missing YAML frontmatter terminator")

frontmatter = "\n".join(lines[1:end_idx])

try:
    data = yaml.safe_load(frontmatter) or {}
except Exception as exc:
    raise SystemExit(f"{path}: invalid YAML: {exc}")

description = str(data.get("description", ""))
if len(description) > 1024:
    raise SystemExit(f"{path}: invalid description: exceeds maximum length of 1024 characters")
PY
}

write_skill_fixture() {
  local repo="$1" skill="$2" version="$3" with_codex="$4"
  mkdir -p "$repo/skills/$skill/.claude-plugin"
  cat > "$repo/skills/$skill/SKILL.md" <<EOF
---
name: $skill
version: "$version"
description: fixture
---
EOF
  cat > "$repo/skills/$skill/.claude-plugin/plugin.json" <<EOF
{
  "name": "$skill",
  "version": "$version"
}
EOF
  if [ "$with_codex" = "yes" ]; then
    mkdir -p "$repo/skills/$skill/.codex-plugin"
    cat > "$repo/skills/$skill/.codex-plugin/plugin.json" <<EOF
{
  "name": "$skill",
  "version": "$version"
}
EOF
  fi
}

run_bump_version_checks() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/scripts" "$tmp/.claude-plugin"
  cp "$ROOT/scripts/bump-version.sh" "$tmp/scripts/bump-version.sh"
  chmod +x "$tmp/scripts/bump-version.sh"

  write_skill_fixture "$tmp" "demo-codex" "1.2.3" "yes"
  write_skill_fixture "$tmp" "demo-basic" "0.4.0" "no"

  cat > "$tmp/.claude-plugin/marketplace.json" <<'EOF'
{
  "plugins": [
    {
      "name": "demo-codex",
      "version": "1.2.3"
    },
    {
      "name": "demo-basic",
      "version": "0.4.0"
    }
  ]
}
EOF

  local dry_run
  dry_run="$(cd "$tmp" && ./scripts/bump-version.sh demo-codex --set 1.2.4 --dry-run)"
  assert_contains "dry-run file list" "$dry_run" "skills/demo-codex/.codex-plugin/plugin.json"

  (cd "$tmp" && ./scripts/bump-version.sh demo-codex --set 1.2.4 >/dev/null)
  assert_eq "demo-codex SKILL.md" "$(read_skill_version "$tmp/skills/demo-codex/SKILL.md")" "1.2.4"
  assert_eq "demo-codex Claude manifest" "$(read_json_version "$tmp/skills/demo-codex/.claude-plugin/plugin.json")" "1.2.4"
  assert_eq "demo-codex Codex manifest" "$(read_json_version "$tmp/skills/demo-codex/.codex-plugin/plugin.json")" "1.2.4"
  assert_eq "demo-codex marketplace" "$(read_market_version "$tmp/.claude-plugin/marketplace.json" demo-codex)" "1.2.4"

  (cd "$tmp" && ./scripts/bump-version.sh demo-basic --set 0.4.1 >/dev/null)
  assert_eq "demo-basic SKILL.md" "$(read_skill_version "$tmp/skills/demo-basic/SKILL.md")" "0.4.1"
  assert_eq "demo-basic Claude manifest" "$(read_json_version "$tmp/skills/demo-basic/.claude-plugin/plugin.json")" "0.4.1"
  assert_eq "demo-basic marketplace" "$(read_market_version "$tmp/.claude-plugin/marketplace.json" demo-basic)" "0.4.1"
}

run_doctor_prompt_contract_checks() {
  local doctor
  doctor="$(cat "$ROOT/skills/dev-loop/agents/doctor-worker.md")"

  # These assert literal needles that must appear verbatim in the prompt — the
  # tildes and backticks are part of the text we grep for, not values to expand.
  # shellcheck disable=SC2088,SC2016
  assert_contains "doctor root Claude plugin skill path" "$doctor" '~/.claude/plugins/cache/*/<plugin>/*/SKILL.md'
  # shellcheck disable=SC2088
  assert_contains "doctor root Codex plugin skill path" "$doctor" '~/.codex/plugins/cache/*/<plugin>/*/SKILL.md'
  assert_contains "doctor wildcard agent probe" "$doctor" 'agents/*.md'
  # shellcheck disable=SC2016
  assert_contains "doctor frontmatter agent name match" "$doctor" 'frontmatter `name:`'
}

run_sync_script_contract_checks() {
  local sync_script
  sync_script="$(cat "$ROOT/skills/dev-loop/sync-plugin-cache.sh")"

  assert_contains "sync-plugin-cache includes dependencies manifest" "$sync_script" 'dependencies.yaml'
  assert_contains "sync-plugin-cache syncs Codex skills subtree" "$sync_script" 'Sync Codex skills subtree'
}

run_skill_frontmatter_contract_checks() {
  while IFS= read -r skill; do
    validate_skill_frontmatter "$ROOT/$skill"
  done < <(
    cd "$ROOT" && find skills -maxdepth 3 -type f -name SKILL.md \
      -not -path '*/skills/*' \
      -print | sort
  )
}

run_plugin_manifest_contract_checks() {
  local manifest rel root skills_path type

  while IFS= read -r manifest; do
    rel="${manifest#$ROOT/}"
    type="$(jq -r '.skills | type' "$manifest")"
    assert_eq "$rel skills field type" "$type" "string"
  done < <(
    find "$ROOT/skills" -maxdepth 3 -type f \
      \( -path '*/.codex-plugin/plugin.json' -o -path '*/.claude-plugin/plugin.json' \) \
      -print | sort
  )

  while IFS= read -r root; do
    manifest="$root/.codex-plugin/plugin.json"
    rel="${manifest#$ROOT/}"
    [ -f "$manifest" ] || fail "$rel missing"
    skills_path="$(jq -r '.skills // empty' "$manifest")"
    assert_eq "$rel skills path" "$skills_path" "./skills/"
  done < <(active_plugin_roots)
}

run_codex_skill_mirror_contract_checks() {
  local root canonical name mirror

  while IFS= read -r root; do
    while IFS= read -r canonical; do
      name="$(read_frontmatter_name "$canonical")"
      [ -n "$name" ] || fail "${canonical#$ROOT/} missing frontmatter name"
      mirror="$root/skills/$name/SKILL.md"
      [ -f "$mirror" ] || fail "${mirror#$ROOT/} missing mirror for ${canonical#$ROOT/}"
      cmp -s "$canonical" "$mirror" || fail "${mirror#$ROOT/} differs from ${canonical#$ROOT/}"
    done < <(
      find "$root" -maxdepth 3 -type f -name SKILL.md \
        -not -path "$root/skills/*" \
        -print | sort
    )
  done < <(active_plugin_roots)
}

run_bump_version_checks
run_doctor_prompt_contract_checks
run_sync_script_contract_checks
run_skill_frontmatter_contract_checks
run_plugin_manifest_contract_checks
run_codex_skill_mirror_contract_checks

printf 'test-dev-loop-release-tooling: ok\n'
