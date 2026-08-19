#!/usr/bin/env bash
# test-cursor-claude-plugin-exam.sh — test cursor-claude-plugin-exam audit script against fake HOMEs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_SCRIPT="$ROOT/skills/cursor-claude-plugin-exam/scripts/audit-claude-cursor-plugins.sh"

[ -f "$AUDIT_SCRIPT" ] || { echo "Missing audit script: $AUDIT_SCRIPT"; exit 1; }

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# ==============================================================================
# Case A — healthy Claude cache, no ~/.cursor/plugins/local
# ==============================================================================
FAKE_HOME_A="$(mktemp -d "${TMPDIR:-/tmp}/audit-test-A.XXXXXX")"
trap 'rm -rf "$FAKE_HOME_A"' EXIT

mkdir -p "$FAKE_HOME_A/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki"
mkdir -p "$FAKE_HOME_A/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/.claude-plugin"
mkdir -p "$FAKE_HOME_A/.claude/plugins/cache/karlorz-agent-skills"
cat > "$FAKE_HOME_A/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "skillwiki@llm-wiki": true,
    "dev-loop@karlorz-agent-skills": true
  }
}
JSON
cat > "$FAKE_HOME_A/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "skillwiki",
  "version": "0.10.56"
}
JSON
cat > "$FAKE_HOME_A/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki/SKILL.md" <<'MD'
---
name: using-skillwiki
---
MD

OUT_A="$(HOME="$FAKE_HOME_A" bash "$AUDIT_SCRIPT")"

if echo "$OUT_A" | grep -q "GAP"; then
  fail "Case A: found forbidden GAP token in output"
fi
if echo "$OUT_A" | grep -q "ln -sfn"; then
  fail "Case A: suggested ln -sfn when Claude cache is healthy"
fi
if ! echo "$OUT_A" | grep -q "OPTIONAL.*cursor.plugins.local"; then
  fail "Case A: cursor.plugins.local should be OPTIONAL"
fi
if ! echo "$OUT_A" | grep -q "PASS.*skillwiki.cache"; then
  fail "Case A: skillwiki.cache should be PASS"
fi
echo "Case A passed"

# ==============================================================================
# Case B — Cursor marketplace pack older than Claude
# ==============================================================================
FAKE_HOME_B="$(mktemp -d "${TMPDIR:-/tmp}/audit-test-B.XXXXXX")"
trap 'rm -rf "$FAKE_HOME_A" "$FAKE_HOME_B"' EXIT

mkdir -p "$FAKE_HOME_B/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki"
mkdir -p "$FAKE_HOME_B/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/.claude-plugin"
mkdir -p "$FAKE_HOME_B/.claude/plugins/cache/karlorz-agent-skills"
cat > "$FAKE_HOME_B/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "skillwiki@llm-wiki": true
  }
}
JSON
cat > "$FAKE_HOME_B/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "skillwiki",
  "version": "0.10.56"
}
JSON
cat > "$FAKE_HOME_B/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki/SKILL.md" <<'MD'
---
name: using-skillwiki
---
MD

# Stale Cursor marketplace pack
mkdir -p "$FAKE_HOME_B/.cursor/plugins/marketplaces/github.com/karlorz/llm-wiki/a1b2c3d4/.claude-plugin"
cat > "$FAKE_HOME_B/.cursor/plugins/marketplaces/github.com/karlorz/llm-wiki/a1b2c3d4/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "skillwiki",
  "version": "0.10.47"
}
JSON

OUT_B="$(HOME="$FAKE_HOME_B" bash "$AUDIT_SCRIPT")"

if ! echo "$OUT_B" | grep -q "WARN.*skillwiki.cursor_pack_stale"; then
  fail "Case B: expected WARN for skillwiki.cursor_pack_stale"
fi
if ! echo "$OUT_B" | grep -q "Refresh or Enable Auto Refresh"; then
  fail "Case B: footer should mention Refresh or Enable Auto Refresh"
fi
if echo "$OUT_B" | grep -qi "reinstalling does not move" && ! echo "$OUT_B" | grep -qi "reinstall"; then
  fail "Case B: check reinstall logic"
fi
if ! echo "$OUT_B" | grep -q "Reinstalling does not move the snapshot"; then
  fail "Case B: expected note that reinstalling does not move snapshot"
fi
echo "Case B passed"

# ==============================================================================
# Case B2 — stale pack advertised only in marketplace.json (no plugin.json)
# ==============================================================================
FAKE_HOME_B2="$(mktemp -d "${TMPDIR:-/tmp}/audit-test-B2.XXXXXX")"
trap 'rm -rf "$FAKE_HOME_A" "$FAKE_HOME_B" "$FAKE_HOME_B2"' EXIT

mkdir -p "$FAKE_HOME_B2/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki"
mkdir -p "$FAKE_HOME_B2/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/.claude-plugin"
mkdir -p "$FAKE_HOME_B2/.claude/plugins/cache/karlorz-agent-skills"
cat > "$FAKE_HOME_B2/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "skillwiki@llm-wiki": true
  }
}
JSON
cat > "$FAKE_HOME_B2/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "skillwiki",
  "version": "0.10.56"
}
JSON
cat > "$FAKE_HOME_B2/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki/SKILL.md" <<'MD'
---
name: using-skillwiki
---
MD
mkdir -p "$FAKE_HOME_B2/.cursor/plugins/marketplaces/github.com/karlorz/llm-wiki/1c390916/.claude-plugin"
cat > "$FAKE_HOME_B2/.cursor/plugins/marketplaces/github.com/karlorz/llm-wiki/1c390916/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "llm-wiki",
  "metadata": { "version": "0.10.47" },
  "plugins": [{ "name": "skillwiki", "version": "0.10.47" }]
}
JSON

OUT_B2="$(HOME="$FAKE_HOME_B2" bash "$AUDIT_SCRIPT")"
if ! echo "$OUT_B2" | grep -q "WARN.*skillwiki.cursor_pack_stale"; then
  fail "Case B2: expected WARN when only marketplace.json carries the stale version"
fi
echo "Case B2 passed"

# ==============================================================================
# Case C — grok-search plugin with .mcp.json, no local link, no user mcp.json
# ==============================================================================
FAKE_HOME_C="$(mktemp -d "${TMPDIR:-/tmp}/audit-test-C.XXXXXX")"
trap 'rm -rf "$FAKE_HOME_A" "$FAKE_HOME_B" "$FAKE_HOME_B2" "$FAKE_HOME_C"' EXIT

mkdir -p "$FAKE_HOME_C/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki"
mkdir -p "$FAKE_HOME_C/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/.claude-plugin"
mkdir -p "$FAKE_HOME_C/.claude/plugins/cache/karlorz-agent-skills/grok-search/0.1.3"
cat > "$FAKE_HOME_C/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "skillwiki@llm-wiki": true,
    "grok-search@karlorz-agent-skills": true
  }
}
JSON
cat > "$FAKE_HOME_C/.claude/plugins/cache/llm-wiki/skillwiki/0.10.56/using-skillwiki/SKILL.md" <<'MD'
---
name: using-skillwiki
---
MD
cat > "$FAKE_HOME_C/.claude/plugins/cache/karlorz-agent-skills/grok-search/0.1.3/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "grok-search": {
      "command": "bash"
    }
  }
}
JSON

OUT_C="$(HOME="$FAKE_HOME_C" bash "$AUDIT_SCRIPT")"

if ! echo "$OUT_C" | grep -q "PASS.*grok-search.mcp"; then
  fail "Case C: grok-search.mcp should be PASS"
fi
if ! echo "$OUT_C" | grep -q "OPTIONAL.*grok-search.local_link"; then
  fail "Case C: grok-search.local_link should be OPTIONAL"
fi
if echo "$OUT_C" | grep -q "grok-search.user_mcp"; then
  fail "Case C: grok-search.user_mcp should not be present when ~/.cursor/mcp.json is missing"
fi
if echo "$OUT_C" | grep -qi "suggest.*write.*mcp.json"; then
  fail "Case C: must not suggest writing mcp.json"
fi
echo "Case C passed"

printf 'test-cursor-claude-plugin-exam: all checks passed\n'
