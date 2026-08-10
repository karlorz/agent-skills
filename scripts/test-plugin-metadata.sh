#!/usr/bin/env bash

# Regression fixtures for the cross-plugin metadata contract in
# test-dev-loop-release-tooling.sh.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-plugin-metadata.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

PASS=0
FAIL=0

copy_fixture() {
  local name="$1"
  local destination="$TEST_ROOT/$name"

  git clone --quiet --no-hardlinks "$REPO_ROOT" "$destination"
  rsync -a --exclude='.git' "$REPO_ROOT/" "$destination/"
  printf '%s\n' "$destination"
}

run_release_tooling() {
  local root="$1"
  (
    cd "$root" || exit 1
    bash scripts/test-dev-loop-release-tooling.sh
  )
}

assert_fail() {
  local label="$1" pattern="$2" root="$3"
  local output rc

  output="$(run_release_tooling "$root" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$output" | grep -Fq -- "$pattern"; then
    printf 'PASS: %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s — expected nonzero with %s, got exit %s:\n%s\n' \
      "$label" "$pattern" "$rc" "$output"
    FAIL=$((FAIL + 1))
  fi
}

marker_root="$(copy_fixture unwanted-marker)"
python3 - "$marker_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

for manifest in (
    root / "skills/deep-research/.claude-plugin/plugin.json",
    root / "skills/deep-research/.codex-plugin/plugin.json",
):
    data = json.loads(manifest.read_text())
    data["description"] += " v9.9.9: stale fixture marker."
    manifest.write_text(json.dumps(data, indent=2) + "\n")

marketplace = root / ".claude-plugin/marketplace.json"
data = json.loads(marketplace.read_text())
for plugin in data["plugins"]:
    if plugin["name"] == "deep-research":
        plugin["description"] += " v9.9.9: stale fixture marker."
marketplace.write_text(json.dumps(data, indent=2) + "\n")
PY
assert_fail "release markers in descriptions are reported" "release marker" "$marker_root"

duplicate_root="$(copy_fixture duplicate-entry)"
python3 - "$duplicate_root" <<'PY'
import copy
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
marketplace = root / ".claude-plugin/marketplace.json"
data = json.loads(marketplace.read_text())
deep_research = next(plugin for plugin in data["plugins"] if plugin["name"] == "deep-research")
data["plugins"].append(copy.deepcopy(deep_research))
marketplace.write_text(json.dumps(data, indent=2) + "\n")
PY
assert_fail "duplicate marketplace names are reported" "duplicate marketplace name" "$duplicate_root"

orphan_root="$(copy_fixture orphan-entry)"
python3 - "$orphan_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
marketplace = root / ".claude-plugin/marketplace.json"
data = json.loads(marketplace.read_text())
data["plugins"].append({
    "name": "not-a-plugin",
    "source": "./skills/not-a-plugin",
    "description": "orphan fixture",
    "version": "1.0.0",
})
marketplace.write_text(json.dumps(data, indent=2) + "\n")
PY
assert_fail "orphan marketplace sources are reported" "marketplace source directory missing" "$orphan_root"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
