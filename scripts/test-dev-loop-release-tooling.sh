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

allowed = {"allowed-tools", "compatibility", "description", "license", "metadata", "name"}
unexpected = sorted(set(data) - allowed)
if unexpected:
    raise SystemExit(f"{path}: unsupported frontmatter fields: {', '.join(unexpected)}")

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
  assert_eq "demo-codex Claude manifest" "$(read_json_version "$tmp/skills/demo-codex/.claude-plugin/plugin.json")" "1.2.4"
  assert_eq "demo-codex Codex manifest" "$(read_json_version "$tmp/skills/demo-codex/.codex-plugin/plugin.json")" "1.2.4"
  assert_eq "demo-codex marketplace" "$(read_market_version "$tmp/.claude-plugin/marketplace.json" demo-codex)" "1.2.4"

  (cd "$tmp" && ./scripts/bump-version.sh demo-basic --set 0.4.1 >/dev/null)
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
  assert_contains "sync-plugin-cache syncs scripts directory" "$sync_script" 'Sync scripts directory'
  assert_contains "sync-plugin-cache copies scripts recursively" "$sync_script" 'scripts/.'
}

run_dev_loop_prep_prompt_contract_checks() {
  local prompt template
  prompt="$(cat "$ROOT/skills/dev-loop/SKILL.md")"
  template="$(cat "$ROOT/skills/dev-loop/templates/project-config.md")"

  assert_contains "dev-loop parses prep mode" "$prompt" 'MODE = prep'
  assert_contains "dev-loop dispatches prep mode" "$prompt" '**`prep`**'
  assert_contains "dev-loop references preflight inventory helper" "$prompt" 'preflight-inventory.js'
  assert_contains "dev-loop resolves preflight policy" "$prompt" 'PREFLIGHT_POLICY'
  assert_contains "dev-loop gates automation readiness" "$prompt" 'automation_ready'
  assert_contains "dev-loop reports readiness skips" "$prompt" 'Automation Readiness Skips'
  assert_contains "dev-loop prep never starts goal" "$prompt" 'Do not start `/goal`'

  assert_contains "project config includes preflight block" "$template" 'preflight:'
  assert_contains "project config includes unattended skip behavior" "$template" 'unattended_not_ready_behavior: skip'
  assert_contains "project config includes readiness state" "$template" 'preflight_state: ready'
}

assert_json_array_contains() {
  local label="$1" file="$2" jq_filter="$3" expected="$4"
  if ! jq -e --arg expected "$expected" "$jq_filter | index(\$expected) != null" "$file" >/dev/null; then
    fail "$label: missing '$expected'"
  fi
}

run_dev_loop_metadata_contract_checks() {
  local skill_root skill_version claude_manifest codex_manifest marketplace
  local claude_description codex_description marketplace_description
  local setup_source setup_mirror

  skill_root="$ROOT/skills/dev-loop"
  claude_manifest="$skill_root/.claude-plugin/plugin.json"
  codex_manifest="$skill_root/.codex-plugin/plugin.json"
  marketplace="$ROOT/.claude-plugin/marketplace.json"
  skill_version="$(read_json_version "$claude_manifest")"

  assert_eq "dev-loop Claude manifest version" "$(read_json_version "$claude_manifest")" "$skill_version"
  assert_eq "dev-loop Codex manifest version" "$(read_json_version "$codex_manifest")" "$skill_version"
  assert_eq "dev-loop marketplace version" "$(read_market_version "$marketplace" dev-loop)" "$skill_version"

  claude_description="$(jq -r '.description' "$claude_manifest")"
  codex_description="$(jq -r '.description' "$codex_manifest")"
  marketplace_description="$(jq -r '.plugins[] | select(.name == "dev-loop") | .description' "$marketplace")"

  assert_contains "dev-loop SKILL.md current version headline" "$(cat "$skill_root/SKILL.md")" "v${skill_version}:"
  assert_contains "dev-loop Claude manifest current version headline" "$claude_description" "v${skill_version}:"
  assert_contains "dev-loop Codex manifest current version headline" "$codex_description" "v${skill_version}:"
  assert_contains "dev-loop marketplace current version headline" "$marketplace_description" "v${skill_version}:"

  assert_contains "dev-loop Claude manifest mentions prep mode" "$claude_description" "preflight prep mode"
  assert_contains "dev-loop Codex manifest mentions prep mode" "$codex_description" "preflight prep mode"
  assert_contains "dev-loop marketplace mentions prep mode" "$marketplace_description" "preflight prep mode"

  assert_json_array_contains "dev-loop Claude manifest prep keyword" "$claude_manifest" ".keywords" "prep"
  assert_json_array_contains "dev-loop Claude manifest preflight keyword" "$claude_manifest" ".keywords" "preflight"
  assert_json_array_contains "dev-loop Codex manifest prep keyword" "$codex_manifest" ".keywords" "prep"
  assert_json_array_contains "dev-loop Codex manifest preflight keyword" "$codex_manifest" ".keywords" "preflight"
  assert_json_array_contains "dev-loop marketplace prep keyword" "$marketplace" '.plugins[] | select(.name == "dev-loop") | .keywords' "prep"
  assert_json_array_contains "dev-loop marketplace preflight keyword" "$marketplace" '.plugins[] | select(.name == "dev-loop") | .keywords' "preflight"

  setup_source="$skill_root/setup-dev-loop/SKILL.md"
  setup_mirror="$skill_root/skills/setup-dev-loop/SKILL.md"
  [ -f "$setup_mirror" ] || fail "${setup_mirror#$ROOT/} missing setup-dev-loop Codex mirror"
  cmp -s "$setup_source" "$setup_mirror" || fail "${setup_mirror#$ROOT/} differs from ${setup_source#$ROOT/}"
}

run_skill_frontmatter_contract_checks() {
  while IFS= read -r skill; do
    validate_skill_frontmatter "$ROOT/$skill"
  done < <(
    cd "$ROOT" && find skills -maxdepth 4 -type f -name SKILL.md \
      -not -path '*/skills/*' \
      -print | sort
  )
}

run_plugin_version_sync_contract_checks() {
  local name version source root claude_manifest codex_manifest

  while IFS=$'\t' read -r name version source; do
    root="$ROOT/${source#./}"
    claude_manifest="$root/.claude-plugin/plugin.json"
    codex_manifest="$root/.codex-plugin/plugin.json"

    [ -d "$root" ] || fail "$name source directory missing: $source"
    [ -f "$claude_manifest" ] || fail "$name missing Claude plugin manifest"

    assert_eq "$name Claude manifest name" "$(jq -r '.name' "$claude_manifest")" "$name"
    assert_eq "$name Claude manifest version" "$(read_json_version "$claude_manifest")" "$version"

    if [ -f "$codex_manifest" ]; then
      assert_eq "$name Codex manifest name" "$(jq -r '.name' "$codex_manifest")" "$name"
      assert_eq "$name Codex manifest version" "$(read_json_version "$codex_manifest")" "$version"
    fi
  done < <(
    jq -r '.plugins[] | select(.source | startswith("./skills/")) | [.name, .version, .source] | @tsv' \
      "$ROOT/.claude-plugin/marketplace.json" | sort
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
run_dev_loop_prep_prompt_contract_checks
run_dev_loop_metadata_contract_checks
run_skill_frontmatter_contract_checks
run_plugin_version_sync_contract_checks
run_plugin_manifest_contract_checks
run_codex_skill_mirror_contract_checks

printf 'test-dev-loop-release-tooling: ok\n'
