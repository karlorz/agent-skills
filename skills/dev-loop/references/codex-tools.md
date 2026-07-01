# Codex Tool Mapping — dev-loop

dev-loop is written with Claude Code tool names. Under OpenAI Codex CLI or the
Codex App, the `PLATFORM_DISPATCH` capability (SKILL.md § Platform Dispatch
Capability) is an instruction-level dispatch routing contract. At REFRESH, the
agent probes which dispatch tools are visible and records `DISPATCH_MODE`.
This file documents the full tool mapping table, worker inventory, and the
Codex App sandbox-finishing contract.

**If `DISPATCH_MODE = codex`**, every `Agent(...)` call in `SKILL.md` is an
instruction to use `spawn_agent(task_name=..., prompt=...)`, then
`wait_agent`, then `close_agent` when the result is needed.

## Tool Mapping

| dev-loop references | Codex equivalent |
|---|---|
| `Agent(subagent_type=X, model=…)` (spawn worker) | `spawn_agent(task_name=X, prompt=...)` after adapting the task name and prompt to the live Codex schema |
| Parallel `Agent` calls (REVIEW fan-out, IDLE maintenance) | Multiple `spawn_agent(task_name=..., prompt=...)` calls |
| Agent returns its report | `wait_agent` |
| Agent finishes — free the slot | `close_agent` |
| `Skill("name")` (invoke a skill) | skills load natively — follow the instructions |
| `TodoWrite` (task tracking) | `update_plan` |
| `Read` / `Write` / `Edit` | native file tools |
| `Bash`, `gh`, `git`, `skillwiki` | native shell |

### Worker subagents dev-loop dispatches

Spawned via the `Agent` tool with `subagent_type:` + `model: "sonnet"`. On
Codex each is a `spawn_agent(task_name=..., prompt=...)` + `wait_agent` +
`close_agent` sequence:

| Worker | Spawned at | Lane |
|---|---|---|
| `dev-loop:doctor-worker` | REFRESH step 7 | dependency + compact probe |
| `dev-loop:status-worker` | STATUS pipeline S1 (optional) | read-only `dev-loop-status.js` probe; inline `node` fallback |
| `dev-loop:research-worker` | IDLE step 4 / investigate SCAN | code + vault health scan |
| `dev-loop:simplify-worker` | REVIEW step 6 | preferred isolated adapter for `simplify:simplify` |
| `simplify:simplify` | REVIEW step 6 | required code-quality review skill; inline fallback |
| `dev-loop:codex-review-worker` | REVIEW step 6 (if enabled) | correctness/security (delegates to Codex) |
| `dev-loop:ci-health-worker` | MERGE 6b / IDLE step 3b | CI health gate |
| `playwright-cli:browser-worker` | BROWSER-VERIFY 6a | browser smoke check |

Codex custom named agents are TOML files under `~/.codex/agents/` or
`.codex/agents/`. The Claude-style markdown files under `skills/dev-loop/agents/`
are source contracts for prompts unless a verified Codex custom-agent bridge is
added. Do not assume Codex auto-discovers those markdown wrappers as named
custom agents.

## Subagent dispatch requires multi-agent support

The REVIEW step always runs `simplify:simplify`, preferably through the
`dev-loop:simplify-worker` adapter, and can optionally fan out
`codex-review-worker` as a second reviewer. IDLE maintenance spawns several
skillwiki workers. Codex gates subagent spawning behind a feature flag. Add to
`~/.codex/config.toml`:

```toml
[features]
multi_agent = true
```

This enables `spawn_agent`, `wait_agent`, and `close_agent`. Without it,
dev-loop still runs — the simplify gate falls back to inline
`Skill("simplify:simplify")`, and each optional worker step degrades to inline
execution (`Skill("dev-loop:<worker>")` or the documented inline fallback).
dev-loop's existing `DEP_DRIFT` / inline-fallback machinery already handles a
missing worker; treat "no multi_agent" the same way.

Use `codex --version` and `codex features list` to confirm that `multi_agent`
is available and enabled in the installed Codex build. Do not rely on an
uncited historical version threshold for `wait_agent`.

## Environment Detection (Codex App sandbox / detached HEAD)

The Codex App runs terminal execution inside a sandboxed, externally-managed
worktree — frequently a **detached HEAD** where branch/push/PR is blocked.
Before the git-mutating steps — MERGE 6b (`git push`, `gh pr create`,
`gh pr merge`), PUSH 10 (tag push), SAVE 7 / MERGE 6b-2 (vault push) — detect
the environment with read-only git checks:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

- `GIT_DIR == GIT_COMMON` → normal checkout. Proceed as documented.
- `GIT_DIR != GIT_COMMON` → linked worktree. Confirm it is not a submodule:
  `git rev-parse --show-superproject-working-tree` (a path means submodule —
  treat as a normal repo).
- `BRANCH` empty → **detached HEAD / externally-managed sandbox**.

## Codex App Finishing (graceful degradation)

When `BRANCH` is empty (detached HEAD in a Codex App sandbox), do NOT run
`git push`, `gh pr create`, `gh pr merge`, tag push, or vault push — they fail
or no-op. Instead:

1. Commit all staged work in place (`git add -A && git commit`) so nothing is lost.
2. Print the prepared artifacts for the user to copy into the App controls: a
   suggested branch name, the conventional-commit message, and a PR body.
3. Direct the user to the App's native controls — **"Create branch"** (then
   commit/push/PR via the App UI) or **"Hand off to local"** (transfer the
   sandbox changes to the local checkout).
4. Skip the CI gate and `verify_after_push` — there is nothing to verify until
   the user finishes via the App. Surface this in RETRO as a deferred-push note,
   not a cycle failure.

This mirrors Superpowers' `finishing-a-development-branch` reduced 3-option menu
for detached HEAD. Normal-repo and named-branch-worktree behavior is unchanged —
this is detection + degradation, not platform branching in the loop logic.

## Discovery

On Claude Code, dev-loop loads from the plugin marketplace. On Codex, place or
symlink the dev-loop skills into `~/.agents/skills/` so they auto-load. The
`.codex-plugin/plugin.json` manifest declares the plugin for Codex tooling.

## Troubleshooting: Subagents Not Working on Codex

If dev-loop cycles complete but workers always fall back to inline execution:

1. **Verify `multi_agent` is enabled:**
   ```bash
   grep -A1 '\[features\]' ~/.codex/config.toml
   # Expected: multi_agent = true
   ```

2. **Check Codex version:**
   ```bash
   codex --version
   codex features list
   ```

3. **Confirm `DISPATCH_MODE` detection:** At REFRESH, dev-loop should log
   `DISPATCH_MODE = codex`. If it logs `inline_only`, the `spawn_agent` tool
   is not being exposed — check if the Codex session loaded the plugin and
   the project is trusted.

4. **Clear stale session cache:**
   ```bash
   rm -rf ~/.codex/sessions/*
   ```

5. **Disable `multi_agent_v2` if encountering "encrypted parameters" errors:**
   ```toml
   [features]
   multi_agent = true
   multi_agent_v2 = false
   ```

6. **Test spawn_agent directly:**
   ```
   codex exec "spawn_agent a test agent to echo hello world"
   ```
   If this fails, the issue is in Codex's agent infrastructure, not dev-loop.
