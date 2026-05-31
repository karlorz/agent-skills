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
}

run_bump_version_checks
run_doctor_prompt_contract_checks
run_sync_script_contract_checks

printf 'test-dev-loop-release-tooling: ok\n'
