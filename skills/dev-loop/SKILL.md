---
name: dev-loop
version: "1.24.1"
description: >
  Use this skill when the user says "run a dev cycle", "implement a feature",
  "make a code change", "start a loop", or wants automated planning, execution,
  code review, and knowledge capture. Also use for "investigate", "find work",
  "what needs doing", or "prep" to proactively queue or prepare structured
  findings. Supports /goal compatibility, Codex CLI/App, preflight prep mode,
  investigate mode, peer-aware vault sync, multi-backend code review, and
  auto-archive. v1.24.1: simple CI/main-first setup contract. v1.24.0:
  preflight prep mode for batch readiness approval.
  v1.23.2: Codex skills/ subtree
  packaging. Pass `high` for aggressive mode.
argument-hint: "[high] [prep [--limit N|--all|--lane work,captures,hygiene|--work slug]] [investigate [high] [topic]]"
---

# Dev Loop — PRD + Skillwiki (Generic Engine)

A single-pass dev cycle. When invoked, runs ONE cycle: refresh context,
load project config, pick up the next claimable work item, drive it
through the loop, exit. The PRD skill drives the work; skillwiki
captures the knowledge in two tiers — project journal and global
playbook. A pluggable interview phase (native 3-question default,
optional grill-with-docs upgrade) sharpens requirements before SPEC.
`/setup-dev-loop` provides interactive project bootstrap.

This skill is **project-agnostic**. All project specifics come from a
config file in the active repo. If no config exists, the skill
autodiscovers conventions or asks the user to bootstrap one.

## Single-Pass Semantics

- **One cycle per invocation.** Do not iterate internally.
- **Idempotent.** If no claimable work exists and nothing is in progress,
  exit with a one-line status — do not invent work.
- **Resumable.** If a previous cycle left a work item mid-step, resume
  at the next unfinished step rather than restarting.
- **Context management is harness-driven.** Claude Code auto-fires
  `/compact` at the context limit; the dev-loop controller cannot invoke
  `/compact` or `/clear` (they are user-only slash commands). Do not
  assume programmatic context management is available.

## Mode

Parse arguments for the keywords `prep` and `investigate` (case-insensitive).
If `prep` is present, set **MODE = prep**. Else if `investigate` is present,
set **MODE = investigate**. Otherwise set **MODE = core** (default).

### Argument Parsing Order

1. Check for `prep` keyword. If found, set `MODE = prep`, remove from args.
   Remaining non-`high` args are preserved as `PREP_ARGS`.
2. Check for `investigate` keyword. If found, set `MODE = investigate`, remove from args.
3. Check for `high` keyword. If found, set `INTENSITY = high`, remove from args.
4. Remaining args → `PREP_ARGS` when MODE = prep; otherwise
   `INVESTIGATE_TOPIC` (only meaningful when MODE = investigate).

Examples:
```
/dev-loop                                → MODE=core, INTENSITY=normal
/dev-loop high                           → MODE=core, INTENSITY=high
/dev-loop prep                           → MODE=prep, INTENSITY=normal
/dev-loop prep --limit 10                → MODE=prep, PREP_ARGS="--limit 10"
/dev-loop prep --lane work --work foo    → MODE=prep, PREP_ARGS="--lane work --work foo"
/dev-loop investigate                    → MODE=investigate, INTENSITY=normal
/dev-loop investigate high               → MODE=investigate, INTENSITY=high
/dev-loop investigate "plugin SDK"       → MODE=investigate, INTENSITY=normal, TOPIC="plugin SDK"
/dev-loop investigate high "plugin SDK"  → MODE=investigate, INTENSITY=high, TOPIC="plugin SDK"
```

### Mode Dispatch

After REFRESH (step 0), branch on MODE:

- **`core`** → run The Loop (steps 1–14) or IDLE DISCOVERY as documented below.
- **`prep`** → gate on `query_vault` in BACKEND_CAPS. If absent, refuse:
  "Prep mode requires a vault — run `/setup-dev-loop` to configure one."
  If present and `PREFLIGHT_POLICY.enabled != false`, run the Preflight Prep
  Pipeline below. If disabled, refuse with the config path to update.
- **`investigate`** → gate on `query_vault` in BACKEND_CAPS. If absent,
  refuse: "Investigate mode requires a vault — run `/setup-dev-loop` to
  configure one." If present, run the investigate pipeline from
  `investigate/SKILL.md`. The investigate companion shares REFRESH state
  (BACKEND_CAPS, VAULT_TYPES, DEP_DRIFT, CRITICAL_PATHS, config) — do not
  re-derive.

### Investigate Pipeline (summary)

```
┌─────────────────────────────────────────────────────────┐
│ INVESTIGATE (when MODE = investigate)                    │
│  1. QUERY     Existing work items + retros for dedup    │
│  2. SCAN      Research-worker (code + vault + transcripts)│
│  3. DEEPEN    Deep-research (high or user topic only)   │
│  4. TRIAGE    Deduplicate, rank, apply intensity cap    │
│  5. SPEC      Queue findings (schema-adaptive output)   │
│  6. RETRO     Log investigation results                 │
│  7. SAVE      Vault auto-commit                         │
└─────────────────────────────────────────────────────────┘
```

See `investigate/SKILL.md` for full step details. Key properties:
- Output: queued findings; use `status: proposed` only when the local
  schema validates it, otherwise use raw transcript captures. Humans promote
  findings to `planned` before CORE executes them.
- Tiered: concrete findings → full spec, exploratory → stub
- Dedup: slug-based + status-aware + archive check
- Cap: `max_items` (normal) or `max_items * 2` (high). Default 5/10.
- Vault required (ADR: `investigate-mode-vault-required`)

### Preflight Prep Pipeline

`/dev-loop prep` is a human-attended pre-implementation workflow. It
discovers current project work, dry-runs what an autonomous cycle would
try to pick up, batches all human questions, and writes readiness state only
after explicit approval. It never implements code and never starts `/goal`.

```
┌─────────────────────────────────────────────────────────┐
│ PREFLIGHT PREP (when MODE = prep)                        │
│  P0. REFRESH    Load config and PREFLIGHT_POLICY          │
│  P1. INVENTORY  scripts/preflight-inventory.js            │
│  P2. VERIFY     Cross-check selected items on disk/git    │
│  P3. QUESTIONS  Build one batch manifest + defaults       │
│  P4. APPROVE    AskUserQuestion in main session           │
│  P5. WRITE      Approved metadata/managed sections only   │
│  P6. VALIDATE   skillwiki validate touched specs/plans    │
│  P7. REPORT     projects/{slug}/requirements/ report      │
│  P8. SUGGEST    Suggested /goal text; do not start it     │
└─────────────────────────────────────────────────────────┘
```

**P0. REFRESH config.** Reuse normal REFRESH state. Require
`query_vault` in BACKEND_CAPS. Resolve `preflight` config into
`PREFLIGHT_POLICY` with defaults:
- `enabled: true`
- `default_limit: 5`
- `default_lanes: [work, captures, hygiene]`
- `require_approved_spec_and_plan: true`
- `unattended_not_ready_behavior: skip`
- `defaults: {}`

**P1. INVENTORY.** Run the deterministic helper from the skill directory:
```
node scripts/preflight-inventory.js \
  --project <slug> \
  --vault <vault> \
  --repo <cwd> \
  <PREP_ARGS or defaults from PREFLIGHT_POLICY>
```

Supported prep args: `--limit <n>`, `--all`, `--lane <work|captures|hygiene>`
(repeatable or comma-separated), and `--work <slug>`. Default to a small
prioritized batch. The helper returns three lanes:
- `work`: active work items (`planned`, `in-progress`) plus repairable
  legacy `proposed`/schema issues.
- `captures`: unclaimed executable raw transcripts (`kind: task|bug`).
- `hygiene`: structural/staleness findings such as missing spec/plan or
  unsupported status values.

**P2. VERIFY selected candidates.** Before asking or writing, verify every
selected candidate against current disk and git state:
- Re-read the selected `spec.md`/`plan.md` or raw transcript path.
- Compare the current sha256 to inventory output; if changed, mark the
  item stale and exclude it from writes until re-inventoried.
- Re-run `skillwiki validate` on selected specs/plans.
- Re-check lightweight git history matches surfaced by inventory to avoid
  preparing work that has already shipped.

**P3. SYNTHESIZE question manifest.** Build one batch manifest, grouped by
candidate, with recommended defaults first. Include:
- Scope, acceptance, compatibility, and execution-risk questions that would
  otherwise interrupt SPEC/PLAN/EXECUTE.
- Any repair actions required for legacy `proposed`, `in_progress`,
  missing spec/plan, missing status, or stale git evidence.
- Explicit actions per candidate: `approve`, `override`, or `defer`.
- Project-level defaults from `PREFLIGHT_POLICY.defaults`, clearly labelled
  as recommendations. Promote new stable answers into config only after
  separate explicit approval.

**P4. ASK batch approval.** Ask in the main session only. Do not spawn a
subagent for approval; AskUserQuestion is interactive and must remain in
the parent session. One approval can cover the whole manifest, but partial
approval is first-class: approved candidates proceed to P5, deferred
candidates keep or receive `preflight_state: needs_human|deferred`.

**P5. WRITE approved readiness state.** No writes are allowed before P4
approval. After approval, write only selected approved items and only:
- Managed frontmatter fields:
  `automation_ready`, `human_questions_resolved`,
  `spec_preflight_approved`, `plan_preflight_approved`,
  `preflight_state`, `last_preflight`.
- Managed body sections: `## Preflight Approval`,
  `## Automation Readiness`, and `## Open Questions`.
- Spec/plan refinements that directly encode approved execution-critical
  answers. Batch-level summaries belong under `projects/{slug}/requirements/`,
  not inside every work item.

Use a vault lock when `VAULT_SYNC_PEER_AWARE` is true. Re-read and hash each
target immediately before writing; if the hash differs from P2, skip that
target and report it as stale. Preserve unrelated frontmatter/body content.

**P6. VALIDATE touched specs/plans.** Run `skillwiki validate` for every
touched `spec.md` and `plan.md`. If validation fails, repair only the
managed edits when the fix is obvious; otherwise leave the item not-ready
and report the blocker. Do not mark an invalid item executable.

**P7. REPORT.** Write a batch report under:
`projects/{slug}/requirements/YYYY-MM-DD-dev-loop-preflight-prep.md`.
Include inventory scope, approved items, deferred items, questions answered,
defaults used, validation results, stale/hash conflicts, and remaining
automation readiness skips. This report is the project-level audit trail.

**P8. SUGGEST /goal.** Emit a suggested `/goal` command for the approved
ready batch, for example:
```
/goal "Run /dev-loop until all automation-ready planned work for project <slug> is completed, tests pass, and the vault is clean."
```
Do not start `/goal`; the user owns that lifecycle.

**Write safety contract:** inventory and validation are deterministic
tooling; synthesis and approval are prompt-driven. The preflight write phase
must satisfy all of these gates: explicit approval, selected items only,
managed frontmatter whitelist, managed body sections, hash check, vault lock
when available, and validation after write.

## Intensity Level

Parse arguments for the keyword `high` (case-insensitive). If present,
set **intensity = high**; otherwise **intensity = normal**.

Intensity applies to BOTH modes — core and investigate use the same variable.

### normal (default)

Respect priority tiers. Pick up P2+ items; only fall through to P3 when
nothing higher exists. Use idle fast-path when truly idle.

### high

Aggressive mode — **ignore priority gates entirely.** Every finding is
claimable work regardless of P-score. Specifically:

- **WORK step**: pick the top-ranked item from the backlog without
  checking its priority tier. P3 and P4+ items are treated the same as P0.
- **IDLE DISCOVERY step 5**: remove the "only P3 if no P2+" guard.
  Execute the top research recommendation unconditionally.
- **Trivial fast-path**: prefer it more aggressively — anything under
  ~80 LOC qualifies (raised from ~50).
- **Research trigger**: after idle maintenance, always invoke the
  research agent with `high` mode.
- **P3+ pickup**: in high mode there is no such thing as "only P3 left"
  — all items are equal. Do NOT exit idle when the backlog has any items.

## Model Strategy

Dev-loop spawns agents for implementation, code review, and research. To balance cost and quality, each agent-eligible step pins to a model tier matched to its complexity:

| Step | Agent | Model | Rationale |
|------|-------|-------|-----------|
| 1. QUERY | wiki-query / git search | `sonnet` (complex queries only) | Vault search and codebase exploration — mechanical lookup |
| 3. SPEC (brainstorm) | Parent session | inherit | Creative exploration, requirements gathering — benefits from parent model |
| 4. PLAN | Parent session | inherit | Architecture design, dependency mapping — benefits from parent model |
| 5. EXECUTE (subagents) | Implementation subagents | `sonnet` | Mechanical coding from plan — following spec, no architectural judgment |
| 6. SIMPLIFY | simplify-worker | `sonnet` | Code review: search, compare, pattern match — integration-level judgment |
| 6a. BROWSER-VERIFY | playwright-cli:browser-worker | `sonnet` | Browser health check — smoke routes, console errors, a11y violations |
| 6b. MERGE | gh CLI (inline) + ci-health-worker | inline + `sonnet` | PR creation (inline) + CI health gate (ci-health-worker agent) |
| IDLE: research | Research agent | `sonnet` | Code health scanning, vault coverage analysis — mechanical analysis |
| IDLE: CI health | ci-health-worker | `sonnet` | GitHub Actions run inspection, required-check verification — mechanical API queries |
| IDLE: maintenance | skillwiki skills (lint, audit, etc.) | `sonnet` (Agent spawns) | Vault maintenance: search, validate, write — mechanical, no architectural judgment |

**Steps that stay inline (not agent-eligible):** WORK, MERGE (commit + push + PR creation only), SAVE, DISTILL, AUDIT, VERIFY, RETRO, E2E, DEPLOY, PUSH — these are CLI commands, file writes, or skill invocations with low token volume. MERGE's CI health gate spawns ci-health-worker (sonnet). IDLE maintenance skills (lint, audit, crystallize, distill, decide) are now agent-eligible and run on sonnet.

**Cost impact**: ~80% of agent-eligible work (EXECUTE subagents + SIMPLIFY + MERGE CI gate + research + IDLE maintenance) runs on Sonnet. Only SPEC and PLAN benefit from parent model capability.

### Interview Capability Matrix

Interview capabilities are separate from knowledge backends — they are interactive,
session-scoped, and declared in the `interview` config section. When the `interview`
section is absent, both capabilities are off and the loop runs fully automated.

| Capability | native (built-in) | grill-with-docs | grill-me | none |
|---|---|---|---|---|
| `setup_interview` | no | yes (glossary delegate) | no | no |
| `work_item_interview` | yes (3 fixed questions) | yes (adaptive + CONTEXT.md) | yes (adaptive, no files) | no |

**Interview backends are resolved at REFRESH:**
1. Parse `interview` section from config. If absent → both capabilities off.
2. `setup_interview`: always available via bundled `setup-dev-loop` skill. If
   `grill-with-docs` is installed, the glossary section delegates to it.
3. `work_item_interview`: resolves to `native` by default. If `upgrade` is set
   (e.g., `grill-with-docs`) AND the skill is installed at
   `~/.claude/skills/<name>/SKILL.md`, the upgrade overrides native.
4. `trigger` field: `auto` (ambiguity detection), `manual` (only on `grill: true`),
   or `never` (fully automated).

**Key constraint**: AskUserQuestion is confirmed broken in subagents (Claude Code
GitHub issues #34592, #12890). All interview logic MUST run in the main session.
This matches dev-loop's existing architecture — SPEC and PLAN already run in the
parent session; EXECUTE dispatches sonnet subagents which don't need interactive tools.

### Interview Engine (Native Default)

When `work_item_interview` resolves to `native`, the GRILL step runs three fixed
`AskUserQuestion` calls in the main session:

1. **Scope**: "What's the scope of this change? What's explicitly out of scope?"
   Options: ["Feature + tests", "Bug fix only", "Refactor (no behavior change)", "Other"]
2. **Constraints**: "What constraints exist? (existing code to respect, performance requirements, compatibility concerns)"
   Options: ["None specific", "Must match existing patterns", "Performance-critical path", "Other"]
3. **Acceptance**: "How do you know it's done? What must be true?"
   Options: ["Tests pass + manual verification", "Tests pass only", "Code review approval", "Other"]

Output: a Q&A summary appended as a preamble to `spec.md` in the work item:

```markdown
## Interview Summary (native)

- **Scope**: Feature + tests — adding X with full test coverage
- **Constraints**: Must match existing patterns in <file>
- **Acceptance**: Tests pass + manual verification
```

This preamble feeds into the SPEC step — the PRD skill reads it as context before
writing the full spec. When `grill-with-docs` or `grill-me` is the backend, their
output (sharpened terminology, resolved decisions) serves the same role.

### Model Strategy (continued)

**CLAUDE_CODE_SUBAGENT_MODEL**: This env var acts as a global override — when set to a model ID, it forces ALL subagents to that model regardless of per-agent `model` parameters.

For dev-loop's tiered model strategy to work correctly, `CLAUDE_CODE_SUBAGENT_MODEL` MUST be unset or empty (`""`).

If this var is set (e.g., to `claude-sonnet-4-6`), every subagent from every skill will run on that model, and per-agent overrides are silently ignored.

The current settings.json at `~/.claude/settings.json` has `"CLAUDE_CODE_SUBAGENT_MODEL": ""` — this is correct and should stay empty for per-agent model control to function.

## System Context

| Layer | Tool | Role |
|-------|------|------|
| PRD | Pluggable via `prd_layer` config — default `superpowers`, also `codestable`, `tdd`, `manual`, `none` | Brainstorm, spec, plan, execute, review |
| Knowledge | Pluggable via `knowledge_layer` config — default `skillwiki`, also `none` | Ingest, validate, query, crystallize, distill, decide, lint, audit |
| Quality | `simplify-worker` agent (model: sonnet, spawned inline) | Pre-push code review gate |
| Hygiene | `claude-md-management:claude-md-improver` | Long-session context maintenance |
| Interview | Pluggable via `interview` config — default `native`, optional `grill-with-docs` / `grill-me` | Setup bootstrap + per-work-item grilling |

The knowledge layer is pluggable via `knowledge_layer` in the project config.
Steps branch on **capabilities**, not backend names — check `if <capability> in
BACKEND_CAPS` rather than `if knowledge_layer == "skillwiki"`. This lets new
backends slot in by declaring which capabilities they provide.

The PRD layer follows the same pattern via `prd_layer` in the project config.
Steps 3–6 branch on `PRD_CAPS` instead of naming specific skills. Pipeline
templates (`prd_pipeline`) control which steps run; `PRD_CAPS` controls which
skill to invoke per step. These are two separate concerns.

### Capability Matrix

| Capability | skillwiki | none | (future) |
|---|---|---|---|
| `query_vault` | yes | no | varies |
| `create_work_item` | proj-work | local mkdir | varies |
| `save_retro` | vault log.md | local retro.md | varies |
| `crystallize` | wiki-crystallize | write insights.md | varies |
| `distill` | proj-distill | grep retros → compound.md | varies |
| `lint_vault` | wiki-lint | project lint (if available) | varies |
| `audit_vault` | wiki-audit | verify work-item structure | varies |
| `drift_check` | skillwiki drift | check unpushed + stale branches | varies |

At REFRESH, `BACKEND_CAPS` is resolved: read `knowledge_layer` from config,
look up the backend in `knowledge_backends` (or derive defaults), and store
the set of capabilities this backend provides. Steps then check membership
in `BACKEND_CAPS` instead of testing the backend name directly.

See config template for `knowledge_backends` registry details.

### PRD Capability Matrix

| Capability | superpowers | codestable | tdd | manual | none |
|---|---|---|---|---|---|
| `brainstorm` | superpowers:brainstorming | — | — | — | — |
| `spec` | (from brainstorm) | codestable:generate | inline | — | — |
| `plan` | superpowers:writing-plans | — | superpowers:writing-plans | — | — |
| `execute` | superpowers:subagent-driven-development | codestable:generate | superpowers:test-driven-development | inline | — |
| `review` | simplify-worker (sonnet agent) | codestable:validate | superpowers:requesting-code-review | manual | — |
| `subagent_dispatch` | yes | no | no | no | no |

At REFRESH, `PRD_CAPS` is resolved alongside `BACKEND_CAPS`: read `prd_layer`
from config (default: auto-discover), look up the backend in `prd_backends`
(or derive defaults), and store the set of PRD capabilities + registered skill
names. Steps 3–6 check `PRD_CAPS` membership instead of naming specific skills.

### Orchestration Capability Set (v1.22.0)

`ORCHESTRATION_CAPS` is resolved at REFRESH, orthogonal to both `BACKEND_CAPS`
and `PRD_CAPS`. It contains only positive capabilities and detects whether the
current session is running inside a platform-provided autonomous loop (`/goal`).

| Capability | When set |
|---|---|
| `goal_context` | Conversation context contains strong evidence of an active /goal evaluator loop (evaluator feedback, active goal condition text, "continue working toward" phrasing, or explicit /goal command/status in the transcript) |
| `multi_cycle_orchestrator` | A platform loop is expected to invoke dev-loop again after this single-pass cycle exits |
| `non_interactive_goal` | Default assumption under `goal_context`: no human is waiting to answer prompts, so interactive questions should be suppressed unless config explicitly allows them |

Detection is **heuristic, not API-based** — no platform (Claude Code,
Codex, Antigravity) exposes a programmatic /goal detection mechanism
(verified May 2026). The heuristic checks:
1. System prompt or recent messages mention an active goal, completion
   condition, or evaluator in a /goal-specific context.
2. The conversation contains evaluator feedback strings ("condition not yet
   met", "continue working", "goal active").
3. The session was invoked with a `/goal` command visible in the transcript.

Avoid false positives: do **not** set `goal_context` for generic uses of the
word "goal", design discussions about /goal, or user requests to prepare a
future /goal. Require an active-loop signal, not merely documentation text.

When `goal_context` is true:
- Add `goal_context` and `multi_cycle_orchestrator` to `ORCHESTRATION_CAPS`.
- Add `non_interactive_goal` unless `interview.work_item.goal_override: allow`
  explicitly permits monitored interaction.
- Set `GRILL_TRIGGER_OVERRIDE = never` when `non_interactive_goal` is present.
- Log: "Goal context detected — interactive prompts suppressed for this cycle."
- Emit: "Running under /goal — dev-loop will complete one work item per turn.
  The /goal evaluator handles multi-cycle continuation."

When `goal_context` is false (default): no behavior change. All existing
workflows continue unchanged.

Steps that need interactive input check for `non_interactive_goal` before
calling AskUserQuestion. If present, use the documented fallback (skip, or use
config defaults).

**Automation readiness gate (unattended contexts):** When
`non_interactive_goal` is present, CORE must only select work items that are
explicitly marked ready for unattended execution. Required frontmatter:

```yaml
automation_ready: true
human_questions_resolved: true
spec_preflight_approved: true
plan_preflight_approved: true
preflight_state: ready
```

Work items missing any field, or carrying any false/non-ready value, are not
claimable in unattended mode. Skip them, continue scanning for ready work, and
emit an `Automation Readiness Skips` summary with item slugs and missing
fields. Do not stop the cycle just because not-ready work exists. The
configured `PREFLIGHT_POLICY.unattended_not_ready_behavior` defaults to
`skip`; any future behavior must remain non-interactive under `/goal`.

### Pipeline Templates

Pipeline templates control which steps run. `PRD_CAPS` controls which skill
to invoke per step. These are two separate concerns.

| Template | Steps | Use case |
|---|---|---|
| `full` | spec → plan → execute → review → merge | Default for superpowers. New features, refactors. |
| `tdd-first` | plan → execute → review → merge | Plan IS the test suite. TDD discipline during execute. |
| `single-pass` | execute → review → merge | Spec is inline from QUERY. Small features, fixes. |
| `debug-only` | execute → merge | No spec/plan. Root cause → fix → verify. |
| `manual` | (none) | User drives everything. Dev-loop is orchestrator only. |

Default pipeline per `prd_layer`:
- `superpowers` → `full`
- `codestable` → `single-pass`
- `tdd` → `tdd-first`
- `manual` → `manual`
- `none` → `manual`

Config can override: `prd_pipeline: tdd-first` even with `prd_layer: superpowers`.

### Cross-Cutting Disciplines

Cross-cutting concerns (TDD, debugging) are advisory overlays, not pipeline
stages. They are declared in `prd_disciplines` config with `when` and `mode`:

```yaml
prd_disciplines:
  - skill: superpowers:test-driven-development
    when: execute       # apply during EXECUTE step
    mode: advisory      # the execute skill decides how to use it
  - skill: superpowers:systematic-debugging
    when: failure       # invoke when EXECUTE encounters errors
    mode: reactive      # interrupt EXECUTE, invoke debugging, resume
```

`when` values: `execute`, `review`, `failure`, `always`
`mode` values: `advisory` (skill decides), `mandatory` (hard gate), `reactive` (interrupt on trigger)

## Knowledge Tiers

| Tier | skillwiki | none | When |
|---|---|---|---|
| 1 — Cycle journal | **Project wiki** (`projects/{slug}/work/.../`, vault log) | `.claude/dev-loop-work/{slug}/retro.md` | Every cycle (RETRO) |
| 2 — Generalized concepts | **Global wiki** (`concepts/dev-loop-*.md`) | `.claude/dev-loop-work/compound.md` | Every 3 cycles (DISTILL) |
| 3 — Workflow ADRs | **Project wiki** ADR (`projects/{slug}/architecture/`) | `.claude/dev-loop-work/adrs.md` | On workflow shift only |

## The Loop (Single Pass)

```
┌─────────────────────────────────────────────────────────────┐
│ PRELUDE (mandatory)                                         │
│  0. REFRESH   Reload plugins + load project config          │
│               + read CLAUDE.md + MEMORY.md                  │
├─────────────────────────────────────────────────────────────┤
│ CORE (mandatory)                                            │
│  1. QUERY     wiki-query → vault context check              │
│  2. WORK      proj-work  → create work item + redirect paths│
│  2b. GRILL    <Interview backend> → sharpen requirements    │
│  3. SPEC      <PRD skill> → spec.md at vault path           │
│  4. PLAN      <PRD skill> → plan.md at vault path           │
│  5. EXECUTE   <PRD execution skill> → implement             │
│  6. SIMPLIFY  Agent(simplify-worker, model: sonnet) → fix  │
│  6b. MERGE    PR from feature branch → main (if branch ≠   │
│               release_branch and code was committed)        │
├─────────────────────────────────────────────────────────────┤
│ OPTIONAL (run if config declares)                           │
│  7. SAVE      wiki-crystallize → session insights           │
│  8. E2E       project test suites → all must exit 0         │
│  9. DEPLOY    deploy artifacts to remote hosts (if any)     │
│ 10. PUSH      release per project config (CI publishes)     │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — single-cycle (mandatory)                         │
│ 11. RETRO     append retro to log + auto-capture findings   │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — every-3-cycles consolidation (conditional)       │
│ 12. DISTILL   proj-distill (concepts) / proj-decide (ADRs)  │
│ 13. AUDIT     claude-md-improver → CLAUDE.md updates        │
│ 14. VERIFY    audit_vault cap → provenance integrity       │
├─────────────────────────────────────────────────────────────┤
│ IDLE DISCOVERY (when CORE finds no claimable work)          │
│  Skip to POSTLUDE steps 11–14 regardless of cadence.        │
│  Then run maintenance based on BACKEND_CAPS:               │
│  - lint_vault cap: wiki-lint/audit/crystallize/distill     │
│  - no lint_vault: git gc, prune branches, project lint     │
│  Then invoke research agent (see research/SKILL.md).      │
│  Exit with one-line summary of what was done.               │
└─────────────────────────────────────────────────────────────┘
```

## Step Details

### 0. REFRESH — context hygiene + config load (mandatory, ~15s)

1. **Hot-reload drift guard** — before any other step, detect whether the
   skill source has drifted from the cached version:
   - Hash the cached SKILL.md from `~/.claude/plugins/cache/<plugin>/dev-loop/<version>/SKILL.md`
   - Hash the source SKILL.md at the skill repo (known from plugin manifest or CWD)
   - Compare to `LAST_SKILL_HASH` from the previous cycle (absent on first cycle)
   - **Three states:**
     - `in_sync`: cache hash == source hash → proceed normally
     - `drifted_reloaded`: cache hash changed from LAST_SKILL_HASH (user ran
       `/reload-plugins`) → warn: "SKILL.md updated — running new version",
       update LAST_SKILL_HASH, proceed
     - `drifted_stale`: source hash != cache hash AND cache hash == LAST_SKILL_HASH
       → **block the cycle**: "Source SKILL.md has edits not yet loaded.
       Run `/reload-plugins` before continuing this cycle."
   - Store cache hash as `LAST_SKILL_HASH` after check.
   - **Session-start warning**: on the first cycle of a new session, if the
     cache hash differs from what `LAST_SKILL_HASH` would be (i.e., the
     skill was reloaded between sessions), emit a one-line note:
     "Skill version changed since last session — running updated SKILL.md."
     This surfaces drift that occurs between sessions, not just mid-session.

2. **Reload plugins** — run `/reload-plugins` to pick up any skill or
   command changes from prior cycles. Skip on first cycle if no edits.

3. **Load project config** in this order:
   - **Primary**: read `./.claude/dev-loop.config.md` (relative to CWD).
     Parse the YAML-style fields described in `templates/project-config.md`.
     Parse `knowledge_layer` (default: `skillwiki`). Then resolve
     `BACKEND_CAPS` — read the `knowledge_backends` map if present in
     config (see templates/project-config.md for schema); otherwise derive
     defaults from `knowledge_layer` + `vault` fields.
     Then resolve `PRD_CAPS` — read `prd_layer` from config. If absent,
     auto-discover: if `superpowers:brainstorming` is available →
     `superpowers`; else if `superpowers:test-driven-development` is
     available → `tdd`; else → `manual`. Read `prd_backends` map if
     present; otherwise derive defaults from `prd_layer`. Store the set
     of PRD capabilities and registered skill names as `PRD_CAPS`.
     Resolve `prd_pipeline` (default per `prd_layer`, override from config).
     Store as `PRD_PIPELINE`. Resolve `prd_disciplines` if declared:
     parse `include_paths` and `exclude_paths` on each discipline entry
     (both are optional — omit for global scope). Warn if a discipline has
     `mode: mandatory` without `include_paths`: "<skill> is mandatory
     globally — consider scoping with include_paths." This is a warning,
     not an error — the discipline still runs. Backwards compat: omitted
     `include_paths` = matches all changed files (current behavior).
     Store disciplines in priority order as `PRD_DISCIPLINES`.
     **Resolve interview backends** — parse the `interview` section from
     config. If absent → `setup_interview` and `work_item_interview` both
     absent from BACKEND_CAPS (loop runs fully automated). If present:
     - Parse `interview.setup` — `setup_interview` ∈ BACKEND_CAPS. Backend:
       `setup-dev-loop` (bundled). If `glossary: grill-with-docs` is set AND
       `~/.claude/skills/grill-with-docs/SKILL.md` exists, delegates glossary
       section to it.
     - Parse `interview.work_item` — `work_item_interview` ∈ BACKEND_CAPS.
       Resolve backend: check if `upgrade` is set AND installed at
       `~/.claude/skills/<upgrade>/SKILL.md` — if yes, backend = upgrade
       skill name; otherwise backend = `native`. Store as
       `INTERVIEW_BACKEND`.
     - Parse `interview.work_item.trigger` — store as `INTERVIEW_TRIGGER`
       (`auto`, `manual`, or `never`).
     - Parse `interview.work_item.goal_override` — store as
       `INTERVIEW_GOAL_OVERRIDE` (`never` or `allow`, default `never`).
     **Resolve `ORCHESTRATION_CAPS`** — inspect the current system context and
     recent transcript for active /goal-loop signals (see Orchestration
     Capability Set). If strong evidence is present, add `goal_context` and
     `multi_cycle_orchestrator`. Add `non_interactive_goal` unless
     `INTERVIEW_GOAL_OVERRIDE == allow`. Do not set any goal capability for
     generic mentions of "goal" or for discussions about setting a future
     /goal.
     **Resolve CI discovery** — parse `ci_configured` and `ci_discovery`
     from config. If `ci_configured: true`:
     - `ci_discovery: runtime` (default) → store `CI_DISCOVERY = runtime`,
       `REQUIRED_CHECKS = []` (discovered at MERGE time via API).
     - `ci_discovery: explicit` → store `CI_DISCOVERY = explicit`,
       `REQUIRED_CHECKS = required_checks` list from config.
     If `ci_configured: false` or absent → `CI_DISCOVERY = none`,
     `REQUIRED_CHECKS = []`.
     **Resolve `critical_paths`** — parse into `CRITICAL_PATHS` dict (name →
     `{code, vault, history_pins}`). Absent or empty → `{}` (equal priority).
     Schema: see `templates/project-config.md` § Critical paths. Setup flow:
     `setup/SKILL.md` Section G.
     **Resolve `fact_check`** — parse into `FACT_CHECK_CAPS` (`source_order`,
     `web_available` bool after validating `web_tools.primary` against installed
     MCP tools, `evidence_contract`). Absent or `enabled: false` → `{}`. Pass to
     SPEC/PLAN steps. Schema: `templates/project-config.md` § Fact-check tier.
     Setup flow: `setup/SKILL.md` Section H.
     **Resolve `code_review`** — parse the `code_review` block (since v1.15.0).
     Build `CODE_REVIEW_BACKENDS` session list (order: always-on backends
     first, optional backends appended per intensity gate):
     - Always include `dev-loop:simplify-worker` (base backend).
     - If `intensity == normal` AND `code_review.codex.enabled_in_normal: true`
       AND `dev-loop:codex-review-worker` ∉ `DEP_DRIFT` AND
       `codex:codex-rescue` ∉ `DEP_DRIFT` → append `dev-loop:codex-review-worker`.
     - If `intensity == high` AND `code_review.codex.enabled_in_high: true`
       AND both refs not in `DEP_DRIFT` → append `dev-loop:codex-review-worker`.
     - If `code_review` block absent → defaults to base-only (preserves
       pre-v1.15.0 behavior).
     Schema: `templates/project-config.md` § Code review. Setup flow:
     `setup/SKILL.md` Section M.
     **Resolve `vault_auto_commit`** — read from config, default `true`.
     Store as session variable `VAULT_AUTO_COMMIT`. When true, SAVE step 7
     commits dirty vault files; AUDIT step 13 warns if tree is dirty.

     **Resolve `vault_sync`** — parse the `vault_sync` block from config.
     - If block is absent: default `peer_aware: true` when `vault_auto_commit: true`,
       otherwise `false`. Default `lock_timeout_seconds: 30`, `retry_budget: 3`.
     - If `peer_aware: false` (explicit or defaulted) → store `VAULT_SYNC_PEER_AWARE = false`.
     - If `peer_aware: true` AND `query_vault` in BACKEND_CAPS:
       - Verify skillwiki >= v0.6.0 by checking for `--acquire-lock` flag:
         `skillwiki sync --help 2>/dev/null | grep -q "acquire-lock"`
       - If available → store `VAULT_SYNC_PEER_AWARE = true`,
         `VAULT_SYNC_LOCK_TIMEOUT = lock_timeout_seconds` (default 30),
         `VAULT_SYNC_RETRY_BUDGET = retry_budget` (default 3).
       - If skillwiki < v0.6.0 → store `VAULT_SYNC_PEER_AWARE = false`,
         emit one-time warning: "vault_sync.peer_aware requires skillwiki
         >= v0.6.0 — upgrade skillwiki to enable peer-aware vault push."
     Always initialize `VAULT_SYNC_DEFERRAL_COUNT = 0` at cycle start
     (per-cycle scope — not session-scoped).
     **Resolve `presync_skill`** — parse from `vault_sync.presync_skill`:
     `auto-detect` (default), `always`, or `never`. Store as
     `VAULT_SYNC_PRESYNC_SKILL`. When `auto-detect`, probe
     `$VAULT/.claude/skills/wiki-presync/SKILL.md` at cycle start;
     cache result as `VAULT_PRESYNC_AVAILABLE` (bool).

     **Resolve `investigate`** — parse the `investigate` block from config.
     - If block is absent → store `INVESTIGATE_MAX_ITEMS = 5`,
       `INVESTIGATE_TOPIC_SEEDS = []` (will fall back to
       `idle_deep_research.topic_seeds` at runtime).
     - If block present: read `max_items` (default 5), `topic_seeds`
       (default []). Store as session variables.
     - Investigate mode itself is always available when `query_vault` in
       BACKEND_CAPS — the config section only controls tuning parameters.

     **Resolve `preflight`** — parse the `preflight` block from config.
     Store as `PREFLIGHT_POLICY`. If the block is absent, use:
     `enabled: true`, `default_limit: 5`,
     `default_lanes: [work, captures, hygiene]`,
     `require_approved_spec_and_plan: true`,
     `unattended_not_ready_behavior: skip`, and `defaults: {}`.
     Validate `default_limit` is a positive integer and `default_lanes`
     only contains `work`, `captures`, and `hygiene`; fall back to defaults
     with a warning for invalid values. `PREFLIGHT_POLICY` controls
     `/dev-loop prep` inventory defaults and unattended readiness skip
     behavior, but prep mode itself still requires `query_vault` in
     BACKEND_CAPS.

     **Resolve `release_policy`** — parse the `release_policy` block from config.
     - If block is absent → store `RELEASE_POLICY = None`. PUSH step uses
       pre-1.19.0 behavior (no auto-bump; user/upstream bumps manifests
       before the cycle reaches step 10).
     - **Advisory**: when `release_policy` block is absent AND `publish_via`
       is set to a non-`none` value, emit one-line advisory: "PUSH step
       configured (publish_via={value}) but release_policy block is absent
       — version bump must occur before step 10. Add release_policy with
       auto_bump: true to enable automated bumping."
     - If block present, store as `RELEASE_POLICY` dict with fields:
       - `auto_bump` (bool, default `false`)
       - `channel` (string: `beta` | `stable`, default `stable`) — passed
         to `bump_script` as a hint; dev-loop does NOT compute version strings
       - `trigger_globs` (list of glob patterns; required when
         `auto_bump: true`). Patterns use shell-style glob with `**`
         for recursive path matching (Python `glob` semantics), relative
         to repo root. Example: `skills/**` matches any file under
         `skills/` at any depth; `.claude-plugin/marketplace.json`
         matches exactly that file.
       - `skip_globs` (list of glob patterns; default `[]`). Same
         semantics as `trigger_globs`. Files matching both trigger and
         skip are treated as skipped.
       - `tag_format` (string template, default `v{version}`) — consumed
         by `bump_script`/tag-push logic, not by dev-loop directly
       - `verify_after_push` (bool, default `true`)
     - Validation: when `auto_bump: true` AND `trigger_globs` is empty or
       absent, emit warning "release_policy.auto_bump is true but
       trigger_globs is empty — no commit will ever trigger a bump.
       Disabling auto_bump for this cycle." and treat as `auto_bump: false`.
     - Validation: when `auto_bump: true` AND `bump_script` path does not
       exist, emit warning "release_policy.auto_bump is true but
       bump_script '{path}' not found — auto-bump will fail at PUSH step."
       Do NOT downgrade auto_bump; the script may be created before PUSH.
     Schema: `templates/project-config.md` § Release policy. Setup flow:
     `setup/SKILL.md` Section N.

     If `query_vault` in
     BACKEND_CAPS, discover vault type directories by
     reading `{vault}/SCHEMA.md` — parse the `## Layers` section for
     lines like `- entities/, concepts/, ...` ending in `/`. Store as
     `VAULT_TYPES` session variable.
     If SCHEMA.md is missing or unparseable, fall back to listing
     subdirectories of `{vault}/` that contain `.md` files.
     Store these as session variables for conditional step logic.
   - **Fallback 1**: extract from `CLAUDE.md` body where possible:
     `slug` (parent dir basename), `vault` (first `~/wiki` tilde-path
     or run `skillwiki path` if available), `knowledge_layer` (default
     `skillwiki` if vault exists, `none` otherwise — then derive
     BACKEND_CAPS from it), `prd_layer` (default `superpowers` if
     superpowers skills are available, else `manual` — then derive
     PRD_CAPS from it),
     `cli_src`/`cli_test` (first `packages/*/src/commands/` or
     `src/commands/` match), `skills_glob`
     (`packages/skills/*/SKILL.md` if exists), `release_branch`
     (regex `default branch`, else `main`), `e2e_scripts`
     (regex `e2e-*.sh` excluding `e2e-common.sh`),
     `manifests_count`/`remote_hosts` (regex/grep).
     `cli_entry_override` is NOT recoverable → leave empty.
   - **Fallback 2**: introspect repo conventions:
     - CLI src: `packages/*/src/commands/`, `src/commands/`, or `cli/`
     - Skills glob: `packages/*/SKILL.md` or `skills/*/SKILL.md`
     - E2E scripts: `scripts/e2e-*.sh` or `test/e2e/*.sh`
     - Vault: run `skillwiki path` if available; else `~/wiki` if it
       exists; else skip vault-dependent steps
     - Knowledge layer: `skillwiki` if vault exists AND `skillwiki doctor`
       passes; else `none` — then derive BACKEND_CAPS from the resolved
       knowledge layer
   - **Fallback 3**: if critical fields (slug) cannot be resolved,
     default to `playground` as the slug. This ensures the PRD bridge
     chain always has a target — `proj-work` emits redirect paths, and
     `superpowers:brainstorming` / `superpowers:writing-plans` can fire
     normally. If `knowledge_layer` also cannot be determined, default
     to `none` and proceed with git-based alternatives.

3. **Read CLAUDE.md and MEMORY.md fresh** — the system-prompt copy
   loaded at session start goes stale if a prior cycle edited them.

   First cycle in a session that hasn't edited skills or CLAUDE.md can
   skip step 1 (plugin reload) as a no-op, but must always do step 2
   (config) and step 3 (CLAUDE.md/MEMORY.md re-read).

3b. **Discover vault types from SCHEMA.md** (only if `query_vault`
   in BACKEND_CAPS). Read `{vault}/SCHEMA.md` and parse the `## Layers`
   section. Extract backtick-wrapped directory names ending in `/`
   (regex: `` `(\w+)/` ``), then exclude `raw` and `projects`
   (Layer 1 and Layer 3). Store the remaining names as `VAULT_TYPES`
   (space-separated). This replaces any hardcoded list — different
   vault schemas (Hermes v2.1 has 4 types, skillwiki has 5) are
   handled automatically.
   If SCHEMA.md is missing, fall back to listing vault-root
   subdirectories (excluding `raw`, `projects`, `_archive`, hidden
   dirs) — these are likely type dirs.
   If `query_vault` not in BACKEND_CAPS, skip (no vault to discover).

4. **CLI version alignment** — if `query_vault` in BACKEND_CAPS and the
   project has a local skillwiki build (detected by `cli_entry_override`
   in config or `packages/cli/package.json` existing), compare the local
   version with the globally installed `skillwiki --version`. If they
   differ, use `npx skillwiki` (or the `cli_entry_override`) for all
   skillwiki invocations in this cycle. A stale global binary can
   produce false lint warnings and miss new schema detections.
   Skip if `query_vault` not in BACKEND_CAPS.

5. **Quick health check** — if `query_vault` in BACKEND_CAPS, run
   `skillwiki doctor` to catch environment issues early (missing vault,
   stale plugin, config errors). If doctor reports errors, fix them
   before proceeding — they will block later steps.
   Skip if `query_vault` not in BACKEND_CAPS.

6. **Scan for ad-hoc captures** — if `query_vault` in BACKEND_CAPS,
   check `raw/transcripts/` for new files since the last cycle. These
   are unprocessed captures from Obsidian or `/wiki-add-task`. If found,
   treat them as claimable work items alongside QUERY results.
   If `query_vault` not in BACKEND_CAPS, skip (no vault transcripts
   directory to scan).

7. **Dependency doctor + compact-pressure probe** — spawn
   `dev-loop:doctor-worker` (sonnet). The worker runs two probes per call:
   (a) probe `dependencies.yaml` installation paths, (b) probe the current
   session's `~/.claude/projects/<slug>/<uuid>.jsonl` for
   `"isCompactSummary":true` markers (auto-compact firings the harness
   recorded). Skip when `SKIP_DOCTOR=true` env var is set.

   ```
   Agent(description: "Dev-loop dep + compact doctor", subagent_type: "dev-loop:doctor-worker", model: "sonnet", prompt: "Probe skills/dev-loop/dependencies.yaml AND auto-compact count for the current session. Report JSON with status, missing_required[], missing_optional[], compact_count, session_jsonl_path.")
   ```

   **Behavior on dependency status:**
   - `broken` → BLOCK the cycle. Print missing required refs + install hints.
   - `degraded` → warn once per missing optional ref; store `DEP_DRIFT` set.
   - `healthy` → proceed.

   **Behavior on `compact_count`** (tuned v1.20.0 — single auto-compacts in
   long-running loops are normal; previous thresholds escalated too aggressively):
   - `0` → one-line proactive emit: "Auto-compact monitor active — 0 firings
     this session (full context)." Always shown so users know the probe is
     wired before pressure arrives.
   - `1` → one-line emit: "Auto-compact monitor — 1 firing this session.
     Earlier observations may have lost detail; monitoring continues."
   - `2` → note: "Auto-compact has fired 2x this session. Consider /clear at
     the next natural breakpoint to reset context."
   - `3` → stronger warning: "Auto-compact has fired 3x — recommend ending
     this session after the current cycle completes."
   - `>= 4` → refuse to start the cycle without explicit user confirmation:
     "Auto-compact has fired 4+ times — significant context loss. Start a
     fresh session for reliable multi-step work."
   - `null` (probe error) → log the error; do not block.

   **HUD bridge (v1.20.0)** — `doctor-worker` writes the latest probe result
   to `~/.claude/dev-loop/last-doctor.json` on every cycle. External HUDs
   (ccstatusline custom widgets, terminal polls) can read this file without
   coupling into the dev-loop controller. Shape: `{compact_count, dep_status,
   session_jsonl_path, cycle_ts}`. See `agents/doctor-worker.md` § HUD bridge
   for the consumer contract.

   Steps depending on optional capabilities (BROWSER-VERIFY 6a, GRILL 2b,
   IDLE step 4.5 deep-research, SAVE step 7 crystallize, AUDIT step 13,
   N9 archive) check `DEP_DRIFT` membership before invoking the external
   ref and apply the documented fallback if drifted.

   Schema: `dependencies.yaml`. Probe logic: `agents/doctor-worker.md`.

### 1. QUERY — context check (mandatory)

**If `query_vault` in BACKEND_CAPS:**
For complex vault queries spanning multiple type directories or requiring
cross-reference synthesis, delegate to a sonnet agent with `model: "sonnet"`:
```
Agent(description: "Vault context search", model: "sonnet", prompt: "Search the vault for prior specs, plans, concepts, decisions overlapping: <task>. Use wiki-query for ranked search. Report top candidates with relevance rationale.")
```
For simple single-term lookups, run inline — no agent spawn needed.

Search the vault (resolved from `vault` config field) for prior specs,
plans, concepts, decisions overlapping the task. Feed results into the
PRD skill's exploration step. Skip if `vault` is empty.

**Critical-path vault bias:** If `CRITICAL_PATHS` is non-empty, include
the slugs listed under `CRITICAL_PATHS.*.vault` as priority search terms
in the vault query. Results matching critical-path vault pages are
ranked above general results.

**Uncited raw check (mandatory when `query_vault` in BACKEND_CAPS):** After wiki-query,
scan for uncited raw articles that have no downstream concept page
citations. If found, treat them as claimable work items alongside any
QUERY results. Prioritize: uncited raw > other work.

**Automation readiness filter (mandatory when `non_interactive_goal` in
ORCHESTRATION_CAPS):** When building the claimable work set, include only
items with all readiness gates set:
`automation_ready: true`, `human_questions_resolved: true`,
`spec_preflight_approved: true`, `plan_preflight_approved: true`, and
`preflight_state: ready`. Skip every other planned/in-progress candidate and
continue looking for ready work. Emit an `Automation Readiness Skips` block
listing skipped slugs and missing/non-ready fields. If no ready work remains,
fall through to the normal idle/goal continuation reporting instead of asking
the user a question.

When `non_interactive_goal` is absent, preserve attended fallback behavior:
warn before selecting an item without readiness metadata, then allow the
existing GRILL/SPEC/PLAN interactive path. Include a recommendation to run
`/dev-loop prep <project>` for future batches instead of resolving questions
one at a time.

**If `query_vault` not in BACKEND_CAPS:**
Use git-based context: `git log --oneline -20` for recent activity,
`git diff --stat HEAD~5` for recent changes, and `grep -r` across the
codebase for terms related to the current task. Feed results into the
PRD skill's exploration step. No vault context available — the PRD
skill works from code and git history alone.

Note: `skillwiki drift` is deferred to IDLE DISCOVERY (step 3) because
it makes network calls and is expensive for the QUERY step.

**Stale-premise check (mandatory, runs regardless of BACKEND_CAPS):**
When the user invocation names specific transcript paths/filenames or
distinctive topic labels, cross-check against archived state before
treating them as claimable work. Three signals:

1. **Named transcript paths.** Extract any string in the prompt matching
   `raw/transcripts/*.md` (full or filename-only). For each, check both
   `<vault>/raw/transcripts/` AND `<vault>/_archive/raw/transcripts/`.
   If the file is in `_archive/` (or any matching basename), surface:
   "Named transcript X is archived — work likely already shipped. Look
   up the archive commit (e.g., `git -C <vault> log --oneline -- _archive/raw/transcripts/<name>`)
   for context." Without a vault (`query_vault` not in BACKEND_CAPS),
   skip this signal.

2. **Distinctive topic labels.** Extract topic keywords from the prompt
   that are concrete enough to grep for. Heuristic:
   - Section letter labels (single letters `A–Z`, or ranges like
     `G-L`) — always concrete.
   - Hyphenated slugs (3+ chars total, ≥1 hyphen): `auto-archive`,
     `codex-probe`, `runtime-probe`.
   - Lowercase feature names (4+ chars, no spaces, not in a tiny stop
     list of `the/and/for/with/from`).
   - Skip single common words under 4 chars and natural-language
     filler.

   Run `git log --oneline -30 --grep="<label>"` on the active repo. If
   matching commits exist, surface: "Topic '<label>' appears in N
   commits since <oldest match> (<hashes>). May be re-discovery of
   shipped work — confirm with user."

3. **Combination gate.** If BOTH Signal 1 (named transcripts in archive)
   AND Signal 2 (topic commits exist) fire → treat as strong
   stale-premise. STOP before WORK step and ask the user via
   `AskUserQuestion` (the QUERY step runs in the main session, so this
   is safe): "Multiple signals indicate this work may already have
   shipped. Continue anyway, or stop?"

   If only one signal fires, **surface but proceed**. The user may
   want re-investigation, refactor, or follow-up. Do not block on a
   single signal.

Stale-premise checks are cheap (one filesystem glob + one git log per
prompt-named term) and run before WORK step. They prevent the
recurring re-discovery loop observed when a stale cron prompt or
manual invocation names work that has already shipped.

### 2. WORK — create work item (mandatory)

**If `create_work_item` in BACKEND_CAPS (skillwiki path):**
Create or open a work item under
`{vault}/projects/{slug}/work/YYYY-MM-DD-{work-slug}/`. proj-work emits
redirect paths for `spec.md` and `plan.md`. Pass these to steps 3–4.

proj-work validates frontmatter (see its SKILL.md for required fields:
`title`, `name`, `description`, `kind`, `status`, `priority: high|medium|low`,
`project: "[[slug]]"` wikilink format, timestamps, provenance).

**`closes:` convention (optional):** If this work item originated from
ad-hoc captures discovered in REFRESH step 6 (or otherwise referenced
specific raw transcripts), record their vault-relative paths under a
`closes:` list in the spec.md frontmatter:

```yaml
closes:
  - raw/transcripts/2026-05-22-idea-foo.md
  - raw/transcripts/2026-05-22-bug-bar.md
```

RETRO step 11 reads this list and archives the entries via
`skillwiki archive` when the cycle flips status to `completed`, so they
stop re-surfacing as new captures next cycle. Omit `closes:` (or leave
it empty) when the work item didn't originate from transcripts. See
RETRO § Archive originating transcripts for archival semantics.

**Critical-path priority escalation:** After creating the work item, check
whether the work item description, spec, or any referenced files match a
glob or path under `CRITICAL_PATHS.*.code`. For resuming work items
(check for prior commits), also intersect changed files with critical
paths. If matched, automatically set the work item's `priority: high`
regardless of the original priority. Log the escalation: "Priority
escalated to high — touches critical path: <name>."

**If `create_work_item` not in BACKEND_CAPS (git-local path):**
Create a local work item under `.claude/dev-loop-work/YYYY-MM-DD-{work-slug}/`
in the project repo. Create `spec.md` and `plan.md` in that directory.
Pass these local paths to steps 3–4. No vault frontmatter needed — use
a simple YAML header with `title`, `status`, `kind`, and `created` date.

**Gitignore:** `.claude/dev-loop-work/` contains session artifacts, not
repo content. Ensure it's listed in `.gitignore` when running in `none`
mode. The project-config template includes a Gitignore section for this.
When `reactive_debugging` config is present, also ensure
`reactive_debugging.evidence_dir` (default `.claude/dev-loop-debug/`)
is in `.gitignore` — evidence captures are session artifacts, not repo
content.

### 2b. GRILL — interview phase (conditional on `interview` config + ambiguity)

**Skip if** `work_item_interview` capability is absent (no `interview` section in config).

**Goal-context override (v1.22.0):** If `goal_context` in `ORCHESTRATION_CAPS`:
- Check config `interview.work_item.goal_override` (default: `never`).
- If `goal_override: never` → skip GRILL entirely. Log: "GRILL skipped —
  running under /goal context. Requirements should be clarified BEFORE
  setting the goal (see /goal Integration section)."
- If `goal_override: allow` → proceed with normal trigger logic below
  (backward-compatible; useful when the user intentionally runs grill-me
  inside a /goal session with manual monitoring).

This override exists because interactive skills (AskUserQuestion, grill-me)
are counterproductive under unattended /goal evaluators — a human may not be
monitoring, and the evaluator loop will keep triggering turns regardless of
interview state.
The recommended pattern: run `/grill-me` and `/dev-loop prep` BEFORE setting
`/goal`, so questions are answered in one attended batch.

**Trigger decision (standard, when goal_override does not apply):**
- `trigger: never` → skip. Fully automated mode.
- `trigger: manual` → run only if work item has `grill: true`. Skip otherwise.
- `trigger: auto` (default) → run ambiguity detection:
  1. If work item has `grill: true` → force interview
  2. If work item has `grill: false` → skip interview
  3. If unset → run pre-spec scan:
     - Scan vault for conflicting prior decisions (≥2 on same topic) → ambiguous
     - Check for zero prior art on the topic → ambiguous
     - Detect vague language in work item description ("improve", "fix stuff", "refactor things") → ambiguous
     - None of the above → skip interview

**Backend resolution (from REFRESH):**
- `native` → invoke inline AskUserQuestion (see Interview Engine section)
- `grill-with-docs` → invoke `Skill("grill-with-docs")` in main session.
  If `grill-with-docs` is in `DEP_DRIFT`, fall back to `native`.
- `grill-me` → invoke `Skill("grill-me")` in main session.
  If `grill-me` is in `DEP_DRIFT`, fall back to `native`.

**IMPORTANT**: GRILL MUST run inline in the main session. Do NOT spawn a subagent
for this step. AskUserQuestion is broken in subagents. The Skill tool works in the
main session and can load external interview skills.

**Output**: Interview findings (Q&A summary for native, sharpened terminology +
decisions for grill-with-docs) are prepended to the work-item spec preamble.
This feeds directly into the SPEC step.

### 3. SPEC — spec artifact (conditional on `prd_pipeline` + `PRD_CAPS`)

**If `spec` step is NOT in the active pipeline template:** skip to step 4.

**If `spec` step IS in the active pipeline template:**

- **`brainstorm` in PRD_CAPS:** Invoke the registered brainstorm skill
  (from `prd_backends` registry) with work-item context. Output: `spec.md`
  at redirect path.
- **`spec` in PRD_CAPS (but not `brainstorm`):** Invoke the registered
  spec skill. Output: `spec.md` at redirect path.
- **Neither in PRD_CAPS:** Inline spec from QUERY results + work item
  description. Output: `spec.md` (minimal).

**Fact-check integration:** If `FACT_CHECK_CAPS` is non-empty, pass the
source order and evidence contract to the invoked PRD skill. The PRD skill
should consult sources in declared order (local_repo → context7 → vault →
web) when writing specs that involve version-sensitive claims, API
contracts, or deprecation notices. Also pass configured `triggers` —
free-text patterns that, when matched in the work item description,
force fact-checking even for otherwise simple specs. This ensures
version claims, CVE checks, and deprecation notices always get
fact-checked. Output specs must include a `## Sources Used` section if
`evidence_contract.require_sources_used_section` is true.

### 4. PLAN — plan artifact (conditional on `prd_pipeline` + `PRD_CAPS`)

**If `plan` step is NOT in the active pipeline template:** skip to step 5.

**If `plan` step IS in the active pipeline template:**

- **`plan` in PRD_CAPS:** Invoke the registered plan skill with `spec.md`.
  Output: `plan.md` at redirect path.
  Pass `FACT_CHECK_CAPS` (source order, web available, evidence contract)
  same as SPEC — the plan skill consults the same source order when
  making architectural decisions about library versions, API contracts,
  or deprecation risks.
- **`plan` not in PRD_CAPS:** Inline plan from `spec.md`. Output:
  `plan.md` (minimal, derived from spec).

### 5. EXECUTE — implementation (conditional on `prd_pipeline` + `PRD_CAPS`)

**If `execute` step is NOT in the active pipeline template:** skip to step 6
(manual pipeline — user drives implementation).

**If `execute` step IS in the active pipeline template:**

- **`execute` in PRD_CAPS:** Invoke the registered execute skill with
  `plan.md` (or `spec.md` if no plan). If `subagent_dispatch` in
  PRD_CAPS, you MUST dispatch every subagent with `model: "sonnet"`.
  The superpowers:subagent-driven-development skill templates show
  Agent calls without a `model` field — ADD `model: "sonnet"` to
  every Agent invocation (implementer, spec reviewer, code quality
  reviewer). None of these roles require the parent model's capability:
  implementation is mechanical coding from a plan, spec review is
  checklist verification, and code quality review is pattern matching.
  Sonnet handles all three at ~5x lower cost with no quality loss.
  This is a hard rule: zero execution subagents go out without
  `model: "sonnet"`. If `subagent_dispatch` is not in PRD_CAPS,
  execute inline.
- **`execute` not in PRD_CAPS:** Prompt user: "Execute manually, then mark
  work item done."

**Discipline injection (sub-step of EXECUTE):**
- **Resolution per `{skill, when}` group**: group `PRD_DISCIPLINES` by
  `{skill, when}`. Within each group, intersect changed-files-since-WORK with
  each entry's `include_paths` (omitted = catch-all), apply `exclude_paths`,
  first-match-wins. Different groups are independent (matching TDD on execute
  does not suppress security-audit on execute). Schema:
  `templates/project-config.md` § Cross-cutting disciplines. Setup flow:
  `setup/SKILL.md` Section L.
- Changed files for fresh items: diff `release_branch`..HEAD at cycle start;
  fall back to spec's referenced files on first cycle.
- `when: execute` → pass discipline + resolved `mode` to the execute skill.
- `when: failure` + `mode: reactive` → intercept failures (see reactive-debug
  budget below).

  **Reactive-debug budget (when `reactive_debugging.enabled: true`):**
  Capture evidence under `evidence_dir` (interpolating `{evidence_dir}`,
  `{cycle}`); hash error signature (top-3 stack frames + library name);
  fact-check external libs via `reactive_debugging.fact_check_tool` if set;
  invoke systematic-debugging and retry up to `auto_retry_attempts`. On
  exhaustion + `escalate_after` match, write a P1 finding to
  `raw/transcripts/` keyed by error-signature hash (future cycles dedup).
  `evidence_dir` MUST be in `.gitignore`. Schema:
  `templates/project-config.md` § Reactive debugging. Setup flow:
  `setup/SKILL.md` Section K.

  **Without `reactive_debugging` config (legacy):** invoke the reactive
  discipline and resume — no retry cap, no evidence, no escalation.

### 6. REVIEW — code quality gate (conditional on `prd_pipeline` + `PRD_CAPS`)

**If `review` step is NOT in the active pipeline template:** skip to step 7.

**If `review` step IS in the active pipeline template:**

- **`review` in PRD_CAPS:** Invoke the registered review skill on all
  modified/new files. Fix every issue raised before any further step.
  No bypass for `mode: mandatory` disciplines.
- **`review` not in PRD_CAPS:** Manual code review (or skip for
  vault-only work where no code was touched).

**Multi-backend execution (since v1.15.0):** Iterate over `CODE_REVIEW_BACKENDS`
(resolved at REFRESH). Spawn every backend in **parallel** via independent
`Agent()` calls with `model: "sonnet"`; each receives the same diff context.
Concatenate findings under per-backend section headers:

```
## simplify-worker findings
<simplify report>

## codex-review-worker findings
<codex report — only if codex backend enabled and not in DEP_DRIFT>
```

The controller reads both, fixes findings from each before continuing.
No auto-reconciliation — divergent findings are the value of having two
reviewers. If `CODE_REVIEW_BACKENDS` has only one entry (default behavior),
this collapses to the pre-v1.15.0 single-spawn case with no overhead.

**Evidence-contract gate (sub-step of REVIEW):** If `FACT_CHECK_CAPS`
is non-empty and `evidence_contract.require_sources_used_section` is true,
the simplify-worker checks that non-trivial SPEC/PLAN outputs include a
`## Sources Used` section. Missing section → flag as review finding,
require addition before proceeding. This applies only to outputs that
consulted external sources (web search, context7, vault queries beyond
the work item itself). The codex backend does not check this contract —
its lane is correctness/security/OOD, not provenance.

### 6a. BROWSER-VERIFY — browser verification gate (conditional on `browser_verification` config)

**Skip if** `browser_verification` is absent, `enabled: false`, or no changed
files match `browser_verification.trigger` globs.

**Skip if** `playwright-cli:browser-worker` is in `DEP_DRIFT` — apply
documented fallback (skip step entirely, or run `e2e_fallback` if configured).

**When triggered:**
1. Verify each `prerequisites` command is healthy (e.g., `curl -fsS <base_url>`).
   Not healthy → block: "Browser verification blocked — prerequisite <cmd>".
2. Spawn `playwright-cli:browser-worker` (model: sonnet) with `base_url`,
   `smoke_routes`, `reviser_workflow`. Reports pass/fail with console + a11y
   findings.
3. **Console-error gate**: any console error/warning → fail → return to EXECUTE.
   The merge-blocker is console errors, not snapshot diffs.
4. If `/playwright-cli` is too narrow, run `e2e_fallback` instead (exit 0 = pass).

**Gate:** pass → MERGE; fail → EXECUTE → SIMPLIFY → BROWSER-VERIFY.
Schema: `templates/project-config.md` § Browser verification. Setup flow:
`setup/SKILL.md` Section J.

### 6b. MERGE — post-cycle commit + push/PR (conditional on pipeline)

MERGE has two sub-steps: **commit** (always when code changed) and
**push + PR** (conditional on branch).

**Skip entirely if any of:**
- No code changes were committed this cycle (vault-only, git-only, trivial fast-path with no LOC changes)
- `prd_pipeline` is `manual` (user drives everything)

#### 6b-1: Commit (when code changed and no commit was made this cycle)

If code changes exist and no commit was made this cycle → commit them.
This applies **regardless of which branch we're on** — including the
release branch. Message format: conventional commit from work item title.

#### 6b-2: Push + PR (conditional on branch)

**On release_branch:** `git push` directly. No PR needed — changes land
directly on the default branch. Report: "Changes committed and pushed to
<release_branch>."

**On feature branch:**

1. **Push feature branch** — `git push -u origin <current-branch>`
2. **Create PR** — `gh pr create --base <release_branch> --title "<work-item-title>" --body "<summary>"`
   - If a PR already exists for this branch (open), skip creation and use the existing PR.
   - If the existing PR is merged or closed, create a new PR.
3. **CI gate decision:**
   - If `ci_configured: true` in config:
     - Spawn `ci-health-worker` agent (model: sonnet) to assess CI health
       before enabling auto-merge. The agent handles CI discovery (runtime
       vs explicit) and returns a structured health classification.
       ```
       Agent(description: "Pre-merge CI check", subagent_type: "dev-loop:ci-health-worker", model: "sonnet", prompt: "Check CI health for the repo before enabling auto-merge on a new PR. ci_discovery: <runtime|explicit>. required_checks: <list or 'discover from API'>. release_branch: <branch>. Run: (1) Discover required checks per ci_discovery mode. (2) Fetch recent workflow runs. (3) Assess health for each required check. (4) Report: healthy/degraded/broken with findings.")
       ```
     - Based on ci-health-worker's health classification:
       - `healthy` or `degraded`: Enable auto-merge with squash:
         `gh pr merge --auto --squash`. Report: "PR #N created with
         auto-merge (squash). CI health: <classification>."
       - `broken`: Do NOT enable auto-merge. Report: "PR #N created
         WITHOUT auto-merge — CI is broken on the release branch.
         Fix CI issues before merging." Surface as P2 finding.
   - If `ci_configured: false` or absent:
     - Do NOT enable auto-merge — without CI, auto-merge can bypass review.
     - Warn: "No CI checks configured — PR #N created without auto-merge. Run /setup-dev-loop and set ci_configured: true to enable CI-gated auto-merge."
     - The user must manually review and merge the PR.
4. **Error handling:**
   - If `gh` is not installed or not authenticated, report: "gh CLI not available — push branch manually and create PR via GitHub."
   - If push fails (network, permissions), report and continue — do not block the cycle on merge.

**Pipeline integration:**
- `full` pipeline: REVIEW → BROWSER-VERIFY → MERGE → SAVE
- `tdd-first` pipeline: REVIEW → BROWSER-VERIFY → MERGE
- `single-pass` pipeline: REVIEW → BROWSER-VERIFY → MERGE
- `debug-only` pipeline: MERGE after EXECUTE (skip BROWSER-VERIFY)
- `manual` pipeline: skip (user drives)

**Vault push coordination (MERGE sub-step, only when `VAULT_SYNC_PEER_AWARE`):**
Before any vault `git push` in MERGE step 6b-2:
0. **Presync gate** — same as SAVE step 7 presync gate: invoke vault-local
   wiki-presync if available. Skip push on failure.
1. Skip if `VAULT_SYNC_PEER_AWARE` is false → push directly.
2. Run `skillwiki sync --acquire-lock --timeout $VAULT_SYNC_LOCK_TIMEOUT`.
3. On success: push, release lock, reset `VAULT_SYNC_DEFERRAL_COUNT`.
4. On contention: increment deferral count, log, continue without pushing vault.
5. Same error handling as SAVE step 7 lock gate (push failure → release lock, report, continue).

BROWSER-VERIFY only runs when `browser_verification` config exists and
changed files match trigger globs. For pipelines that skip it, MERGE
follows REVIEW directly.

**MERGE does not replace PUSH.** MERGE commits code and creates a PR (or
pushes directly on the release branch). PUSH (step 10) handles publishing
(npm, tag-triggered CI). A project that only uses MERGE (no npm publish)
will skip PUSH.

### 7. SAVE — crystallize session insights + vault auto-commit (optional)

**Vault auto-commit (sub-step of SAVE, only when `query_vault` in BACKEND_CAPS):**
If `VAULT_AUTO_COMMIT` is true AND `query_vault` in BACKEND_CAPS:
1. `git -C $VAULT diff --quiet` — if clean, skip silently.
2. If dirty: `git -C $VAULT add -A && git -C $VAULT commit -m "dev-loop[${work_slug}]: auto-commit vault changes"`.
3. If commit fails (no changes after add, or git not configured), skip silently — never block the cycle on vault commit failure.
If `VAULT_AUTO_COMMIT` is false, skip.

**Vault push with advisory lock (sub-step of SAVE, only when `VAULT_SYNC_PEER_AWARE`):**
After vault auto-commit succeeds AND produced a commit (skip if auto-commit found
a clean tree), before pushing to remote:
0. **Presync gate** — if `VAULT_PRESYNC_AVAILABLE` and `VAULT_SYNC_PRESYNC_SKILL`
   is `auto-detect` or `always`: invoke `Skill("$VAULT/.claude/skills/wiki-presync/SKILL.md")`
   to run lint gate + collision dedup + `git pull --rebase`. If the skill fails
   (non-zero exit), skip the push — presync failure means the vault has issues
   that should block a push. If `VAULT_SYNC_PRESYNC_SKILL` is `always` but the
   skill file is missing: warn "presync_skill: always but wiki-presync not found
   at $VAULT/.claude/skills/wiki-presync/" and push directly.
1. Skip if `VAULT_SYNC_PEER_AWARE` is false → push directly (current behavior).
2. Run `skillwiki sync --acquire-lock --timeout $VAULT_SYNC_LOCK_TIMEOUT`.
3. On success (lock acquired):
   - `git -C $VAULT push origin main`
   - `skillwiki sync --release-lock`
   - Reset `VAULT_SYNC_DEFERRAL_COUNT = 0`.
4. On failure (lock contended or command missing):
   - Increment `VAULT_SYNC_DEFERRAL_COUNT`.
   - Log: "vault push deferred: peer holds advisory lock (attempt $COUNT of $VAULT_SYNC_RETRY_BUDGET)".
   - Continue cycle — do not block.
5. If push fails (network/permissions): release lock, report error, continue.

**If `crystallize` in BACKEND_CAPS:**
At natural breakpoints, crystallize insights not captured in spec/plan.
Skip if `vault` is empty.

**If `crystallize` not in BACKEND_CAPS:**
Write session insights to the work-item folder as `insights.md` — a
free-form markdown file with key learnings, blocked items, and
discoveries. Not as rich as a vault concept page, but ensures insights
aren't lost when no knowledge backend is available.

### 8. E2E (optional — run if `e2e_scripts` config field is non-empty)

Run each script from `e2e_scripts` in declared order. Each must exit 0
before the next starts. Counts are NOT a contract — only the exit code is.

### 9. DEPLOY (optional — run if `remote_hosts` is non-empty or `deploy_script` is set)

Deploy built artifacts to remote hosts. This step is separate from PUSH
(publishing packages) — many projects deploy without publishing to a
package registry.

Execution:
- If `deploy_script` is set in config, run it. Exit code must be 0.
- If `remote_hosts` is set but no `deploy_script`, check CLAUDE.md or
  the project's documented deployment procedure for the deploy command.
- If neither is set, skip.

**SSH/auth prerequisite:** The deploy script may require SSH
authentication to remote hosts. If the script fails with auth errors,
report the failure and do not retry — the user must resolve SSH access
outside the loop. The deploy script itself handles rollback on failure
(e.g., the zzapi-mes `update-msi1.sh` auto-rollbacks on ERR).

**Pre-deploy checks:**
- Build must pass (verified in EXECUTE)
- Tests must pass (verified by SIMPLIFY gate or E2E)
- For trivial/git-only/vault-only changes, skip DEPLOY unless the
  change affects the deployed artifact.

### 10. PUSH (optional — run if `publish_via` config field is non-empty)

**Auto-bump decision (when `RELEASE_POLICY` is non-None and `auto_bump: true`):**

Before the `publish_via` branch, decide whether this cycle should bump
and tag based on the declared `release_policy`:

1. Resolve last tag: `git describe --tags --abbrev=0 2>/dev/null`. If
   no tags exist, fall back to the repo root commit
   (`git rev-list --max-parents=0 HEAD 2>/dev/null`). If both fail
   (empty repo, no commits) → skip PUSH and log "PUSH skipped: empty
   repo or no commit history."
2. List changed files since that ref:
   `git diff --name-only <last-tag>..HEAD`. Empty diff → skip PUSH
   (nothing committed since last release).
3. Match each changed file against `RELEASE_POLICY.trigger_globs`
   (shell-style glob with `**` for recursive match, per Python `glob`
   semantics, patterns relative to repo root). If zero files match
   any pattern → skip PUSH (no shippable changes).
4. Match each changed file against `RELEASE_POLICY.skip_globs`. If
   EVERY changed file matches at least one `skip_globs` pattern → skip
   PUSH (vault-only / doc-only window). Log: "PUSH skipped: all
   changed files match skip_globs."
5. Otherwise → invoke `bump_script` (from `## Release` config) to
   update manifests and compute the next version per `channel`. Pass
   `channel` via env var `RELEASE_CHANNEL` (the script reads this if
   it supports channel-aware bumping; otherwise it stable-bumps).
6. After `bump_script` exits 0, commit manifest changes with
   `chore: bump version to <new-version>` and `git push` to
   `release_branch`. Then fall through to the `publish_via` branch
   below — its tag-push logic uses `tag_format` and
   `verify_after_push` from `RELEASE_POLICY`.

When `RELEASE_POLICY` is `None` OR `auto_bump: false`, skip this
prelude entirely and proceed directly to the `publish_via` branch
(pre-1.19.0 behavior — manual bump expected before the cycle reaches
this step).

Follow the project's documented release procedure based on
`publish_via`:

- **`ci-tag-trigger`**: bump → commit → push → tag → CI publishes.
  Verify the tag landed on the remote
  (`git ls-remote origin refs/tags/<tag>`). If missing, push it again.
  Then **verify CI** — run `gh run list --limit 1` and check the
  latest run status. If the run is `in_progress`, wait up to 120s
  (`gh run watch --exit-status`). If the run fails, inspect
  `gh run view <id> --log-failed`, fix the workflow, and re-push
  the tag. Do NOT proceed to RETRO while CI is failing.
- **`local`**: project's local release script (with caution — interactive
  auth prompts on the dev host break `/loop` idempotency).
- **`none`**: skip.

**Prefer CI-driven publishing over local `npm publish`** wherever possible.

**Order matters:** DEPLOY (step 9) runs before PUSH (step 10) because
deploying to a host and publishing a package are independent operations.
Some projects only deploy (no npm publish); some only publish (no remote
hosts); some do both.

### 11. RETRO — Tier 1 cycle journal (mandatory)

**If `save_retro` in BACKEND_CAPS (skillwiki path):**
Append a one-line retro to the project work item and the vault log
(`{vault}/log.md`):

```
## [YYYY-MM-DD] retro | loop cycle: <work-slug>
- Friction:       <what felt slow or unnecessary>
- Miss:           <what the vault query or simplify missed>
- Improve:        <what to change in this prompt or workflow>
- Generalize?:    yes | no    (does this insight apply beyond this project?)
- ClaudeMd?:      yes | no    (does this learning belong in CLAUDE.md?)
- WorkflowShift?: yes | no    (does this change the loop itself?)
```

The three flags drive the consolidation steps below. If `vault` is
empty, write the retro to the work item only.

**If `save_retro` not in BACKEND_CAPS (git-local path):**
Append the same retro format to `.claude/dev-loop-work/{work-slug}/retro.md`.
No vault log exists. If a git commit was made this cycle, include a
one-line summary of the commit in the retro.

#### Goal-context continuation hint (v1.22.0, when `goal_context` in ORCHESTRATION_CAPS)

After logging the retro, query for remaining `status: planned` work
items in the current project. When `non_interactive_goal` is present,
count only items that pass the automation readiness gate
(`automation_ready`, `human_questions_resolved`, both preflight approval
fields, and `preflight_state: ready`) as remaining executable work:

- If `query_vault` in BACKEND_CAPS: query
  `{vault}/projects/{slug}/work/` for items with `status: planned`.
- If `query_vault` not in BACKEND_CAPS: scan
  `.claude/dev-loop-work/` for items with `status: planned` in their
  YAML header.

Emit a one-line continuation hint in the transcript:
- If remaining > 0: "Goal progress: {N} automation-ready planned items remaining for
  project {slug} — /goal evaluator will trigger next cycle."
- If remaining == 0 and no readiness skips exist: "Goal progress: All planned items completed for
  project {slug} — /goal condition may be satisfied."
- If remaining == 0 but readiness skips exist: "Goal progress: No automation-ready
  planned items remain for project {slug}; {N} planned items need `/dev-loop prep`
  before autonomous execution can continue."

This hint is critical because /goal continuation decisions are primarily
made from the conversation transcript (Haiku on Claude Code, continuation.md
on Codex; Antigravity-style planners also benefit when they are not reading
the vault directly). The hint surfaces work-item status into the transcript
so the evaluator can make an informed continue/stop decision.

Skip when `goal_context` not in `ORCHESTRATION_CAPS` — the hint is
only useful under /goal and adds noise in manual cycles.

#### Auto-capture (sub-step of RETRO, only when `query_vault` in BACKEND_CAPS)

After logging the retro, auto-capture key findings from the cycle as a
raw transcript. This ensures insights aren't trapped in the one-line
retro format and become discoverable by `wiki-query` and future cycles.

Write to `{vault}/raw/transcripts/YYYY-MM-DD-loop-cycle-{work-slug}.md`:

```yaml
---
source_url:
ingested: YYYY-MM-DD
sha256:          # computed over body bytes after closing ---
---
```

Body should contain:
- **Finding summary** — what was learned, decided, or changed this cycle
- **Key references** — files touched, concepts created, decisions made
- **Unresolved items** — anything deferred, blocked, or flagged for
  future cycles

Skip auto-capture for:
- Idle/maintenance cycles (no work-slug)
- Cycles where the only change is a retro (nothing new to capture)

Do NOT modify existing raw files (N9 compliance). Always create a new
file. If a file with the same name exists, append a `-2` suffix.

#### Archive originating transcripts (sub-step of RETRO, only when `query_vault` in BACKEND_CAPS)

After auto-capture, if the cycle is flipping the work item to
`status: completed`, parse the `closes:` list from the work item's
`spec.md` frontmatter (see WORK step § `closes:` convention). For each
entry, derive the slug (basename without `.md`) and run
`skillwiki archive <slug>`. Append a one-line summary to the retro:

```
- Archived <N> originating transcripts: <slug1>, <slug2>, …
```

Skip rules:
- `closes:` absent or empty → skip silently.
- Work item is NOT completing this cycle (status stays
  `in-progress`) → skip; `closes:` persists across cycles and only
  fires once on completion.
- A listed path does not exist in `raw/transcripts/` → log a warning
  in the retro but do not block the cycle. The transcript may already
  be archived from a prior cycle.
- `skillwiki archive` errors (vault lock, missing CLI) → log the error
  in the retro and continue. Archive is hygiene, not a release gate.

Idle cycles and non-completing cycles never archive — `closes:` is a
completion-trigger, not a per-cycle action.

### 12. DISTILL — concept promotion / ADRs (conditional — mixed cadence; see sub-sections)

**If `distill` in BACKEND_CAPS (skillwiki path):**

DISTILL (concept pages) — run if either:
- Three cycles have completed since the last DISTILL run, OR
- A retro this cycle flagged `Generalize?: yes`.

DISTILL pulls compound retro entries from the project wiki, identifies
recurring patterns (≥2 occurrences across cycles), and writes a vault
concept page at `concepts/dev-loop-<slug>.md` with provenance pointing
back to the source retros.

ADR (workflow decisions) — run `skillwiki:proj-decide` **in the same
cycle that flagged it** if the retro set `WorkflowShift?: yes`. ADR
write does NOT wait for the 3-cycle DISTILL cadence — capture while
the context is fresh. Writes an ADR under
`projects/{slug}/architecture/decisions/`. ADRs that generalize also
get a corresponding concept page in the global wiki.

**If `distill` not in BACKEND_CAPS (git-local path):**
Grep local retro files in `.claude/dev-loop-work/` for recurring
patterns (same ≥2 occurrence threshold). Append findings to
`.claude/dev-loop-work/compound.md` — a persistent file that
accumulates cross-cycle patterns. Not as rich as a vault concept page,
but preserves the distillation intent.
If a retro flagged `WorkflowShift?: yes`, note it in `compound.md`
**in the same cycle** for future reference when a vault becomes
available — do not defer to a later DISTILL run.

### 13. AUDIT — `claude-md-management:claude-md-improver` + auto-memory note (conditional — every 3 cycles OR on `ClaudeMd?: yes`)

Run ONLY if any of:
- Three cycles have completed since the last AUDIT run.
- A retro this cycle had `ClaudeMd?: yes`.

Skip otherwise. Running every cycle creates churn-y diffs and noise.
The 3-cycle cadence aligns with DISTILL so consolidation happens in one
phase.

**Two complementary hygiene systems are now active per cycle:**

1. **`claude-md-management:claude-md-improver`** — audits the project's
   `CLAUDE.md` file. dev-loop invokes this skill at the cadence above.

2. **Claude Code built-in Auto-Memory** — the harness maintains
   `~/.claude/projects/<slug>/memory/MEMORY.md` per the user's CLAUDE.md
   auto-memory instructions (user/feedback/project/reference entries).
   The dev-loop controller does NOT invoke this — it's harness-managed
   based on the user's auto-memory directives. dev-loop's role is to
   *surface* the fact at AUDIT time: remind the user that a second
   memory layer exists and may benefit from session-end review,
   especially if recent cycles introduced new preferences or constraints.

If `DEP_DRIFT` includes `claude-md-management:claude-md-improver`, skip
its invocation and apply the documented fallback (skip AUDIT step;
CLAUDE.md updates remain manual). The auto-memory surfacing still happens.

**Vault dirty-tree check (sub-step of AUDIT, only when `query_vault` in BACKEND_CAPS):**
After claude-md-improver and auto-memory surfacing:
- `git -C $VAULT diff --quiet` — if dirty, emit warning:
  "Vault working tree is dirty after cycle. Run `git -C $VAULT add -A && git -C $VAULT commit` or enable `vault_auto_commit: true` in dev-loop config."
- This is a warning, not a cycle blocker — the cycle proceeds regardless.

**Vault sync contention check (sub-step of AUDIT, only when `VAULT_SYNC_PEER_AWARE`):**
After the dirty-tree check:
- If `VAULT_SYNC_DEFERRAL_COUNT == 0` → silent.
- If `1 <= VAULT_SYNC_DEFERRAL_COUNT < VAULT_SYNC_RETRY_BUDGET` → note:
  "vault push deferred $COUNT time(s) this cycle — peer held advisory lock."
- If `VAULT_SYNC_DEFERRAL_COUNT >= VAULT_SYNC_RETRY_BUDGET` → surface as P2 finding:
  "vault push retry budget exhausted ($COUNT deferrals). Peer sessions may be
  holding the advisory lock persistently, or the lockfile may be stale.
  Investigate with `skillwiki sync peers`."
  (Counter resets to 0 at next REFRESH — per-cycle scope.)

### 14. VERIFY — provenance integrity (conditional, every 3 cycles)

**If `audit_vault` in BACKEND_CAPS (skillwiki path):**
Run after DISTILL/AUDIT to verify per-page that every `^[raw/...]`
reference resolves and source frontmatter matches the body. Catches
broken provenance from rotated raw files or moved concept pages. Quick
read-only check — should report zero issues in healthy cycles.

**If `audit_vault` not in BACKEND_CAPS (git-local path):**
Verify work-item directory structure completeness: each work item has
spec.md, plan.md (or inline-justified skip), and retro.md. Flag
incomplete work items. Quick structural check — no provenance to verify
without a vault.

## Idle Discovery (when CORE finds no claimable work)

When QUERY returns no claimable work and nothing is in progress, the
cycle doesn't end empty. Skip CORE steps 2–9 and run maintenance
instead:

1. Run RETRO (step 11) as a maintenance retro — no work-slug, just
   note that this was an idle cycle.
2. Run consolidation steps 12–14 regardless of their normal 3-cycle
   cadence (idle time is free — use it).
3. Run maintenance based on BACKEND_CAPS:

   **If `lint_vault` in BACKEND_CAPS (skillwiki maintenance):**

   Vault maintenance skills are dispatched as **Agent spawns with `model: "sonnet"`** — these are mechanical tasks (search, validate, write) that sonnet handles at ~5x lower cost than inheriting the parent model. Each agent gets a self-contained prompt with vault path and project context.

   ```
   Agent(description: "Vault lint", subagent_type: "skillwiki:wiki-lint", model: "sonnet",
     prompt: "Run vault lint on the skillwiki vault. Fix any auto-fixable issues. Report findings summary.")
   ```

   ```
   Agent(description: "Vault audit", subagent_type: "skillwiki:wiki-audit", model: "sonnet",
     prompt: "Run vault audit on the skillwiki vault. Verify provenance integrity. Report findings.")
   ```

   ```
   Agent(description: "Vault crystallize", subagent_type: "skillwiki:wiki-crystallize", model: "sonnet",
     prompt: "Crystallize session insights into the skillwiki vault. Report any pages created.")
   ```

   ```
   Agent(description: "Project distill", subagent_type: "skillwiki:proj-distill", model: "sonnet",
     prompt: "Distill compound entries for project {slug} in the skillwiki vault. Promote recurring patterns to concept pages. Report any pages created.")
   ```

   ```
   Agent(description: "Project decide", subagent_type: "skillwiki:proj-decide", model: "sonnet",
     prompt: "Record any pending ADRs for project {slug} in the skillwiki vault. Report any decisions recorded.")
   ```

   **Fallback:** If Agent spawn fails (subagent_type unavailable), fall back to inline `Skill("skillwiki:<skill>")` invocation for backwards compatibility.

   Additional maintenance tasks (run inline — low token volume):
   - **Drift check** — run `skillwiki drift` to detect changed upstream
     sources. Handle per N9 Reingest Protocol (metadata-only vs content
     drift).
   - **Drift metadata cleanup** — `skillwiki drift` reports
     `fetch_failed` entries for raw sources with non-HTTP source_urls
     (null, file://, local:). These can never be drift-checked. In
     idle time, either fix the source_url to a valid HTTP URL (if
     known), or add a `refreshable: false` annotation to document
     them as intentionally non-refreshable.
   - **Unretro'd commits check** — compare recent git commits against
     vault log entries. If ≥3 commits lack corresponding retros,
     batch-write a summary retro covering the gap.

   **If `lint_vault` not in BACKEND_CAPS (git-local maintenance):**
   - Run `git gc --auto` if the repo is large
   - Prune stale local branches: `git branch --merged | grep -v main`
   - Run project lint/format if available (e.g., `npm run lint`)
   - Check for outdated dependencies if lockfile exists
   - Check for unpushed commits: `git log origin/$RELEASE_BRANCH..HEAD --oneline`
   - Verify work-item directories are complete (spec + retro present)
   - **Unretro'd commits check** — compare recent git commits against
     vault log / local retro files. If ≥3 commits lack corresponding
     retros, batch-write a summary retro covering the gap. This prevents
     retro gaps from accumulating silently during intensive sprints.

3b. **CI health check** (only if `ci_configured: true`). Spawn
   `ci-health-worker` agent (model: sonnet) to inspect GitHub Actions
   health — this is mechanical API querying and status interpretation;
   Sonnet handles it at lower cost.

   ```
   Agent(description: "CI health check", subagent_type: "dev-loop:ci-health-worker", model: "sonnet", prompt: "Check CI health for the repo. ci_discovery: <runtime|explicit>. required_checks: <list or 'discover from API'>. release_branch: <branch>. Run: (1) Discover required checks per ci_discovery mode. (2) Fetch recent workflow runs. (3) Assess health for each required check. (4) Report: healthy/degraded/broken with findings.")
   ```

   If the agent reports **broken** (required checks failing on the
   release branch), surface as a P2 finding for the next cycle.
   If **degraded** (optional checks failing, or stale workflows), note
   in the idle retro but don't escalate.

   Skip if `ci_configured: false` — no CI to monitor.

4. Invoke research agent with `model: "sonnet"` — see `research/SKILL.md` in
   this skill directory. Code and vault health scanning is mechanical
   analysis; Sonnet handles it at lower cost without quality loss.
   ```
   Agent(description: "Dev-loop research", subagent_type: "dev-loop:research-worker", model: "sonnet", prompt: "Run research cycle with intensity: <normal|high>. BACKEND_CAPS: <caps>. VAULT_TYPES: <types>. CRITICAL_PATHS: <paths>. Scan code health and vault health per research/SKILL.md.")
   ```
   Pass intensity through (`normal` or `high`). Also pass
   `BACKEND_CAPS`, `VAULT_TYPES`, and `CRITICAL_PATHS` (derived from
   config at REFRESH) so the research agent can apply critical-path
   ranking bias (Track A0) and skip Track B when `query_vault` not in
   BACKEND_CAPS.
   If it returns ranked recommendations, the next dev-loop cycle picks
   up the top item via the WORK step.

4.5. **IDLE DEEP-RESEARCH** (conditional on `idle_deep_research.enabled` AND
     research step 4 returned no P2+ findings AND cooldown allows):
   - Gate on `query_vault` in BACKEND_CAPS — skip if no vault.
   - **Gate on `deep-research:deep-research` not in `DEP_DRIFT`** — skip
     entirely if drifted (no fallback available for deep research).
   - Pick next topic from `topic_seeds` (round-robin), biased toward
     `CRITICAL_PATHS.*.code` matches.
   - Skip if a vault query page for the topic was created within
     `skip_if_recent_query_page_exists` days, or if `max_per_day` is hit.
   - Invoke `/deep-research <topic>` honoring `budget.*` caps.
   - Extract 1–3 actionable ideas → route through the schema-compatible
     vault queue. Use raw transcript captures when the active schema lacks a
     non-executing work-item status. Default P-score: P3.
   - Mark cooldown timestamp; log: "Idle deep-research: <topic>, <N> ideas."

   With `knowledge_layer: none`, the vault capture path is unavailable —
   outputs go to `.claude/dev-loop-work/` instead.
   Schema: `templates/project-config.md` § Idle deep-research. Setup flow:
   `setup/SKILL.md` Section I.

5. **Pick up P3 work if no P2+ items exist** (normal mode). After
   research completes, if the backlog contains only P3 items, pick the
   top P3 item and execute it using the trivial cycle fast-path. In
   **high** mode, skip the priority guard entirely and pick up the
   top-ranked item regardless of P-score.
6. Exit with a one-line summary: `"Idle cycle — ran [skills executed],
   research: [findings summary]."` or `"P3 pickup — [work-slug]:
   [result]."`.
7. **Auto-cancel after consecutive idle cycles.** If 3+ consecutive
   cycles produce no claimable work (idle with no P3 pickup), emit a
   recommendation: "3+ consecutive idle cycles — consider cancelling
   the loop. Re-enable when new work arrives or new raw sources are
   ingested." This does NOT auto-cancel — the user decides — but
   surfacing the signal prevents wasting context budget on stable
   projects.

## Trivial Cycle Fast-Path

When the work item is scoped to a small, well-defined change, collapse
the pipeline:

**Qualifying criteria (any one suffices):**
- Single subcommand, config tweak, or small bug fix under ~50 LOC in
  normal mode (~80 LOC in high mode)
- **Git-only operation** (push unpushed commit, merge branch, tag
  release) — 0 LOC changes
- **Vault-only work** (page edits, frontmatter fixes) — no code touched

**Collapsed pipeline:**

1. **QUERY** — normal.
2. **WORK** — `proj-work` as usual, but note `kind: trivial` in the
   work item.
3. **SPEC** — inline spec in the work-item folder (skip brainstorming).
4. **PLAN** — skip (spec is the plan for trivial changes).
5. **EXECUTE** — inline (no subagent dispatch).
6. **SIMPLIFY** — mandatory for code changes; **skip for git-only or
   vault-only work** (nothing to review).
6b. **MERGE** — skip for vault-only work. For code changes:
   commit always, then push directly on release_branch or create PR
   on a feature branch.
7. **E2E / PUSH** — if applicable.

Retro and consolidation steps are unchanged. The fast-path is a
*recommendation*, not a requirement — if scope creep makes a trivial
item non-trivial, escalate to the full pipeline.

### Vault-Only Fast-Path (requires `query_vault` in BACKEND_CAPS)

When the work item is **purely vault edits** (no code touched, no git
push needed), further collapse the trivial pipeline:

1. **QUERY** — normal.
2. **WORK** — skip (no code spec/plan needed for vault-only edits).
3. **SPEC** — skip.
4. **PLAN** — skip.
5. **EXECUTE** — inline vault edits (page creation, frontmatter fixes,
   citation normalization).
6. **VALIDATE** — if `audit_vault` in BACKEND_CAPS: `skillwiki validate`
   on each modified page (required before touching `index.md` or
   `log.md`). If `audit_vault` not in BACKEND_CAPS: verify work-item
   directory structure (each work item has spec.md + retro.md).
7. **SIMPLIFY** — skip (no code to review).
8. **E2E / PUSH** — skip by default. Push vault changes only if the
   vault has accumulated significant edits (git commit + push).

This shorter path avoids creating work-item directories for routine
vault maintenance (typing a query page, fixing citations, enriching a
thin page). The standard trivial path remains available for vault work
that benefits from work-item tracking (e.g., a multi-page enrichment
campaign). Vault-only fast-path is only available when `query_vault` in
BACKEND_CAPS — without a vault, there are no vault-only edits.

## Bootstrap Cycle (setup-only work)

When the work item is a setup or bootstrap operation (proj-init, vault
repair, dependency bump, config scaffolding), the full pipeline is
overkill. Collapse to:

1. **QUERY** — normal context check.
2. **EXECUTE** — inline (no spec/plan — the action is self-defining).
3. **RETRO** — normal retro format.

Skip SPEC, PLAN, SIMPLIFY, E2E, PUSH. Setup operations don't produce
reviewable code — they create scaffolding that future full cycles build
on. If the setup involves a code change (e.g., adding a script), use
the trivial cycle fast-path instead.

Typical bootstrap items: `proj-init`, config file creation, vault
directory repair, `npm install` after dependency addition, git branch
setup.

## Pre-Push Gate (when PUSH applies)

| Gate | Condition | Pass | Fail |
|------|-----------|------|------|
| SIMPLIFY | simplify-worker review (sonnet) | MERGE (if code changed) | Fix issues, re-run |
| MERGE | On release_branch | `git push` directly | — |
| MERGE | On feature branch | Push + create PR | — |
| MERGE (CI) | `ci_configured: true` | Spawn ci-health-worker (sonnet) → healthy/degraded: auto-merge (squash), broken: skip auto-merge | — |
| MERGE (no CI) | `ci_configured: false` | Warn, no auto-merge | — |
| E2E | `e2e_scripts` non-empty | DEPLOY (if applicable) | Fix, re-run from SIMPLIFY |
| DEPLOY | `remote_hosts` / `deploy_script` set | PUSH | Report failure, do not retry auth |
| PUSH | `publish_via` set | Bump → commit → push → tag (CI publishes) | — |
| PUSH (verify) | CI after tag push | Green → RETRO | Red → fix workflow, re-push tag |

A push that bypasses review is a broken release. Treat E2E and DEPLOY
with the same discipline if the project has them.

## N9 Reingest Protocol

**If `drift_check` in BACKEND_CAPS (skillwiki path):**
When `skillwiki drift` reports drifted sources, handle according to drift
severity:

### Metadata-only drift (sha256 changed, content substantively same)

Common with GitHub repo URLs which return non-deterministic HTML on each
fetch. The content hasn't meaningfully changed — only the rendering differs.

**Action:** run `skillwiki drift --apply` to update the stored sha256 in
the raw file's frontmatter. This is a metadata correction, not a content
change. No new raw file or concept page update needed.

### Content drift (source actually changed)

The upstream source has substantively changed since ingestion.

1. **Archive the old raw file** — `skillwiki archive <slug>` moves it to
   `_archive/raw/...` preserving the original as provenance history.
2. **Ingest the new content** — use `wiki-ingest` to create a new raw
   file with updated content and sha256.
3. **Update concept pages** that cite the old raw path to point to the
   new one if the content change is significant. For minor formatting
   drift, leave citations unchanged and add a note.
4. **Do NOT modify the old raw file** (it's now in `_archive/`).

**If `drift_check` not in BACKEND_CAPS (git-local path):**
No upstream source drift is possible without a vault. Instead, check for
stale local state:

1. **Unpushed commits** — `git log origin/$RELEASE_BRANCH..HEAD --oneline`.
   If ≥5, flag as P2 risk (batch push recommended).
2. **Stale local branches** — `git branch --merged | grep -v $RELEASE_BRANCH`.
   Prune branches that have been merged upstream.
3. **Uncommitted changes** — `git status --short`. Flag if work-in-progress
   has been sitting uncommitted for multiple cycles.

## Hard Rules

1. **Always REFRESH first.** Reload plugins, load project config, read
   CLAUDE.md and MEMORY.md fresh every cycle.
2. **Always start work with proj-work.** Redirect paths come from
   there, not from the PRD skill.
3. **PRD skill is pluggable via `prd_layer` config.** Steps 3–6 branch on
   `PRD_CAPS` and `prd_pipeline`, not hardcoded skill names. superpowers
   is the default backend, not required.
4. **Never push without review.** Hard gate for code changes;
   git-only and vault-only work skip simplify-worker (nothing to review). E2E
   joins the gate when the project has it.
5. **Validate before index.** When `audit_vault` in BACKEND_CAPS:
   `skillwiki validate` must pass before touching `index.md` or
   `log.md`. Otherwise: verify work-item directory completeness.
6. **Raw is immutable.** Never modify files in `raw/` after ingestion.
7. **Trust the vault for history** when `query_vault` in BACKEND_CAPS.
   Query the wiki, not git history, for past decisions. When
   `query_vault` not in BACKEND_CAPS: trust git history and local
   work-item files instead.
8. **Provenance stays project** when `save_retro` in BACKEND_CAPS.
   Pages: `provenance: project`,
   `provenance_projects: ["[[<project-slug>]]"]`. When `save_retro`
   not in BACKEND_CAPS: retros use local `retro.md` format (no
   wikilink provenance).
9. **Fallback to wiki-ingest** when `query_vault` in BACKEND_CAPS. If
   proj-work redirect fails, use `wiki-ingest` manually. When
   `query_vault` not in BACKEND_CAPS: create the file locally in the
   work-item directory instead.
10. **Consolidation is every 3 cycles, not per-cycle.** DISTILL, AUDIT,
    VERIFY share the 3-cycle cadence and run as a single phase.
11. **Tier 1 is project, Tier 2 is global.** Project retros stay in
    `projects/{slug}/`. Generalized patterns lift to `concepts/` only
    via DISTILL.
12. **Publishing follows config.** `publish_via: ci-tag-trigger` is the
    safe default. Local `npm publish` prompts for auth and breaks
    `/loop` idempotency.
13. **Idle cycles run maintenance.** When CORE finds no claimable work,
    run consolidation and maintenance instead of exiting idle. Never
    waste a cycle. When `lint_vault` in BACKEND_CAPS: run skillwiki
    maintenance skills. Otherwise: run git-based housekeeping.
14. **Counts are not a contract.** E2E success is `exit 0`, not a magic
    number of assertions. Discover counts at cycle start; never
    hardcode them in this skill.
15. **Fix friction in-cycle.** When a retro identifies a code-fixable
    friction (e.g., lint --fix creating duplicates, missing schema),
    implement the fix in the same cycle rather than filing it as
    backlog. Backlog is for deferred decisions, not for known code
    fixes. Filing a known fix as backlog and re-discovering it in
    future cycles is waste.
16. **Verify CI after push.** After PUSH (step 10), check CI status
    with `gh run list --limit 1` and `gh run watch` if in-progress.
    Do NOT proceed to RETRO while CI is failing. If CI fails, inspect
    `gh run view <id> --log-failed`, fix the workflow, and re-push
    the tag.
17. **Use local CLI, not global** when `lint_vault` in BACKEND_CAPS.
    When the project has a local build of skillwiki (or a
    `cli_entry_override` in config), prefer it over the globally
    installed `skillwiki` binary. A stale global version produces false
    lint warnings and missing schema detections. Use `npx skillwiki` or
    the config override, not `skillwiki` directly. When `lint_vault`
    not in BACKEND_CAPS: not applicable (no skillwiki binary needed).
18. **Respect `BACKEND_CAPS`.** Each step checks capability membership
    before invoking backend-specific operations. When a capability is
    absent, use the documented git-based alternative or document why
    the step is intentionally skipped. Never silently fail — the user
    must see which steps were skipped and why. When new backends are
    added, they declare capabilities in the config; steps pick them
    up automatically.
19. **Block on skill-source drift.** If REFRESH detects that the cached
    SKILL.md differs from the source but the user hasn't reloaded
    plugins, block the cycle. Running stale skill logic silently is
    worse than stopping and asking the user to `/reload-plugins`.
20. **Execution subagents always run on sonnet.** When `subagent_dispatch`
    in PRD_CAPS, every subagent spawned during EXECUTE (implementer,
    spec reviewer, code quality reviewer) must include
    `model: "sonnet"`. The superpowers:subagent-driven-development
    templates omit `model` — the controller MUST add it. None of these
    roles benefit from the parent model. If `CLAUDE_CODE_SUBAGENT_MODEL`
    is set to a non-empty value, it globally overrides per-agent model
    parameters — it must remain empty (`""`) for this rule to work.
21. **MERGE commits code, then creates PRs or pushes directly.** The
    MERGE step always commits code changes (regardless of branch), then
    either creates a PR (feature branch) or pushes directly (release
    branch). It never force-pushes or directly merges a feature branch
    into the release branch. This preserves branch protection, CI gates,
    and review workflows.
22. **`release_policy` is opt-in.** Projects without the `release_policy`
    block see no behavior change (pre-1.19.0 manual-bump flow preserved).
    When the block is present with `auto_bump: true`, PUSH gates on
    file-glob matches before invoking `bump_script` — the script handles
    version computation, dev-loop handles the policy. When all changed
    files match `skip_globs`, PUSH is skipped entirely so vault-only or
    doc-only cycles don't generate noise releases.

## Wrapper Agents for Skill-as-Subagent Adapters

When a third-party skill needs **subagent isolation** (clean context, model
pinning, no parent context pollution) but its owning plugin doesn't ship a
registered agent, create a thin wrapper in `skills/dev-loop/agents/<name>.md`.
The wrapper is registered as an agent (auto-discovered from the `agents/`
directory) while its body delegates to the foreign skill via inline `Skill()`
invocation.

**Reference exemplar:** `agents/research.md` (name: `research-worker`,
model: sonnet) wraps `research/SKILL.md` so IDLE step 4 can dispatch the
scan as a subagent — keeping the parent session context clean while pinning
the work to sonnet.

**When to create a wrapper:**
- The skill is expensive in tokens and should run isolated from parent context.
- The skill is mechanical (search/probe/summarize) and benefits from sonnet pinning.
- The owning plugin hasn't shipped (or won't ship) an agent registration.

**Wrapper template** (~30 lines):

```markdown
---
name: <adapter-name>-worker
description: Wrapper that delegates to <foreign-skill> with subagent isolation. Typical triggers include ...
model: sonnet
tools: [Read, Bash, Grep, Glob, Write, Edit]
---

# <adapter-name>-worker

Invoke `Skill("<foreign-skill>")` with the caller's prompt as argument.
Report the skill's output verbatim. Apply caller-specified guards (read-only mode,
budget caps) before invoking.
```

After creation, reference the wrapper in `dependencies.yaml` (kind: agent,
`self: true`) and in any SKILL.md call sites via `subagent_type: "dev-loop:<adapter-name>-worker"`.

Cost: one ~30-line file per adapter. Benefit: full subagent isolation
without waiting on upstream cooperation.

## Obsidian Integration (requires `query_vault` in BACKEND_CAPS)

When `skillwiki init` creates a vault, it writes:

- `.obsidian/app.json` — `attachmentFolderPath`, `newFileLocation`,
  `newFileFolderPath` for consistent file placement
- `.obsidian/templates.json` — points to `_Templates/` folder
- `_Templates/tpl-ad-hoc-capture.md` — minimal capture template with
  `created: {{date:YYYY-MM-DD}}T{{time:HH:mm}}` (Obsidian auto-fills)
  and `ingested:` (empty — agent fills when processing the transcript)

The ad-hoc capture flow works in both directions:
1. **From Obsidian** — user creates a note in `raw/transcripts/` using the
   template, or drops any `.md` file there. Dev-loop discovers it on the
   next REFRESH step 6.
2. **From Claude** — `/wiki-add-task <text>` creates a dedicated capture
   file at `raw/transcripts/YYYY-MM-DD-{type}-{slug}.md` with ad-hoc
   capture frontmatter (`kind`, `project`, `ingested`). Each capture gets
   its own file — never appended to an existing daily log.

When `query_vault` not in BACKEND_CAPS, Obsidian integration is
unavailable — no vault exists for captures to land in. Ad-hoc captures
from Claude go to `.claude/dev-loop-work/captures.md` instead.

## Vault-Local Skill Discovery (requires `query_vault` in BACKEND_CAPS)

dev-loop supports a vault-local skill pattern: skills placed at
`$VAULT/.claude/skills/<name>/SKILL.md` that are discovered at runtime
rather than declared in `dependencies.yaml`. This is for vault-specific
tooling that doesn't belong in the main plugin distribution.

**`wiki-presync` contract:** Before each vault push (SAVE step 7, MERGE
step 6b-2), dev-loop checks `$VAULT/.claude/skills/wiki-presync/SKILL.md`.
If present and `vault_sync.presync_skill` is `auto-detect` or `always`,
the skill is invoked as a pre-push hook. The skill should run lint gate,
collision dedup, and `git pull --rebase`. If it exits non-zero, the push
is skipped — presync failure means the vault has issues that should
block a push.

Vaults that don't ship the skill see no change in behavior. The probe
is a single `[ -f ]` check at cycle start — zero runtime cost when absent.

## Bootstrap Mode

If the user explicitly asks to bootstrap a new project (or REFRESH
fallback 3 fires), use the **two-step bootstrap**:

### Interview-first bootstrap (preferred)

If `setup_interview` ∈ BACKEND_CAPS (the `interview` section is declared in
config — which it won't be yet on a fresh project, so dev-loop auto-detects
that `setup-dev-loop` is a bundled skill and offers it), invoke
`Skill("setup-dev-loop")`. The setup skill walks the user through PRD layer,
knowledge layer, release config, and delegates the domain glossary to
`grill-with-docs` if installed. It writes `./.claude/dev-loop.config.md` and
runs `proj-init` if a vault is available.

### Step A: Create config file (fallback)

If `setup_interview` ∉ BACKEND_CAPS (no interview section, or user declines
the interactive setup), fall back to auto-detect:

Copy `templates/project-config.md` into `./.claude/dev-loop.config.md`,
filling in:

1. `slug` — project identifier
2. `vault` — wiki path (or empty)
3. `knowledge_layer` — `skillwiki` if vault exists and skillwiki is
   installed; `none` otherwise. Derive BACKEND_CAPS from this.
4. `release_branch` — e.g., `main`, `dev`
5. Code layout fields (auto-detect candidates from repo structure)
6. E2E scripts (auto-detect from `scripts/`)
7. Release config (`publish_via`, `bump_script`, `manifests_count`)
8. Optional `notes` for project-specific gotchas

### Step B: Initialize vault workspace (only if `query_vault` in BACKEND_CAPS)

Run `skillwiki:proj-init` with the project slug to create
`{vault}/projects/{slug}/` with README and folder structure
(`requirements/`, `architecture/`, `work/`, `compound/`).

Skip Step B when `query_vault` not in BACKEND_CAPS — no vault to initialize.

**Both steps are required** for full vault integration. After bootstrap,
re-run REFRESH to load the new config.

## /goal Integration (v1.22.0)

dev-loop is single-pass by design — it processes one work item per
invocation and exits. This makes it naturally compatible with `/goal`
on any platform (Claude Code v2.1.139+, Codex v0.128.0+, Antigravity 2.0).

### How It Works

`/goal` is the outer loop; dev-loop is the inner engine. The platform's
/goal evaluator checks if the overall objective is met. Each turn,
dev-loop picks up the next work item, drives it through the pipeline,
and exits. If work remains, the evaluator triggers another turn →
another dev-loop cycle.

```
/goal evaluator loop (platform-provided)
  └─ turn N: invoke dev-loop
       └─ REFRESH → QUERY → WORK → SPEC → PLAN → EXECUTE → REVIEW → MERGE → RETRO
  └─ evaluator check: all planned items completed? NO → turn N+1
  └─ turn N+1: invoke dev-loop (picks next item)
       └─ REFRESH → QUERY → WORK → ... → RETRO
  └─ evaluator check: YES → goal clears
```

### Recommended Pipeline: grill-me → dev-loop prep → /goal → dev-loop

**Phase 1: CLARIFY** (human-attended, ~5-10 min)
1. `/grill-me` — adaptive interview to sharpen requirements
2. Write requirements to vault work items (`status: planned`)

**Phase 2: PREFLIGHT** (human-attended, batch approval)
3. `/dev-loop prep` — inventory active work, captures, and hygiene findings;
   batch all questions with recommended defaults; approve the items safe for
   unattended execution.
4. Verify approved items carry readiness gates:
   `automation_ready: true`, `human_questions_resolved: true`,
   `spec_preflight_approved: true`, `plan_preflight_approved: true`,
   and `preflight_state: ready`.

**Phase 3: CONFIGURE** (human-attended, ~2 min)
5. Verify dev-loop config (`.claude/dev-loop.config.md`).
6. Set goal condition:
   `/goal "All status:planned items for project <slug> completed,
   all tests pass, vault clean"`

**Phase 4: EXECUTE** (autonomous, hours-long)
7. /goal evaluator triggers turn → dev-loop REFRESH detects goal
   context (`ORCHESTRATION_CAPS`) → picks next automation-ready planned
   item → drives full pipeline → RETRO logs remaining ready items and
   readiness skips → evaluator re-checks → repeats until all ready items
   complete or unprepared items require another attended prep pass.

**Key rule:** Interactive work (grill-me, AskUserQuestion, `/dev-loop prep`)
happens BEFORE `/goal`. Autonomous work (dev-loop pipeline) happens INSIDE
`/goal`. AskUserQuestion is counterproductive under /goal evaluators — the
default assumption is unattended execution. `/dev-loop prep` may suggest a
goal command, but it must not start or manage `/goal`.

### Platform Behavior

| Platform | Evaluator | dev-loop Interaction |
|----------|-----------|---------------------|
| **Claude Code** | Haiku checks transcript each turn | RETRO continuation hint (§11) surfaces remaining items for Haiku to read |
| **Codex** | continuation.md prompts same model | RETRO hint provides structured progress for the continuation decision |
| **Antigravity** | Subagent planner decomposes tasks | Best-effort SKILL.md compatibility; if invoked as a nested worker, keep dev-loop single-pass and avoid adding platform-specific branching |

### What dev-loop Does NOT Do

- **Does not branch on platform.** No `if claude_code` or `if codex` logic —
  capability-based only (existing pattern). For Codex tool-name mapping
  (`Agent` → `spawn_agent`/`wait_agent`), the `multi_agent` config gate, and the
  Codex App sandbox-finishing contract, see `references/codex-tools.md` — a
  reference the agent consults, not branching in the loop logic.
- **Does not manage the /goal lifecycle.** Setting, clearing, pausing /goal
  is the user's responsibility.
- **Does not replace /goal.** dev-loop + /loop cron is the legacy pattern;
  dev-loop + /goal is the recommended pattern for new work.

## Codex Platform Adaptation

dev-loop targets Claude Code first but runs under OpenAI Codex CLI / Codex App
without platform branching. Two concerns sit outside the capability-based loop
logic and are documented in `references/codex-tools.md`:

1. **Subagent dispatch.** The worker spawns (doctor-, research-, simplify-,
   codex-review-, ci-health-worker; browser-worker) use the Claude `Agent` tool.
   On Codex, map these to `spawn_agent` / `wait_agent` / `close_agent` and set
   `[features] multi_agent = true` in `~/.codex/config.toml`. Without multi-agent,
   each worker degrades to inline `Skill(...)` execution — the same path
   `DEP_DRIFT` already uses.
2. **Codex App sandbox finishing.** The App executes in an externally-managed
   worktree (often detached HEAD) where push/branch/PR is blocked. Before the
   git-mutating steps (MERGE 6b, PUSH 10, SAVE 7 / MERGE 6b-2 vault push),
   detect the environment (`GIT_DIR`/`GIT_COMMON`/`BRANCH` + submodule guard).
   On detached HEAD, commit in place and hand off via the App's "Create branch"
   / "Hand off to local" controls instead of pushing. Surface the deferral in
   RETRO, not as a cycle failure.

Discovery on Codex is via `~/.agents/skills/`; the `.codex-plugin/plugin.json`
manifest declares the plugin for Codex tooling.

## Research Agent

The companion research agent prompt lives in `research/SKILL.md` adjacent to
this `SKILL.md`. It is invoked from IDLE DISCOVERY step 4. The research
agent shares the same project config; do not duplicate config fields.

## Investigate Companion

The companion investigate prompt lives in `investigate/SKILL.md` adjacent to
this `SKILL.md`. It is invoked when MODE resolves to `investigate` after
REFRESH, and reuses the same session state (`BACKEND_CAPS`, `VAULT_TYPES`,
`DEP_DRIFT`, `CRITICAL_PATHS`, `INVESTIGATE_MAX_ITEMS`,
`INVESTIGATE_TOPIC_SEEDS`). It queues schema-valid findings and does not
execute code. Proposed work items are allowed only when `skillwiki validate`
accepts that non-executing status; otherwise findings are queued as
`raw/transcripts/` ad-hoc captures.
