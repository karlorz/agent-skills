#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$SKILL_DIR/scripts/install-codex-home-hooks.sh"

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
  local desc="$1"
  local file="$2"
  local pattern="$3"
  TOTAL=$((TOTAL + 1))
  if grep -Fq -- "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1"
  local file="$2"
  local pattern="$3"
  TOTAL=$((TOTAL + 1))
  if grep -Fq -- "$pattern" "$file"; then
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert_file_exists() {
  local desc="$1"
  local path="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autopilot-codex-home-hooks-test-XXXXXX")"
HOME_DIR="$TEST_DIR/home"
HOOKS_FILE="$HOME_DIR/.codex/hooks.json"
DISPATCH_FILE="$HOME_DIR/.codex/hooks/cmux-stop-dispatch.sh"
SESSION_START_FILE="$HOME_DIR/.codex/hooks/managed-session-start.sh"
HOME_AUTOPILOT_STOP_FILE="$HOME_DIR/.codex/hooks/autopilot-stop.sh"
HOME_SESSION_START_FILE="$HOME_DIR/.codex/hooks/session-start.sh"
AUTOPILOT_RESET_FILE="$HOME_DIR/.codex/autopilot/autopilot-reset.sh"
AUTOPILOT_CORE_FILE="$HOME_DIR/.codex/autopilot/hooks/cmux-autopilot-stop-core.sh"
SESSION_CORE_FILE="$HOME_DIR/.codex/autopilot/hooks/cmux-session-start-core.sh"
RESET_SKILL_FILE="$HOME_DIR/.codex/skills/autopilot_reset/SKILL.md"
CONFIG_FILE="$HOME_DIR/.codex/config.toml"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$HOME_DIR/.codex"
cat >"$CONFIG_FILE" <<'EOF'
notify = ["/tmp/notify.sh"]

[profiles.default]
color = "blue"
EOF

cat >"$HOME_DIR/.bashrc" <<'EOF'
[ -f /root/lifecycle/codex-shell-helpers.sh ] && . /root/lifecycle/codex-shell-helpers.sh
export PATH="/usr/local/bin:$PATH"
EOF

cat >"$HOME_DIR/.zshrc" <<'EOF'
[ -f /root/lifecycle/codex-shell-helpers.sh ] && . /root/lifecycle/codex-shell-helpers.sh
export EDITOR=vim
EOF

echo "=== bundled codex home hook install test ==="

bash "$INSTALLER" --home "$HOME_DIR" >/dev/null
bash "$INSTALLER" --home "$HOME_DIR" >/dev/null

assert_file_exists "managed hooks.json exists" "$HOOKS_FILE"
assert_file_exists "managed dispatcher script exists" "$DISPATCH_FILE"
assert_file_exists "managed session-start script exists" "$SESSION_START_FILE"
assert_file_exists "managed home autopilot fallback exists" "$HOME_AUTOPILOT_STOP_FILE"
assert_file_exists "managed home session-start fallback exists" "$HOME_SESSION_START_FILE"
assert_file_exists "shared reset script exists" "$AUTOPILOT_RESET_FILE"
assert_file_exists "shared stop core exists" "$AUTOPILOT_CORE_FILE"
assert_file_exists "shared session-start core exists" "$SESSION_CORE_FILE"
assert_file_exists "autopilot_reset skill exists" "$RESET_SKILL_FILE"
assert_contains \
  "hooks.json points to the managed home dispatcher" \
  "$HOOKS_FILE" \
  'cmux-stop-dispatch.sh'
assert_contains \
  "hooks.json installs SessionStart for workspace capture" \
  "$HOOKS_FILE" \
  'managed-session-start.sh'
assert_contains \
  "config.toml keeps unrelated config" \
  "$CONFIG_FILE" \
  'color = "blue"'
assert_contains \
  "config.toml enables codex_hooks" \
  "$CONFIG_FILE" \
  'codex_hooks = true'
assert_not_contains \
  "bashrc no longer sources stale helper overrides" \
  "$HOME_DIR/.bashrc" \
  'codex-shell-helpers.sh'
assert_not_contains \
  "zshrc no longer sources stale helper overrides" \
  "$HOME_DIR/.zshrc" \
  'codex-shell-helpers.sh'

TOTAL=$((TOTAL + 1))
CODEX_HOOKS_COUNT="$(grep -c '^codex_hooks = true$' "$CONFIG_FILE" || true)"
if [[ "$CODEX_HOOKS_COUNT" = "1" ]]; then
  echo "  PASS: installer is idempotent for codex_hooks"
  PASS=$((PASS + 1))
else
  echo "  FAIL: installer is idempotent for codex_hooks"
  FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS/$TOTAL"

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
