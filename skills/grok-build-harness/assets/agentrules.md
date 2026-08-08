# Global Subagent Routing and Workflow Rules

These rules apply to every agent in this harness (parent and subagents),
inherited via AGENTS.md. They supplement - never override - explicit user
instructions or deeper project AGENTS.md files.

## Planning, implementation, and review workflow

- **Planning stays on the main agent (frontier).** Whether using the built-in
  `plan` subagent, `/design`, `/using-skillwiki`, superpowers brainstorming, or
  any other planning skill - the planning step must run on the main session
  agent or a `model: inherit` subagent. Never delegate planning to a `sonnet`
  subagent. The built-in `plan` agent has `model: inherit` (correct); skills
  that spawn `general-purpose` for planning inherit the `sonnet` pin (wrong) -
  override with `model:` at spawn time or run planning inline in the parent.

- **Implementation defaults to subagents on `sonnet`.** Use `general-purpose`,
  `scout`, or `explore` for code changes, exploration, and mechanical work.
  **Keep `general-purpose = "sonnet"` pinned** — bundled skills (`/implement`,
  `/execute-plan`, `/design`, `/review`) and many third-party skills spawn gp
  **without** `model:`; unpinned gp inherits the live parent (frontier cost
  leak). Scout/explore/browser-use stay pinned too. Override to parent only when
  the user explicitly asks or the task needs design judgment the plan did not
  provide.

- **Review of implementation results returns to the main agent (frontier).**
  After a subagent implements a task, the diff and test results must come back
  to the parent agent for final verdict. The parent reads the evidence, decides
  accept/reject/fix, and owns the final integration. Do not let a `sonnet`
  subagent make the final accept/reject decision on a diff it did not
  architect. Task-scoped review subagents (spec compliance, code quality) may
  run on `sonnet` as evidence gatherers, but their verdict is a recommendation
  to the parent - the parent makes the final call.

## Model routing

- **Planning and judgment inherit the parent frontier model** - the model the
  user selected for this session. Ordinary `plan` children are unpinned so they
  follow parent `/model`. Parent synthesis and final decisions stay on frontier.
- **Dirty work stays on the flash alias (`sonnet`)** - `scout`, `explore`,
  `general-purpose`, `browser-use`, research gather/refine workers, and skill
  subagents that declare or spawn with `model: sonnet`. Config pins
  (`[subagents.models]` in `~/.grok/config.toml`) and agent frontmatter enforce
  this; do not "upgrade" those children to frontier unless the user explicitly
  asks.
- Do **not** pass model/effort overrides at spawn time by default. Only restrict
  further (for example `capability_mode` or `isolation: worktree`) when the task
  demands it. Exception: when a skill spawns `general-purpose` for a planning
  or review task that should be on frontier, explicitly pass `model:` to
  override the `sonnet` pin.

## Goal mode workflow

Goal mode (`/goal`) runs in rounds on the main agent. The goal harness spawns
subagents for planning (planner), verification (skeptic panel), stall rescue
(strategist), and closing summary (summarizer).

**There is no built-in implementer subagent.** The product template
(`goal_rules.md`) says "implement it yourself", so the **built-in default**
is the main agent (frontier) writing code directly. That is **not** the
harness assignment. Implementation is dirty work (code writing) and must be
delegated to `sonnet` subagents.

### Goal phase routing (verified 2026-08-07 — pin safety over parent skeptics)

**Product naming trap:** goal `InheritCurrent` / empty `skeptic_models` does
**not** mean "parent model". It means "no runtime override", then resolution
is **pin → agent-def → parent** (`config.rs:2929-2931`, `subagent/mod.rs:660-666`).

**Do not unpin `general-purpose` to chase parent skeptics.** Evidence:

| Path | Spawns gp with `model:`? | If gp unpinned | If gp pinned sonnet |
|------|--------------------------|----------------|---------------------|
| `/goal` product implement | No implementer role — main agent "implement yourself" | Parent codes (frontier) | Same product default |
| `/goal` harness: parent spawns gp for code | Must set `model:sonnet` or pin | Parent unless model set | **Sonnet** |
| Bundled `/implement` implementer | **No model param** | **Parent/frontier leak** | **Sonnet** |
| Bundled `/execute-plan` implementer | **No model param** | **Parent leak** | **Sonnet** |
| Bundled `/design` writer | **No model param** | Parent (often OK for design) | Sonnet |
| Superpowers SDD | Docs require explicit model; omit = inherit expensive | Parent if omit | Pin if omit |
| deep-research / dev-loop workers | Usually `model: "sonnet"` | Sonnet (override) | Sonnet |
| Built-in `plan` type | Unpinned type, inherit | Parent (correct) | Parent (correct) |

**Applied policy:** keep `general-purpose = "sonnet"`. Empty skeptic pool →
**sonnet pin** (cheap verification, not live parent). Optional hardcoded
`[goal].skeptic_models` only for a **fixed** frontier id (does not track
`/model`). True "skeptics = live parent" needs a product feature
(`model = "inherit"` as runtime override) without unpinning gp.

| Phase | Who | With gp pin sonnet | Notes |
|-------|-----|--------------------|-------|
| **Planning** | Planner fork | **Live parent** | `fork_context: true` |
| **Implementation** | Main or gp spawn | **Sonnet** if gp (pin); parent if inline | Prefer spawn + pin |
| **Completion check** | Evaluator | Parent sampling | In-process |
| **Verification** | Skeptics | **Sonnet pin** | Or static `[goal] skeptic_models` |
| **Stall / summary** | Strategist / summarizer | **Sonnet pin** | Unpinned non-fork → pin |
| **Final completion** | Host | Host | `tracker.complete()` |

### Goal mode implementation delegation (required)

1. Read plan; next task.
2. Spawn `general-purpose` (sonnet via pin) for code writing — still pass
   `model: "sonnet"` when possible for clarity.
3. Review on parent; continue.
4. Skeptics (sonnet pin unless hardcoded frontier pair); host binds Achieved.

### Note on `[goal]` config

- Empty skeptic pool + gp pin ⇒ sonnet skeptics (safe, cheap).
- Hardcoded `skeptic_models model = "grok-4.5"` ⇒ static frontier (no `/model` track).
- **Never** unpin gp solely for parent skeptics — breaks skill code-writing safety.
- `use_current_model_only` does not inject parent under a pin.

## Delegation discipline

- Default to `scout` for read-only evidence packs. Built-in `explore` and `plan`
  remain available for their narrow roles. Use `general-purpose` only when the
  delegated task truly needs broader tools than a read-only scout. Prefer
  explicit `model: "sonnet"` on dirty-work gp spawns even though the pin
  already enforces it.
- Subagents perform exploration, search, and verification by default. Code
  changes, design choices, final decisions, and final validation remain the
  parent's responsibility.
- Never assign overlapping write scopes to concurrent workers; use worktree
  isolation for independent delegated edits.
- Do not create nested subagent trees. A child must return a decomposition
  request to the parent instead of spawning another child.
- Prefer one-shot disposable scouts: one child, one turn, no follow-up reuse.

## Evidence requirements

A subagent result is a lead, not an unquestioned fact. For important claims:

1. Require `file:line` references, symbol names, commands, and short verbatim
   excerpts.
2. Spot-check the returned references in the parent session.
3. Run the real shipped entry point or targeted tests when the result affects
   correctness.
4. Separate observed facts, inferences, uncertainty, and unchecked scope.

## Context discipline

- Ask scouts for compressed, evidence-dense output rather than long narrative.
- Do not paste whole files or logs into the parent when a path, line range, and
  concise excerpt are sufficient.
- Split broad exploration into independent questions instead of one vague task.
- Re-check the current workspace after long-running or parallel work.
