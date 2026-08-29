#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-plugin-release-drift.js"

fail() {
  printf 'test-plugin-release-drift: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local label="$1" actual="$2" expected="$3"
  [[ "$actual" == *"$expected"* ]] ||
    fail "$label: expected output to contain '$expected', got: $actual"
}

write_manifests() {
  local repo="$1" version="$2" marketplace_version="${3:-$2}"

  mkdir -p \
    "$repo/.claude-plugin" \
    "$repo/skills/dev-loop/.claude-plugin" \
    "$repo/skills/dev-loop/.codex-plugin" \
    "$repo/skills/dev-loop/skills/dev-loop" \
    "$repo/skills/dev-loop/scripts" \
    "$repo/skills/dev-loop/agents" \
    "$repo/skills/dev-loop/templates" \
    "$repo/skills/dev-loop/references"

  cat > "$repo/.claude-plugin/marketplace.json" <<EOF
{
  "plugins": [
    {
      "name": "dev-loop",
      "version": "$marketplace_version",
      "source": "./skills/dev-loop",
      "description": "fixture"
    }
  ]
}
EOF

  cat > "$repo/skills/dev-loop/.claude-plugin/plugin.json" <<EOF
{"name":"dev-loop","version":"$version","skills":"./skills/"}
EOF
  cat > "$repo/skills/dev-loop/.codex-plugin/plugin.json" <<EOF
{"name":"dev-loop","version":"$version","skills":"./skills/"}
EOF
  cat > "$repo/skills/dev-loop/skills/dev-loop/SKILL.md" <<EOF
---
name: dev-loop
description: fixture v$version
---
# fixture
EOF
  printf 'fixture\n' > "$repo/skills/dev-loop/scripts/helper.js"
  printf 'fixture\n' > "$repo/skills/dev-loop/agents/worker.md"
  printf 'fixture\n' > "$repo/skills/dev-loop/templates/report.md"
  printf 'fixture\n' > "$repo/skills/dev-loop/references/runtime.md"
  printf 'required: []\n' > "$repo/skills/dev-loop/dependencies.yaml"
}

init_fixture() {
  local repo="$1" codex_mode="${2:-with-codex}"

  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test"
  git -C "$repo" config user.name "test"
  write_manifests "$repo" "1.26.22"
  if [ "$codex_mode" = "without-codex" ]; then
    rm "$repo/skills/dev-loop/.codex-plugin/plugin.json"
  fi
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "release 1.26.22"
  git -C "$repo" tag dev-loop-1.26.22
}

run_checker() {
  local repo="$1"
  node "$CHECKER" --repo "$repo" --skill dev-loop
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BOOTSTRAP="$TMP/bootstrap"
mkdir -p "$BOOTSTRAP"
git -C "$BOOTSTRAP" init -q
git -C "$BOOTSTRAP" config user.email "test@test"
git -C "$BOOTSTRAP" config user.name "test"
write_manifests "$BOOTSTRAP" "1.26.22"
git -C "$BOOTSTRAP" add -A
git -C "$BOOTSTRAP" commit -q -m "bootstrap"
BOOTSTRAP_OUT="$(run_checker "$BOOTSTRAP")" ||
  fail "repository without a matching historical tag should pass"
assert_contains "bootstrap behavior" "$BOOTSTRAP_OUT" "no matching dev-loop-* tag"

UNCHANGED="$TMP/unchanged"
mkdir -p "$UNCHANGED"
init_fixture "$UNCHANGED"
UNCHANGED_OUT="$(run_checker "$UNCHANGED")" ||
  fail "unchanged tagged payload should pass"
assert_contains "unchanged payload" "$UNCHANGED_OUT" "payload unchanged"

NO_CODEX="$TMP/no-codex"
mkdir -p "$NO_CODEX"
init_fixture "$NO_CODEX" without-codex
NO_CODEX_OUT="$(run_checker "$NO_CODEX")" ||
  fail "plugin without a Codex manifest should pass"
assert_contains "optional current Codex manifest" "$NO_CODEX_OUT" "payload unchanged"

MUTATED="$TMP/mutated"
mkdir -p "$MUTATED"
init_fixture "$MUTATED"
printf 'changed payload\n' > "$MUTATED/skills/dev-loop/scripts/helper.js"
set +e
MUTATED_OUT="$(run_checker "$MUTATED" 2>&1)"
MUTATED_EXIT=$?
set -e
[[ "$MUTATED_EXIT" -ne 0 ]] ||
  fail "changed payload with unchanged released version must fail"
assert_contains "same-version mutation reason" "$MUTATED_OUT" "immutable installed caches"
assert_contains "same-version mutation remedy" "$MUTATED_OUT" "./scripts/bump-version.sh dev-loop patch"

ADVANCED="$TMP/advanced"
mkdir -p "$ADVANCED"
init_fixture "$ADVANCED"
write_manifests "$ADVANCED" "1.26.23"
printf 'changed payload\n' > "$ADVANCED/skills/dev-loop/scripts/helper.js"
ADVANCED_OUT="$(run_checker "$ADVANCED")" ||
  fail "changed payload with an advanced version should pass"
assert_contains "advanced payload" "$ADVANCED_OUT" "version advanced"

FIRST_CODEX="$TMP/first-codex"
mkdir -p "$FIRST_CODEX"
init_fixture "$FIRST_CODEX" without-codex
write_manifests "$FIRST_CODEX" "1.26.23"
FIRST_CODEX_OUT="$(run_checker "$FIRST_CODEX")" ||
  fail "first Codex manifest with an advanced version should pass"
assert_contains "first Codex manifest" "$FIRST_CODEX_OUT" "version advanced"

BEHIND="$TMP/behind"
mkdir -p "$BEHIND"
init_fixture "$BEHIND"
write_manifests "$BEHIND" "1.26.21"
set +e
BEHIND_OUT="$(run_checker "$BEHIND" 2>&1)"
BEHIND_EXIT=$?
set -e
[[ "$BEHIND_EXIT" -ne 0 ]] ||
  fail "current version behind the latest release tag must fail"
assert_contains "behind version" "$BEHIND_OUT" "older than latest tag"

DISAGREE="$TMP/disagree"
mkdir -p "$DISAGREE"
init_fixture "$DISAGREE"
write_manifests "$DISAGREE" "1.26.23" "1.26.22"
set +e
DISAGREE_OUT="$(run_checker "$DISAGREE" 2>&1)"
DISAGREE_EXIT=$?
set -e
[[ "$DISAGREE_EXIT" -ne 0 ]] ||
  fail "manifest disagreement must fail"
assert_contains "manifest disagreement" "$DISAGREE_OUT" "manifest versions disagree"

UNRELATED="$TMP/unrelated"
mkdir -p "$UNRELATED"
init_fixture "$UNRELATED"
printf 'unrelated\n' > "$UNRELATED/README.md"
UNRELATED_OUT="$(run_checker "$UNRELATED")" ||
  fail "unrelated repository changes must not require a dev-loop release"
assert_contains "unrelated change" "$UNRELATED_OUT" "payload unchanged"

SIBLING_TAGS="$TMP/sibling-tags"
mkdir -p "$SIBLING_TAGS"
init_fixture "$SIBLING_TAGS"
git -C "$SIBLING_TAGS" tag dev-loop-dev-20260822
git -C "$SIBLING_TAGS" tag dev-loop-preview-1
git -C "$SIBLING_TAGS" tag dev-loop-preview.foo
SIBLING_OUT="$(run_checker "$SIBLING_TAGS")" ||
  fail "sibling or non-semver suffixed tags must be ignored"
assert_contains "sibling tags ignored" "$SIBLING_OUT" "payload unchanged"

MALFORMED_EXACT="$TMP/malformed-exact"
mkdir -p "$MALFORMED_EXACT"
init_fixture "$MALFORMED_EXACT"
git -C "$MALFORMED_EXACT" tag dev-loop-1.26.22-invalid_meta
set +e
MALFORMED_EXACT_OUT="$(run_checker "$MALFORMED_EXACT" 2>&1)"
MALFORMED_EXACT_EXIT=$?
set -e
[[ "$MALFORMED_EXACT_EXIT" -ne 0 ]] ||
  fail "exact malformed semver tag must fail"
assert_contains "malformed exact tag" "$MALFORMED_EXACT_OUT" "is not valid X.Y.Z or X.Y.Z-beta.N semver"

printf 'test-plugin-release-drift: all checks passed\n'
