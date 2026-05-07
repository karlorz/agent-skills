#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-user-scope.sh"

TESTS_PASSED=0
TESTS_TOTAL=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

assert_file_exists() {
  local path="$1"
  local message="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ ! -f "$path" ]]; then
    echo "FAIL: $message" >&2
    echo "  missing file: $path" >&2
    exit 1
  fi
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

bash "$INSTALL_SCRIPT" --codex-home "$TMP_DIR/.codex" >/dev/null
assert_file_exists "$TMP_DIR/.codex/skills/loop/SKILL.md" "copy install should place the skill in the user scope"

bash "$INSTALL_SCRIPT" --codex-home "$TMP_DIR/.codex" --mode symlink >/dev/null
assert_eq "$([[ -L "$TMP_DIR/.codex/skills/loop" ]] && echo yes || echo no)" "yes" "symlink install should replace the copy with a symlink"

echo "All assertions passed ($TESTS_PASSED/$TESTS_TOTAL)."
