# Codex Tool Mapping — deep-research

deep-research is written with Claude Code tool names. When running under
OpenAI Codex CLI or the Codex App, map them to your platform equivalents.
This file is the deep-research analogue of Superpowers'
`using-superpowers/references/codex-tools.md`.

## Tool Mapping

| deep-research references | Codex equivalent |
|---|---|
| `Agent` tool (spawn research / fetch / refine agent) | `spawn_agent` |
| Multiple parallel `Agent` calls (Phase 2 fan-out) | Multiple `spawn_agent` calls |
| Agent returns its report | `wait_agent` |
| Agent finishes — free the slot | `close_agent` |
| `TodoWrite` (progress tracking, if used) | `update_plan` |
| Web search (inside search agents) | native web search tool |
| Web fetch / deep-fetch | native fetch tool |
| Context7 / DeepWiki (MCP) | same MCP tools (host-exposed) |
| `skillwiki` CLI (`path`/`lang`/`hash`/`validate`) | native shell |

## Subagent dispatch requires multi-agent support

Phase 2 fans out 2–3 web-search agents + 2–3 deep-fetch agents + optional
Context7 and DeepWiki agents — up to ~8 concurrent subagents. Codex gates
subagent spawning behind a feature flag. Add to `~/.codex/config.toml`:

```toml
[features]
multi_agent = true
```

This enables `spawn_agent`, `wait_agent`, and `close_agent`. Without it, run
the research phases sequentially in the main context — slower and higher cost,
but still functional.

Legacy note: Codex builds before `rust-v0.115.0` exposed spawned-agent waiting
as `wait`. Current Codex uses `wait_agent`; `wait` now belongs to code-mode
`exec/wait` (resumes a yielded exec cell by `cell_id`) and is NOT the
spawned-agent result tool.

## Model selection (the cost model)

deep-research's cost model pins each agent to a tier: research/fetch/refine
agents run on `sonnet` (or `haiku` for trivial single-page fetches), while
Phase 3 synthesis inherits the parent model. That mapping is Claude-Code
specific — the `model: "sonnet"` strings in `SKILL.md` are Agent-tool
parameters, not portable model IDs.

On Codex:
- If the host lets you pick a model per spawned agent, map `sonnet`/`haiku`
  → your cheap/fast tier and let synthesis run on the session's main model.
- If per-agent model selection is unavailable, accept the host default for
  spawned agents. The phase structure (parallel gather → synthesize → refine)
  still holds; only the per-tier cost optimization is lost.
- Read the intent as "cheap tier for mechanical gather/refine work," not a
  literal requirement to run Anthropic Sonnet.

## Environment Detection (vault writes / `--save`)

deep-research output is filesystem work — writing a query page, `--save <path>`,
raw captures. That is safe inside a Codex sandbox. deep-research does NOT push
git itself; vault commit/push is delegated to the host (the vault's own sync,
or dev-loop's SAVE step).

If a run does finish a vault by committing, detect the environment first with
read-only git checks:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

- `GIT_DIR != GIT_COMMON` → linked worktree (typical Codex App sandbox).
  Confirm you are not in a submodule: `git rev-parse --show-superproject-working-tree`.
- `BRANCH` empty → detached HEAD: do NOT push/branch/PR. Write the page, commit
  in place if possible, and let the user finish via the Codex App controls
  ("Create branch" / "Hand off to local").

The dev-loop `references/codex-tools.md` carries the full sandbox-finishing
contract shared across these plugins.
