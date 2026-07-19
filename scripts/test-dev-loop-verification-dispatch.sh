#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VD="$ROOT/skills/dev-loop/scripts/dev-loop-verification-dispatch.js"
fail() { printf 'test-dev-loop-verification-dispatch: %s\n' "$1" >&2; exit 1; }
[[ -f "$VD" ]] || fail "missing dev-loop-verification-dispatch.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude" "$TMP/scripts"
printf '#!/bin/sh\necho ok\n' >"$TMP/scripts/check.sh"
chmod +x "$TMP/scripts/check.sh"

cat >"$TMP/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: verify-fixture
release_branch: main
verification:
  timeout_seconds: 120
  required: true
  commands:
    - kind: command
      command: "npm test"
      timeout_seconds: 90
    - "node --check skills/dev-loop/scripts/dev-loop-status.js"
  scripts:
    - kind: script
      path: "scripts/check.sh"
      timeout_seconds: 30
e2e_scripts:
  - "bash scripts/test-dev-loop-status.sh"
dispatch:
  model: "sonnet"
  platforms:
    codex:
      spawn: spawn_agent
      wait: wait_agent
      cleanup: close_agent
      isolation: worktree
    grok:
      spawn: spawn_subagent
      wait: get_command_or_subagent_output
      cleanup: kill_command_or_subagent
      isolation: worktree
```
EOF

OUT="$(node "$VD" --repo "$TMP" --format json)"
echo "$OUT" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.schema_version !== "dev-loop-verification-dispatch.v1") throw new Error("schema");
if (j.verification.default_timeout_seconds !== 120) throw new Error("default timeout");
const cmds = j.verification.commands;
const scripts = j.verification.scripts;
if (!cmds.some((c) => c.command === "npm test" && c.timeout_seconds === 90)) {
  throw new Error(`typed command timeout missing: ${JSON.stringify(cmds)}`);
}
if (!cmds.some((c) => c.kind === "command" && c.command.includes("node --check"))) {
  throw new Error("string command not classified");
}
if (!scripts.some((s) => s.path === "scripts/check.sh" && s.timeout_seconds === 30)) {
  throw new Error(`typed script missing: ${JSON.stringify(scripts)}`);
}
if (!scripts.some((s) => s.path === "scripts/test-dev-loop-status.sh" || (s.run || "").includes("test-dev-loop-status"))) {
  throw new Error(`legacy e2e script missing: ${JSON.stringify(scripts)}`);
}
const codex = j.dispatch.platforms.codex;
if (!codex || codex.ok !== true) throw new Error(`codex plan: ${JSON.stringify(codex)}`);
if (codex.spawn !== "spawn_agent" || codex.wait !== "wait_agent") throw new Error("codex spawn/wait");
if (codex.requires_claude_tools) throw new Error("codex must not require Claude tools");
const grok = j.dispatch.platforms.grok;
if (!grok || grok.ok !== true) throw new Error(`grok plan: ${JSON.stringify(grok)}`);
if (grok.spawn !== "spawn_subagent") throw new Error("grok spawn");
if (grok.requires_claude_tools) throw new Error("grok must not require Claude tools");
const claude = j.dispatch.platforms.claude;
if (!claude || claude.ok !== true) throw new Error("claude plan");
if (claude.spawn !== "Agent") throw new Error("claude spawn default");
process.stdout.write("ok-typed-verification-and-dispatch\n");
'

# Non-Claude platform must fail if forced onto Claude-only tools via config override file
mkdir -p "$TMP/bad/.claude"
cat >"$TMP/bad/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: bad-dispatch
release_branch: main
dispatch:
  platforms:
    codex:
      spawn: Agent
      wait: TaskOutput
      cleanup: none
```
EOF
set +e
OUT_BAD="$(node "$VD" --repo "$TMP/bad" --platform codex --format json)"
BAD_EXIT=$?
set -e
[[ "$BAD_EXIT" -eq 1 ]] || fail "Claude-only tools on codex must exit 1, got $BAD_EXIT"
echo "$OUT_BAD" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
const plan = j.dispatch.selected || j.dispatch.platforms.codex;
if (!plan || plan.ok !== false || !plan.requires_claude_tools) {
  throw new Error(`expected Claude-only refusal: ${JSON.stringify(plan)}`);
}
process.stdout.write("ok-non-claude-rejects-claude-tools\n");
'

# Unit-level: exported pure functions distinguish command vs script without a repo
node - "$VD" <<'NODE'
const path = process.argv[2];
const {
  normalizeVerificationEntry,
  resolveDispatch,
  PLATFORM_CAPABILITIES,
} = require(path);

const cmd = normalizeVerificationEntry({ kind: "command", command: "npm test", timeout_seconds: 15 }, 600);
if (cmd.kind !== "command" || cmd.timeout_seconds !== 15) throw new Error(JSON.stringify(cmd));
const script = normalizeVerificationEntry("scripts/foo.sh", 600);
if (script.kind !== "script" || script.path !== "scripts/foo.sh") throw new Error(JSON.stringify(script));

const codex = resolveDispatch("codex", { dispatch: {} });
if (codex.spawn !== PLATFORM_CAPABILITIES.codex.spawn) throw new Error(JSON.stringify(codex));
if (codex.requires_claude_tools) throw new Error("codex defaults must not require Claude tools");

const poisoned = resolveDispatch("codex", {
  dispatch: { platforms: { codex: { spawn: "Agent", wait: "TaskOutput" } } },
});
if (poisoned.ok !== false || !poisoned.requires_claude_tools) {
  throw new Error(JSON.stringify(poisoned));
}
process.stdout.write("ok-pure-functions\n");
NODE

printf 'test-dev-loop-verification-dispatch: all checks passed\n'
