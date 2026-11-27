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
| `wiki_*` MCP reads/writes (vault route) | same host-exposed MCP tools |
| `skillwiki` CLI (local authoring opt-in only) | native shell, only under `references/vault-pipeline.md` opt-in |

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

## Vault routing on Codex

Vault reads and writes are platform-neutral: follow `references/vault-pipeline.md`
as the single routing home. Advertised SkillWiki MCP tools win for reads and
writes and supply the `default_vault`; do not use the Codex sandbox filesystem
as a vault writer, do not commit or push the vault, and do not fall back to a
local CLI when an MCP mutation is missing or fails. `--save` and the Phase 3
scratch parent use the same containment guard as every other host: session-known
`DEEP_RESEARCH_VAULT_ROOT` / `DEEP_RESEARCH_PROTECTED_ROOTS` plus `$HOME/wiki`
and `$HOME/wiki-git`, symlink-resolved, fail closed when the boundary inventory
is unresolved. The guard never invokes `skillwiki`; the CLI is reachable only
through the explicit local authoring opt-in.
