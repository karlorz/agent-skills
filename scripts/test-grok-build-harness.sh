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
run_generate "$TEST_ROOT/merged.toml" --preserve "$TEST_ROOT/live-config.toml" --enabled "a"
assert_contains "preserve keeps live sources" \
  "$(cat "$TEST_ROOT/merged.toml")" 'name = "my-team"'
assert_contains "preserve keeps template sources" \
  "$(cat "$TEST_ROOT/merged.toml")" 'name = "karlorz-agent-skills"'
run_generate "$TEST_ROOT/merged-alias.toml" --preserve-sources "$TEST_ROOT/live-config.toml" --enabled "a"
assert_contains "--preserve-sources alias still works" \
  "$(cat "$TEST_ROOT/merged-alias.toml")" 'name = "my-team"'

# --- config generation: host-set [plugins] keys survive re-renders -----------
run_generate "$TEST_ROOT/keyed.toml" --hub-key h --new-key n --context7-key c --enabled "a"
python3 - "$TEST_ROOT/keyed.toml" <<'EOF'
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
for i, line in enumerate(lines):
    if line.strip().startswith('enabled = ['):
        lines.insert(i + 1, 'disabled = ["host-backup-restore"]')
        break
p.write_text('\n'.join(lines) + '\n')
EOF
run_generate "$TEST_ROOT/preserved.toml" --preserve "$TEST_ROOT/keyed.toml" \
  --hub-key h --new-key n --context7-key c --enabled "a"
assert_contains "preserve keeps host disabled list" \
  "$(cat "$TEST_ROOT/preserved.toml")" 'disabled = ["host-backup-restore"]'
assert_eq "preserve: enabled stays template-owned" \
  "$(grep -c 'enabled = \["a"\]' "$TEST_ROOT/preserved.toml")" "1"

# --- merge-agents.py: splice + migration + idempotency -----------------------
MERGE_PY="$PLUGIN/scripts/merge-agents.py"
ASSET_MD="$PLUGIN/assets/AGENTS.md"
# migration: v0.2.0 shape (skillwiki marker + unmarked contract + user content)
printf '<!-- skillwiki:begin -->\nmarker line\n<!-- skillwiki:end -->\n\n## Subagent contract\n- bullet one\n- Full rules: read `~/.grok/agentrules.md`.\n\n## User preferences\n- keep me\n' \
  > "$TEST_ROOT/migrate.md"
python3 "$MERGE_PY" "$ASSET_MD" "$TEST_ROOT/migrate.md" > "$TEST_ROOT/migrated.md"
MIG="$(cat "$TEST_ROOT/migrated.md")"
assert_contains "migration keeps skillwiki marker" "$MIG" "<!-- skillwiki:begin -->"
assert_contains "migration wraps contract in harness marker" "$MIG" "<!-- grok-build-harness:begin -->"
assert_contains "migration keeps user content after contract" "$MIG" "## User preferences"
assert_contains "migration keeps user content text" "$MIG" "- keep me"
assert_eq "migration: exactly one contract block" \
  "$(grep -c '## Subagent contract' "$TEST_ROOT/migrated.md")" "1"
# splice idempotency: merging the merged file again is byte-identical
python3 "$MERGE_PY" "$ASSET_MD" "$TEST_ROOT/migrated.md" > "$TEST_ROOT/migrated2.md"
if cmp -s "$TEST_ROOT/migrated.md" "$TEST_ROOT/migrated2.md"; then
  ok "merge is idempotent (run twice, byte-identical)"
else
  fail "merge is NOT idempotent (run twice differs)"
fi
# insert fallback: user file without marker/contract keeps everything
printf '# my own notes\n\nsome content\n' > "$TEST_ROOT/bare.md"
python3 "$MERGE_PY" "$ASSET_MD" "$TEST_ROOT/bare.md" > "$TEST_ROOT/bare-merged.md"
assert_contains "insert fallback keeps user file content" \
  "$(cat "$TEST_ROOT/bare-merged.md")" "some content"
assert_contains "insert fallback adds marked contract" \
  "$(cat "$TEST_ROOT/bare-merged.md")" "<!-- grok-build-harness:begin -->"

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

# --- installer: AGENTS.md splice merge (user content preserved) ---------------
MERGE_HOME="$TEST_ROOT/merge-home"
mkdir -p "$MERGE_HOME"
printf '<!-- skillwiki:begin -->\nmarker line\n<!-- skillwiki:end -->\n\n## User preferences\n- keep me\n' > "$MERGE_HOME/AGENTS.md"
"$INSTALL" --grok-home "$MERGE_HOME" --skip-plugins --no-config --force -y >/dev/null 2>&1
MERGE_OUT="$(cat "$MERGE_HOME/AGENTS.md")"
assert_contains "merge keeps skillwiki marker" "$MERGE_OUT" "<!-- skillwiki:begin -->"
assert_contains "merge installs subagent contract" "$MERGE_OUT" "## Subagent contract"
assert_contains "merge wraps contract in harness marker" "$MERGE_OUT" "<!-- grok-build-harness:begin -->"
assert_contains "merge keeps user content" "$MERGE_OUT" "## User preferences"
assert_contains "merge keeps user content text" "$MERGE_OUT" "- keep me"

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

# --- installer: keyed config survives a keyless re-run (ADR-4) ----------------
GUARD_HOME="$TEST_ROOT/guard-home"
mkdir -p "$GUARD_HOME"
run_generate "$GUARD_HOME/config.toml" --hub-key g --new-key g2 --context7-key g3 --enabled "a"
GUARD_OUT="$(env -u HARNESS_HUB_KEY -u HARNESS_NEW_KEY -u HARNESS_CONTEXT7_KEY \
  "$INSTALL" --grok-home "$GUARD_HOME" --skip-plugins --force -y 2>&1 || true)"
assert_contains "keyless re-run warns about skipping config render" "$GUARD_OUT" "skipping config render"
assert_contains "keyless re-run names --force-render" "$GUARD_OUT" "--force-render"
assert_eq "keyless re-run keeps keyed config untouched" \
  "$(grep -c 'api_key = "g' "$GUARD_HOME/config.toml")" "7"
env -u HARNESS_HUB_KEY -u HARNESS_NEW_KEY -u HARNESS_CONTEXT7_KEY \
  "$INSTALL" --grok-home "$GUARD_HOME" --skip-plugins --force -y --force-render >/dev/null 2>&1
assert_eq "--force-render rewrites env-only" \
  "$(grep -c '^api_key = ' "$GUARD_HOME/config.toml")" "0"

# --- installer: host-set disabled list survives a full re-run -----------------
PRES_HOME="$TEST_ROOT/pres-home"
mkdir -p "$PRES_HOME"
run_generate "$PRES_HOME/config.toml" --hub-key p --new-key p2 --context7-key p3 --enabled "superpowers"
python3 - "$PRES_HOME/config.toml" <<'EOF'
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
for i, line in enumerate(lines):
    if line.strip().startswith('enabled = ['):
        lines.insert(i + 1, 'disabled = ["host-backup-restore"]')
        break
p.write_text('\n'.join(lines) + '\n')
EOF
"$INSTALL" --grok-home "$PRES_HOME" --skip-plugins --force -y >/dev/null 2>&1
assert_contains "re-render keeps host disabled list" \
  "$(cat "$PRES_HOME/config.toml")" 'disabled = ["host-backup-restore"]'
PRES_RUN2="$("$INSTALL" --grok-home "$PRES_HOME" --skip-plugins --force -y 2>&1)"
assert_eq "re-render with preserved key stays idempotent" \
  "$(grep -c 'identical, skipping' <<<"$PRES_RUN2")" "5"

# --- installer: unknown option exits 1 ----------------------------------------
"$INSTALL" --definitely-not-a-flag >/dev/null 2>&1
assert_eq "unknown option exits 1" "$?" "1"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
