#!/usr/bin/env bash
# test-cursor-github-marketplace-repin.sh — status.sh against stub agent + git
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_SCRIPT="$ROOT/skills/cursor-github-marketplace-repin/scripts/status.sh"
SKILL_MD="$ROOT/skills/cursor-github-marketplace-repin/skills/cursor-github-marketplace-repin/SKILL.md"
CURSOR_MANIFEST="$ROOT/skills/cursor-github-marketplace-repin/.cursor-plugin/plugin.json"
CURSOR_MARKETPLACE="$ROOT/.cursor-plugin/marketplace.json"

[ -f "$STATUS_SCRIPT" ] || { echo "Missing status script: $STATUS_SCRIPT"; exit 1; }

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$label: expected '$needle', got: $haystack"
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$label: did not expect '$needle', got: $haystack"
}

TAG_OBJECT="b948b5c91b83b0b1c3fab8c885613a37af913e15"
TAG_PEELED="2a3be295aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OLD_OBJECT="f43eda13bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
HEAD_SHA="36b02ce96b80d73a8cf4c9f9d0d8a79b04aa2350"
OLD_HEAD="94d03d00cccccccccccccccccccccccccccccccc"

FAKE_BIN="$(mktemp -d "${TMPDIR:-/tmp}/repin-test-bin.XXXXXX")"
LIST_JSON="$FAKE_BIN/marketplace.json"
trap 'rm -rf "$FAKE_BIN"' EXIT

cat > "$FAKE_BIN/cursor-agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "plugin" && "${2:-}" == "marketplace" && "${3:-}" == "list" ]]; then
  cat "$MARKETPLACE_LIST_JSON"
  exit 0
fi
echo "unexpected agent invocation: $*" >&2
exit 1
EOF

cat > "$FAKE_BIN/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "ls-remote" ]]; then
  echo "unexpected git: \$*" >&2
  exit 1
fi
url="\${2:-}"
case "\$url" in
  *llm-wiki*)
    printf '%s\trefs/tags/v0.10.61\n' "$OLD_OBJECT"
    printf '%s\trefs/tags/v0.10.61^{}\n' "1111111111111111111111111111111111111111"
    printf '%s\trefs/tags/v0.10.62\n' "$TAG_OBJECT"
    printf '%s\trefs/tags/v0.10.62^{}\n' "$TAG_PEELED"
    ;;
  *agent-skills*)
    printf '%s\tHEAD\n' "$HEAD_SHA"
    ;;
  *)
    echo "unexpected ls-remote url: \$url" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$FAKE_BIN/cursor-agent" "$FAKE_BIN/git"

run_status() {
  local output status
  set +e
  output="$(
    PATH="$FAKE_BIN:$PATH" \
    CURSOR_AGENT_BIN="$FAKE_BIN/cursor-agent" \
    MARKETPLACE_LIST_JSON="$LIST_JSON" \
    bash "$STATUS_SCRIPT" 2>&1
  )"
  status=$?
  set -e
  printf '%s\n' "$output"
  return "$status"
}

write_list() {
  cat > "$LIST_JSON"
}

# SKILL.md documents the repo-relative script first (sibling exam pattern).
SKILL_BODY="$(cat "$SKILL_MD")"
INSTALL_SCRIPT="$ROOT/skills/cursor-github-marketplace-repin/scripts/install-keep-plugins.sh"
assert_contains "SKILL.md repo path" "$SKILL_BODY" \
  "bash skills/cursor-github-marketplace-repin/scripts/status.sh"
assert_contains "SKILL.md home path" "$SKILL_BODY" \
  "bash ~/.cursor/skills/cursor-github-marketplace-repin/scripts/status.sh"
assert_contains "SKILL.md no auto-update" "$SKILL_BODY" \
  "does not auto-update"
assert_contains "SKILL.md dashboard fallback" "$SKILL_BODY" \
  "install-keep-plugins.sh"
assert_contains "SKILL.md public ids warning" "$SKILL_BODY" \
  "are **not** the user GitHub marketplace"
[ -f "$INSTALL_SCRIPT" ] || fail "Missing $INSTALL_SCRIPT"
INSTALL_BODY="$(cat "$INSTALL_SCRIPT")"
assert_contains "helper Dashboard RPC" "$INSTALL_BODY" \
  "InstallUserPlugin"
assert_contains "helper never prints token env" "$INSTALL_BODY" \
  "Never prints tokens"
assert_contains "SKILL.md KEEP cursor-box-channel" "$SKILL_BODY" \
  "cursor-box-channel@karlorz-agent-skills"
assert_contains "helper KEEP cursor-box-channel" "$INSTALL_BODY" \
  "cursor-box-channel@karlorz-agent-skills"
assert_contains "SKILL.md KEEP rempin plugin" "$SKILL_BODY" \
  "cursor-github-marketplace-repin@karlorz-agent-skills"
assert_contains "helper KEEP rempin plugin" "$INSTALL_BODY" \
  "cursor-github-marketplace-repin@karlorz-agent-skills"
[ -f "$CURSOR_MANIFEST" ] || fail "Missing $CURSOR_MANIFEST"
assert_contains "Cursor manifest name" "$(cat "$CURSOR_MANIFEST")" \
  '"name": "cursor-github-marketplace-repin"'
MARKET_BODY="$(cat "$CURSOR_MARKETPLACE")"
assert_contains "Cursor catalog lists rempin" "$MARKET_BODY" \
  '"name": "cursor-github-marketplace-repin"'
assert_contains "Cursor catalog source" "$MARKET_BODY" \
  '"source": "skills/cursor-github-marketplace-repin"'

# Case A — both pins match latest tag object / HEAD
write_list <<JSON
[
  {"name":"llm-wiki","scope":"user","gitUrl":"https://github.com/karlorz/llm-wiki","gitRef":"$TAG_OBJECT"},
  {"name":"karlorz-agent-skills","scope":"user","gitUrl":"https://github.com/karlorz/agent-skills","gitRef":"$HEAD_SHA"}
]
JSON
OUT_A="$(run_status)" || fail "Case A: status.sh exited nonzero"
assert_contains "Case A llm-wiki" "$OUT_A" "status: PIN MATCHES latest v0.10.62 tag"
assert_contains "Case A agent-skills" "$OUT_A" "status: PIN MATCHES default-branch HEAD"
assert_not_contains "Case A no stale" "$OUT_A" "STALE"
echo "Case A passed"

# Case B — both stale; add URL comes from groups[].url without .git
write_list <<JSON
[
  {"name":"llm-wiki","scope":"user","gitUrl":"https://github.com/karlorz/llm-wiki","gitRef":"$OLD_OBJECT"},
  {"name":"karlorz-agent-skills","scope":"user","gitUrl":"https://github.com/karlorz/agent-skills","gitRef":"$OLD_HEAD"}
]
JSON
OUT_B="$(run_status)" || fail "Case B: status.sh exited nonzero"
assert_contains "Case B llm-wiki stale" "$OUT_B" \
  "status: STALE — remove then add --git-ref v0.10.62"
assert_contains "Case B llm-wiki add" "$OUT_B" \
  "plugin marketplace add https://github.com/karlorz/llm-wiki --git-ref v0.10.62"
assert_contains "Case B agent-skills stale" "$OUT_B" \
  "status: STALE — remove then add --git-ref $HEAD_SHA"
assert_contains "Case B agent-skills add" "$OUT_B" \
  "plugin marketplace add https://github.com/karlorz/agent-skills --git-ref $HEAD_SHA"
echo "Case B passed"

# Case C — missing catalog rows
write_list <<'JSON'
[]
JSON
OUT_C="$(run_status)" || fail "Case C: status.sh exited nonzero"
assert_contains "Case C llm-wiki missing" "$OUT_C" \
  "status: MISSING — skip remove; only add --git-ref"
assert_contains "Case C agent-skills missing" "$OUT_C" "== karlorz-agent-skills =="
echo "Case C passed"

# Case D — scope is not user; do not compare remotes
write_list <<JSON
[
  {"name":"llm-wiki","scope":"team","gitUrl":"https://github.com/karlorz/llm-wiki","gitRef":"$OLD_OBJECT"},
  {"name":"karlorz-agent-skills","scope":"user","gitUrl":"https://github.com/karlorz/agent-skills","gitRef":"$HEAD_SHA"}
]
JSON
OUT_D="$(run_status)" || fail "Case D: status.sh exited nonzero"
assert_contains "Case D non-user note" "$OUT_D" "scope is not user"
assert_not_contains "Case D llm-wiki not stale" "$OUT_D" "add --git-ref v0.10.62"
assert_contains "Case D agent-skills still matches" "$OUT_D" \
  "status: PIN MATCHES default-branch HEAD"
echo "Case D passed"

# Case E — marketplace list is not JSON
printf 'not-json' > "$LIST_JSON"
set +e
OUT_E="$(
  PATH="$FAKE_BIN:$PATH" \
  CURSOR_AGENT_BIN="$FAKE_BIN/cursor-agent" \
  MARKETPLACE_LIST_JSON="$LIST_JSON" \
  bash "$STATUS_SCRIPT" 2>&1
)"
STATUS_E=$?
set -e
[[ "$STATUS_E" -ne 0 ]] || fail "Case E: expected nonzero exit for invalid JSON"
assert_contains "Case E JSON error" "$OUT_E" "marketplace list is not JSON"
echo "Case E passed"

printf 'test-cursor-github-marketplace-repin: all checks passed\n'
