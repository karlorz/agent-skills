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
CHECK_CONFIG="$PLUGIN/scripts/check-config.py"
PLUGIN_VERSION="$(awk -F'"' '/"version"[[:space:]]*:/{print $4; exit}' "$PLUGIN/.claude-plugin/plugin.json")"
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
python3 -m py_compile "$CHECK_CONFIG" 2>/dev/null \
  && ok "check-config.py compiles" || fail "check-config.py fails to compile"

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

# --- regression: harness plugin must be in PLUGIN_SPECS + [plugins].enabled ---
# Assert the harness plugin is in install.sh's PLUGIN_SPECS (the source of
# truth for [plugins].enabled) — this is the guard that catches the original
# bug. The dry-run assertion below independently verifies it surfaces in the
# plugins line.
assert_contains "harness plugin in PLUGIN_SPECS" \
  "$(cat "$INSTALL")" 'grok-build-harness|grok-build-harness|SKIP_NONE'

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
assert_contains "dry-run: harness plugin listed first" \
  "$DRY_OUT" "plugins: grok-build-harness superpowers"

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

# --- config generation: toggle present and implement_via_subagents absent ----
assert_contains "template contains grok-build-byok = false" \
  "$(cat "$TEST_ROOT/with-keys.toml")" 'grok-build-byok = false'
assert_not_contains "template does NOT contain implement_via_subagents" \
  "$(cat "$TEST_ROOT/with-keys.toml")" 'implement_via_subagents'

# --- installer: stamp file written on install --------------------------------
STAMP_FILE="$IDEM_HOME/.grok-build-harness-stamp.json"
assert_contains "stamp file created after install" \
  "$([ -f "$STAMP_FILE" ] && echo "exists" || echo "missing")" "exists"
assert_contains "stamp file contains schema" \
  "$(cat "$STAMP_FILE")" '"schema": "grok-build-harness-stamp/v1"'
assert_contains "stamp file contains plugin_version ${PLUGIN_VERSION}" \
  "$(cat "$STAMP_FILE")" "\"plugin_version\": \"${PLUGIN_VERSION}\""

# --- installer: grokgod auto-detect and plan_mode merge ----------------------
GROKGOD_FAKE_HOME="$TEST_ROOT/fake-grokgod-user"
mkdir -p "$GROKGOD_FAKE_HOME/.grokgod"
echo "0.0.1" > "$GROKGOD_FAKE_HOME/.grokgod/.source-version"
GROKGOD_INSTALL_HOME="$TEST_ROOT/grokgod-install-home"

# When grokgod is detected via $HOME/.grokgod/.source-version
HOME="$GROKGOD_FAKE_HOME" "$INSTALL" --grok-home "$GROKGOD_INSTALL_HOME" --skip-plugins --force -y >/dev/null 2>&1
assert_contains "grokgod auto-detected: writes implement_via_subagents" \
  "$(cat "$GROKGOD_INSTALL_HOME/config.toml")" 'implement_via_subagents = true'
assert_contains "grokgod stamp records grokgod_detected = true" \
  "$(cat "$GROKGOD_INSTALL_HOME/.grok-build-harness-stamp.json")" '"grokgod_detected": true'

# When --skip-grokgod is passed with the fake grokgod directory
GROKGOD_SKIP_HOME="$TEST_ROOT/grokgod-skip-home"
HOME="$GROKGOD_FAKE_HOME" "$INSTALL" --grok-home "$GROKGOD_SKIP_HOME" --skip-grokgod --skip-plugins --force -y >/dev/null 2>&1
assert_not_contains "--skip-grokgod skips implement_via_subagents merge" \
  "$(cat "$GROKGOD_SKIP_HOME/config.toml")" 'implement_via_subagents'
assert_contains "--skip-grokgod stamp records grokgod_detected = false" \
  "$(cat "$GROKGOD_SKIP_HOME/.grok-build-harness-stamp.json")" '"grokgod_detected": false'

# --- installer: last flag wins for grokgod ------------------------------------
GROKGOD_LAST_HOME="$TEST_ROOT/grokgod-last-home"
HOME="$GROKGOD_FAKE_HOME" "$INSTALL" --grok-home "$GROKGOD_LAST_HOME" \
  --with-grokgod --skip-grokgod --skip-plugins --force -y >/dev/null 2>&1
assert_not_contains "--skip-grokgod after --with-grokgod wins" \
  "$(cat "$GROKGOD_LAST_HOME/config.toml")" 'implement_via_subagents'

# --- installer: missing grok without --skip-plugins ---------------------------
NO_GROK_HOME="$TEST_ROOT/no-grok-home"
NO_GROK_OUT="$(PATH=/usr/bin:/bin HOME="$TEST_ROOT/empty-home" \
  "$INSTALL" --grok-home "$NO_GROK_HOME" --skip-grokgod --force -y --no-config 2>&1 || true)"
assert_eq "missing grok without --skip-plugins exits 1" \
  "$(PATH=/usr/bin:/bin HOME="$TEST_ROOT/empty-home" \
    "$INSTALL" --grok-home "$NO_GROK_HOME" --skip-grokgod --force -y --no-config >/dev/null 2>&1; echo $?)" "1"
assert_contains "missing grok names the binary, not find_grok" \
  "$NO_GROK_OUT" "grok binary not found"
assert_not_contains "missing grok is not a command-not-found crash" \
  "$NO_GROK_OUT" "find_grok: command not found"

# --- installer: --verify after skip-plugins -----------------------------------
VERIFY_OUT="$("$INSTALL" --grok-home "$IDEM_HOME" --skip-plugins --skip-grokgod --verify --force -y 2>&1)"
assert_contains "--verify prints stamp path" \
  "$VERIFY_OUT" ".grok-build-harness-stamp.json"

# --- installer: unknown option exits 1 ----------------------------------------
"$INSTALL" --definitely-not-a-flag >/dev/null 2>&1
assert_eq "unknown option exits 1" "$?" "1"

# --- check-config.py & schema checking tests ---------------------------------
# 1. Valid consent with version int and account string (assert account not in output)
CONSENT_VALID_CFG="$TEST_ROOT/consent-valid.toml"
cat > "$CONSENT_VALID_CFG" <<'EOF'
disabled_mcp_servers = ["image_mcp"]
[privacy]
privacy_banner_acked = "2026-08-29T00:00:00Z"
[consent.answers.aup]
version = 2
account = "user@example.com"
[consent.answers.tos]
version = 2
EOF
CONSENT_VALID_OUT="$(python3 "$CHECK_CONFIG" --config "$CONSENT_VALID_CFG" 2>&1)"
assert_eq "check-config: valid consent exits 0" "$?" "0"
assert_not_contains "check-config: fixture account PII not in stdout" "$CONSENT_VALID_OUT" "user@example.com"

# 2. Missing consent: OK (exit 0)
CONSENT_MISSING_CFG="$TEST_ROOT/consent-missing.toml"
cat > "$CONSENT_MISSING_CFG" <<'EOF'
disabled_mcp_servers = ["image_mcp"]
[privacy]
privacy_banner_acked = "2026-08-29T00:00:00Z"
EOF
python3 "$CHECK_CONFIG" --config "$CONSENT_MISSING_CFG" >/dev/null 2>&1
assert_eq "check-config: missing consent exits 0" "$?" "0"

# 3. Invalid consent (version string instead of int): fail
CONSENT_INVALID_CFG="$TEST_ROOT/consent-invalid.toml"
cat > "$CONSENT_INVALID_CFG" <<'EOF'
[consent.answers.aup]
version = "two"
EOF
python3 "$CHECK_CONFIG" --config "$CONSENT_INVALID_CFG" >/dev/null 2>&1
assert_eq "check-config: consent version non-int exits non-zero" "$?" "1"

# 4. Unexpected top-level table: exit 0 without --strict; nonzero with --strict
UNEXPECTED_CFG="$TEST_ROOT/unexpected.toml"
cat > "$UNEXPECTED_CFG" <<'EOF'
[future_unknown_table]
foo = "bar"
EOF
python3 "$CHECK_CONFIG" --config "$UNEXPECTED_CFG" >/dev/null 2>&1
assert_eq "check-config: unexpected table without --strict exits 0" "$?" "0"
python3 "$CHECK_CONFIG" --config "$UNEXPECTED_CFG" --strict >/dev/null 2>&1
assert_eq "check-config: unexpected table with --strict exits non-zero" "$?" "1"

# 5. No live docs file: uses vendored keys (privacy classified docs-known, not unexpected)
NO_DOCS_GROK_HOME="$TEST_ROOT/no-docs-grok-home"
mkdir -p "$NO_DOCS_GROK_HOME"
PRIVACY_CFG="$TEST_ROOT/privacy-only.toml"
cat > "$PRIVACY_CFG" <<'EOF'
[privacy]
privacy_banner_acked = "2026-08-29T00:00:00Z"
EOF
GROK_HOME="$NO_DOCS_GROK_HOME" python3 "$CHECK_CONFIG" --config "$PRIVACY_CFG" --strict >/dev/null 2>&1
assert_eq "check-config: vendored fallback knows privacy with --strict" "$?" "0"

# 6. Live $GROK_HOME/docs/user-guide/26-config-reference.md wins over vendored
# (e.g. a fixture docs file that omits privacy makes privacy unexpected)
LIVE_DOCS_GROK_HOME="$TEST_ROOT/live-docs-grok-home"
mkdir -p "$LIVE_DOCS_GROK_HOME/docs/user-guide"
cat > "$LIVE_DOCS_GROK_HOME/docs/user-guide/26-config-reference.md" <<'EOF'
# Configuration reference
### `agent`
### `cli`
EOF
GROK_HOME="$LIVE_DOCS_GROK_HOME" python3 "$CHECK_CONFIG" --config "$PRIVACY_CFG" --strict >/dev/null 2>&1
assert_eq "check-config: live docs wins over vendored (privacy omitted in live docs -> fails --strict)" "$?" "1"

# 7. install.sh accepts --strict flag
STRICT_TEST_HOME="$TEST_ROOT/strict-test-home"
export HARNESS_HUB_KEY=s-hub HARNESS_NEW_KEY=s-new HARNESS_CONTEXT7_KEY=s-ctx
"$INSTALL" --grok-home "$STRICT_TEST_HOME" --skip-plugins --skip-grokgod --verify --strict --force -y >/dev/null 2>&1
assert_eq "install.sh accepts --strict and exits 0 on valid install" "$?" "0"

# 8. User agent named grok-build-byok assert in verify when grok binary is available and plugins not skipped
FAKE_GROK_DIR="$TEST_ROOT/fake-grok-bin"
mkdir -p "$FAKE_GROK_DIR"
cat > "$FAKE_GROK_DIR/grok" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "plugin" ] && [ "$2" = "marketplace" ]; then exit 0; fi
if [ "$1" = "plugin" ] && [ "$2" = "install" ]; then exit 0; fi
if [ "$1" = "plugin" ] && [ "$2" = "list" ]; then
  if [ "${3:-}" = "--json" ]; then
    echo '[{"name":"grok-build-harness","status":"enabled","version":"0.5.0"},{"name":"superpowers","status":"enabled","version":"1.0.0"},{"name":"simplify","status":"enabled","version":"1.0.0"},{"name":"deep-research","status":"enabled","version":"1.0.0"},{"name":"dev-loop","status":"enabled","version":"1.0.0"},{"name":"claude-md-management","status":"enabled","version":"1.0.0"},{"name":"grill-me","status":"enabled","version":"1.0.0"},{"name":"codebase-architecture","status":"enabled","version":"1.0.0"},{"name":"hermes-cli","status":"enabled","version":"1.0.0"},{"name":"skillwiki","status":"enabled","version":"1.0.0"},{"name":"context7","status":"enabled","version":"1.0.0"},{"name":"vault-sync","status":"enabled","version":"1.0.0"},{"name":"codex","status":"enabled","version":"1.0.0"},{"name":"playwright-cli","status":"enabled","version":"1.0.0"}]'
  else
    echo "plugins list"
  fi
  exit 0
fi
if [ "$1" = "models" ]; then
  echo "  - sonnet"
  echo "  - haiku"
  echo "  - deepseek-v4-flash"
  exit 0
fi
if [ "$1" = "inspect" ]; then
  echo '{"agents":[{"name":"grok-build-byok","source":{"type":"user","path":"/some/path"}}],"configWarnings":[]}'
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_GROK_DIR/grok"

FAKE_GROK_HOME="$TEST_ROOT/fake-grok-home"
mkdir -p "$FAKE_GROK_HOME"
export HARNESS_HUB_KEY=fake-hub HARNESS_NEW_KEY=fake-new HARNESS_CONTEXT7_KEY=fake-ctx
PATH="$FAKE_GROK_DIR:$PATH" "$INSTALL" --grok-home "$FAKE_GROK_HOME" --skip-grokgod --verify --force -y >/dev/null 2>&1
assert_eq "install.sh verify with fake grok and grok-build-byok user agent succeeds" "$?" "0"

# Fake grok missing grok-build-byok user agent -> verify must fail
cat > "$FAKE_GROK_DIR/grok" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "plugin" ] && [ "$2" = "marketplace" ]; then exit 0; fi
if [ "$1" = "plugin" ] && [ "$2" = "install" ]; then exit 0; fi
if [ "$1" = "plugin" ] && [ "$2" = "list" ]; then
  if [ "${3:-}" = "--json" ]; then
    echo '[{"name":"grok-build-harness","status":"enabled","version":"0.5.0"},{"name":"superpowers","status":"enabled","version":"1.0.0"},{"name":"simplify","status":"enabled","version":"1.0.0"},{"name":"deep-research","status":"enabled","version":"1.0.0"},{"name":"dev-loop","status":"enabled","version":"1.0.0"},{"name":"claude-md-management","status":"enabled","version":"1.0.0"},{"name":"grill-me","status":"enabled","version":"1.0.0"},{"name":"codebase-architecture","status":"enabled","version":"1.0.0"},{"name":"hermes-cli","status":"enabled","version":"1.0.0"},{"name":"skillwiki","status":"enabled","version":"1.0.0"},{"name":"context7","status":"enabled","version":"1.0.0"},{"name":"vault-sync","status":"enabled","version":"1.0.0"},{"name":"codex","status":"enabled","version":"1.0.0"},{"name":"playwright-cli","status":"enabled","version":"1.0.0"}]'
  else
    echo "plugins list"
  fi
  exit 0
fi
if [ "$1" = "models" ]; then
  echo "  - sonnet"
  echo "  - haiku"
  echo "  - deepseek-v4-flash"
  exit 0
fi
if [ "$1" = "inspect" ]; then
  echo '{"agents":[{"name":"other-agent","source":{"type":"user","path":"/some/path"}}],"configWarnings":[]}'
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_GROK_DIR/grok"

PATH="$FAKE_GROK_DIR:$PATH" "$INSTALL" --grok-home "$FAKE_GROK_HOME" --skip-grokgod --verify --force -y >/dev/null 2>&1
assert_eq "install.sh verify without grok-build-byok user agent fails" "$?" "1"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
