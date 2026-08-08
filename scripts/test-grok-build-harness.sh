#!/usr/bin/env bash

# Regression tests for the grok-build-harness plugin: config generation in all
# modes, installer dry-run/warning/flag semantics, AGENTS.md merge, and re-run
# idempotency. Runs without a grok binary (CI has none): runtime bootstrap
# behavior is covered by the separate E2E workflow (e2e.yml) and local
# GROK_HOME scratch runs.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/skills/grok-build-harness"
INSTALL="$PLUGIN/scripts/install.sh"
GENERATE="$PLUGIN/scripts/generate-config.py"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/grok-build-harness-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

PASS=0
FAIL=0

ok()   { printf 'ok:   %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    ok "$label"
  else
    fail "$label: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -Fq -- "$needle" <<<"$haystack"; then
    ok "$label"
  else
    fail "$label: missing '$needle'"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -Fq -- "$needle" <<<"$haystack"; then
    fail "$label: unexpected '$needle'"
  else
    ok "$label"
  fi
}

run_generate() {
  local out="$1"; shift
  python3 "$GENERATE" --template "$PLUGIN/assets/config.toml.template" \
    --out "$out" "$@" >/dev/null 2>&1
}

# --- syntax gates ------------------------------------------------------------
bash -n "$INSTALL" && ok "install.sh parses (bash -n)" || fail "install.sh fails bash -n"
python3 -m py_compile "$GENERATE" 2>/dev/null \
  && ok "generate-config.py compiles" || fail "generate-config.py fails to compile"

# --- config generation: with keys --------------------------------------------
run_generate "$TEST_ROOT/with-keys.toml" \
  --hub-key test-hub --new-key test-new --context7-key test-ctx \
  --enabled "superpowers,dev-loop,skillwiki"
assert_eq "with-keys: 5 hub + 2 new api_key lines" \
  "$(grep -c 'api_key = "test' "$TEST_ROOT/with-keys.toml")" "7"
assert_contains "with-keys: context7 key injected" \
  "$(cat "$TEST_ROOT/with-keys.toml")" '"test-ctx"'
assert_contains "with-keys: enabled list substituted" \
  "$(cat "$TEST_ROOT/with-keys.toml")" 'enabled = ["superpowers", "dev-loop", "skillwiki"]'

# --- config generation: env-only ---------------------------------------------
run_generate "$TEST_ROOT/env-only.toml" --enabled "superpowers"
assert_eq "env-only: zero api_key lines" \
  "$(grep -c '^api_key = ' "$TEST_ROOT/env-only.toml")" "0"
assert_not_contains "env-only: context7 --api-key pair dropped" \
  "$(cat "$TEST_ROOT/env-only.toml")" '"--api-key"'
assert_contains "env-only: env_key fallback kept" \
  "$(cat "$TEST_ROOT/env-only.toml")" 'env_key = "HUB_API_KEY"'

# --- config generation: restrictive mode -------------------------------------
run_generate "$TEST_ROOT/restrictive.toml" --permission-mode plan --enabled "a"
assert_eq "restrictive: permission_mode = plan" \
  "$(grep -c 'permission_mode = "plan"' "$TEST_ROOT/restrictive.toml")" "1"
run_generate "$TEST_ROOT/default.toml" --enabled "a"
assert_eq "default: permission_mode = always-approve" \
  "$(grep -c 'permission_mode = "always-approve"' "$TEST_ROOT/default.toml")" "1"

# --- config generation: preserve marketplace sources -------------------------
printf '[[marketplace.sources]]\nname = "my-team"\ngit = "https://github.com/me/team-plugins.git"\n' \
  > "$TEST_ROOT/live-config.toml"
run_generate "$TEST_ROOT/merged.toml" --preserve-sources "$TEST_ROOT/live-config.toml" --enabled "a"
assert_contains "preserve-sources keeps live sources" \
  "$(cat "$TEST_ROOT/merged.toml")" 'name = "my-team"'
assert_contains "preserve-sources keeps template sources" \
  "$(cat "$TEST_ROOT/merged.toml")" 'name = "karlorz-agent-skills"'

# --- installer: dry-run plan --------------------------------------------------
DRY_OUT="$("$INSTALL" --grok-home "$TEST_ROOT/never-created" --dry-run --skip-plugins 2>&1 || true)"
assert_contains "dry-run: agent install plan listed" "$DRY_OUT" "agent grok-build-byok: would install"
assert_contains "dry-run: config plan listed" "$DRY_OUT" "config.toml: would"
assert_contains "dry-run: plugin table listed" "$DRY_OUT" "superpowers simplify deep-research"
assert_eq "dry-run: writes nothing" \
  "$([ -d "$TEST_ROOT/never-created" ] && echo exists || echo absent)" "absent"

# --- installer: missing-key warnings + --require-keys ------------------------
WARN_OUT="$("$INSTALL" --grok-home "$TEST_ROOT/warn-home" --dry-run --skip-plugins 2>&1 || true)"
assert_contains "missing keys warn about env-only config" "$WARN_OUT" "config will be env-only"
assert_contains "missing keys name the env fallbacks" "$WARN_OUT" "HARNESS_HUB_KEY"
"$INSTALL" --grok-home "$TEST_ROOT/rk-home" --require-keys --dry-run --skip-plugins >/dev/null 2>&1
assert_eq "--require-keys exits 1 without keys" "$?" "1"
"$INSTALL" --grok-home "$TEST_ROOT/rk-home" --hub-key k --new-key k2 --require-keys \
  --dry-run --skip-plugins >/dev/null 2>&1
assert_eq "--require-keys passes with keys" "$?" "0"

# --- installer: AGENTS.md skillwiki-marker merge ------------------------------
MERGE_HOME="$TEST_ROOT/merge-home"
mkdir -p "$MERGE_HOME"
printf '<!-- skillwiki:begin -->\nmarker line\n<!-- skillwiki:end -->\n\n## stale\n' > "$MERGE_HOME/AGENTS.md"
"$INSTALL" --grok-home "$MERGE_HOME" --skip-plugins --no-config --force -y >/dev/null 2>&1
MERGE_OUT="$(cat "$MERGE_HOME/AGENTS.md")"
assert_contains "merge keeps skillwiki marker" "$MERGE_OUT" "<!-- skillwiki:begin -->"
assert_contains "merge installs subagent contract" "$MERGE_OUT" "## Subagent contract"
assert_not_contains "merge drops stale content" "$MERGE_OUT" "## stale"

# --- installer: re-run idempotency (files + config) ---------------------------
IDEM_HOME="$TEST_ROOT/idem-home"
export HARNESS_HUB_KEY=idem-hub HARNESS_NEW_KEY=idem-new HARNESS_CONTEXT7_KEY=idem-ctx
"$INSTALL" --grok-home "$IDEM_HOME" --skip-plugins --force -y >/dev/null 2>&1
RUN2_OUT="$("$INSTALL" --grok-home "$IDEM_HOME" --skip-plugins --force -y 2>&1)"
assert_eq "re-run: all five files identical" \
  "$(grep -c 'identical, skipping' <<<"$RUN2_OUT")" "5"
assert_eq "re-run: no new backup dir" \
  "$(find "$IDEM_HOME/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" "0"
assert_eq "re-run: config keeps injected keys" \
  "$(grep -c 'api_key = "idem' "$IDEM_HOME/config.toml")" "7"

# --- installer: unknown option exits 1 ----------------------------------------
"$INSTALL" --definitely-not-a-flag >/dev/null 2>&1
assert_eq "unknown option exits 1" "$?" "1"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
