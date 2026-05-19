---
name: dev-loop
version: "1.7.1"
description: 'Use this skill when the user says "run a dev cycle", "implement a feature", "make a code change", "start a loop", or wants to work on a task with automated planning, execution, code review, and knowledge capture. Pass `high` for aggressive mode.'
argument-hint: "[high]"
---

# Dev Loop — PRD + Skillwiki (Generic Engine)

A single-pass dev cycle. When invoked, runs ONE cycle: refresh context,
load project config, pick up the next claimable work item, drive it
through the loop, exit. The PRD skill drives the work; skillwiki
captures the knowledge in two tiers — project journal and global
playbook.

This skill is **project-agnostic**. All project specifics come from a
config file in the active repo. If no config exists, the skill
autodiscovers conventions or asks the user to bootstrap one.

## Single-Pass Semantics

- **One cycle per invocation.** Do not iterate internally.
- **Idempotent.** If no claimable work exists and nothing is in progress,
  exit with a one-line status — do not invent work.
- **Resumable.** If a previous cycle left a work item mid-step, resume
  at the next unfinished step rather than restarting.
- **Never `/clear` during a loop session.** It destroys cumulative
  learning, retro state, and resume hints. `/clear` is a session-end
  action only.
- **`/compact` is allowed only at the COMPACT step** per the documented
  thresholds.

## Intensity Level

Parse arguments for the keyword `high` (case-insensitive). If present,
set **intensity = high**; otherwise **intensity = normal**.

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
| IDLE: research | Research agent | `sonnet` | Code health scanning, vault coverage analysis — mechanical analysis |
| IDLE: maintenance | skillwiki skills (lint, audit, etc.) | inline (Skill tool) | Low token volume; future: agent spawns via skillwiki project task |

**Steps that stay inline (not agent-eligible):** WORK, SAVE, DISTILL, AUDIT, VERIFY, RETRO, E2E, DEPLOY, PUSH — these are CLI commands, file writes, or skill invocations with low token volume.

**Cost impact**: ~70% of agent-eligible work (EXECUTE subagents + SIMPLIFY + research) runs on Sonnet. Only SPEC and PLAN benefit from parent model capability.

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
| Hygiene | `claude-md-management:claude-md-improver`, `/compact` | Long-session context maintenance |

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

### Pipeline Templates

Pipeline templates control which steps run. `PRD_CAPS` controls which skill
to invoke per step. These are two separate concerns.

| Template | Steps | Use case |
|---|---|---|
| `full` | spec → plan → execute → review | Default for superpowers. New features, refactors. |
| `tdd-first` | plan → execute → review | Plan IS the test suite. TDD discipline during execute. |
| `single-pass` | execute → review | Spec is inline from QUERY. Small features, fixes. |
| `debug-only` | execute | No spec/plan. Root cause → fix → verify. |
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
│  3. SPEC      <PRD skill> → spec.md at vault path           │
│  4. PLAN      <PRD skill> → plan.md at vault path           │
│  5. EXECUTE   <PRD execution skill> → implement             │
│  6. SIMPLIFY  Agent(simplify-worker, model: sonnet) → fix  │
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
│ POSTLUDE — context hygiene (conditional)                    │
│ 15. COMPACT   /compact if context >70% or 5+ cycles in      │
├─────────────────────────────────────────────────────────────┤
│ IDLE DISCOVERY (when CORE finds no claimable work)          │
│  Skip to POSTLUDE steps 11–15 regardless of cadence.        │
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
     Store as `PRD_PIPELINE`. Resolve `prd_disciplines` if declared.
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

**Uncited raw check (mandatory when `query_vault` in BACKEND_CAPS):** After wiki-query,
scan for uncited raw articles that have no downstream concept page
citations. If found, treat them as claimable work items alongside any
QUERY results. Prioritize: uncited raw > other work.

**If `query_vault` not in BACKEND_CAPS:**
Use git-based context: `git log --oneline -20` for recent activity,
`git diff --stat HEAD~5` for recent changes, and `grep -r` across the
codebase for terms related to the current task. Feed results into the
PRD skill's exploration step. No vault context available — the PRD
skill works from code and git history alone.

Note: `skillwiki drift` is deferred to IDLE DISCOVERY (step 3) because
it makes network calls and is expensive for the QUERY step.

### 2. WORK — create work item (mandatory)

**If `create_work_item` in BACKEND_CAPS (skillwiki path):**
Create or open a work item under
`{vault}/projects/{slug}/work/YYYY-MM-DD-{work-slug}/`. proj-work emits
redirect paths for `spec.md` and `plan.md`. Pass these to steps 3–4.

proj-work validates frontmatter (see its SKILL.md for required fields:
`title`, `name`, `description`, `kind`, `status`, `priority: high|medium|low`,
`project: "[[slug]]"` wikilink format, timestamps, provenance).

**If `create_work_item` not in BACKEND_CAPS (git-local path):**
Create a local work item under `.claude/dev-loop-work/YYYY-MM-DD-{work-slug}/`
in the project repo. Create `spec.md` and `plan.md` in that directory.
Pass these local paths to steps 3–4. No vault frontmatter needed — use
a simple YAML header with `title`, `status`, `kind`, and `created` date.

**Gitignore:** `.claude/dev-loop-work/` contains session artifacts, not
repo content. Ensure it's listed in `.gitignore` when running in `none`
mode. The project-config template includes a Gitignore section for this.

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

### 4. PLAN — plan artifact (conditional on `prd_pipeline` + `PRD_CAPS`)

**If `plan` step is NOT in the active pipeline template:** skip to step 5.

**If `plan` step IS in the active pipeline template:**

- **`plan` in PRD_CAPS:** Invoke the registered plan skill with `spec.md`.
  Output: `plan.md` at redirect path.
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
- If any `prd_disciplines` entry has `when: execute`, pass its context
  to the execute skill as advisory guidance.
- If execution encounters errors and any discipline has `when: failure`
  with `mode: reactive`, interrupt EXECUTE, invoke the reactive discipline
  (e.g., systematic-debugging), then resume.

### 6. REVIEW — code quality gate (conditional on `prd_pipeline` + `PRD_CAPS`)

**If `review` step is NOT in the active pipeline template:** skip to step 7.

**If `review` step IS in the active pipeline template:**

- **`review` in PRD_CAPS:** Invoke the registered review skill on all
  modified/new files. Fix every issue raised before any further step.
  No bypass for `mode: mandatory` disciplines.
- **`review` not in PRD_CAPS:** Manual code review (or skip for
  vault-only work where no code was touched).

### 7. SAVE — crystallize session insights (optional)

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

### 12. DISTILL — concept promotion / ADRs (conditional, every 3 cycles)

**If `distill` in BACKEND_CAPS (skillwiki path):**

DISTILL (concept pages) — run if either:
- Three cycles have completed since the last DISTILL run, OR
- A retro this cycle flagged `Generalize?: yes`.

DISTILL pulls compound retro entries from the project wiki, identifies
recurring patterns (≥2 occurrences across cycles), and writes a vault
concept page at `concepts/dev-loop-<slug>.md` with provenance pointing
back to the source retros.

ADR (workflow decisions) — run `skillwiki:proj-decide` if a retro this
cycle flagged `WorkflowShift?: yes`. Writes an ADR under
`projects/{slug}/architecture/decisions/`. ADRs that generalize also
get a corresponding concept page in the global wiki.

**If `distill` not in BACKEND_CAPS (git-local path):**
Grep local retro files in `.claude/dev-loop-work/` for recurring
patterns (same ≥2 occurrence threshold). Append findings to
`.claude/dev-loop-work/compound.md` — a persistent file that
accumulates cross-cycle patterns. Not as rich as a vault concept page,
but preserves the distillation intent.
If a retro flagged `WorkflowShift?: yes`, note it in
`compound.md` for future reference when a vault becomes available.

### 13. AUDIT — `claude-md-management:claude-md-improver` (conditional, every 3 cycles)

Run ONLY if any of:
- Three cycles have completed since the last AUDIT run.
- A retro this cycle had `ClaudeMd?: yes`.

Skip otherwise. Running every cycle creates churn-y diffs and noise.
The 3-cycle cadence aligns with DISTILL so consolidation happens in one
phase.

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

### 15. COMPACT — `/compact` (conditional, context-driven)

Run ONLY if any of:
- Context window utilization is above ~70%.
- Five or more cycles have run in the current session.
- The session has crossed the daily-end checkpoint.

`/clear` remains forbidden mid-session.

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
   - `skillwiki:wiki-lint` — vault health, fix issues found
   - `skillwiki:wiki-audit` — provenance integrity check
   - `skillwiki:wiki-crystallize` — capture any session insights
   - `skillwiki:proj-distill` — promote compound entries to concepts
   - `skillwiki:proj-decide` — record any pending ADRs
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

4. Invoke research agent with `model: "sonnet"` — see `research/SKILL.md` in
   this skill directory. Code and vault health scanning is mechanical
   analysis; Sonnet handles it at lower cost without quality loss.
   ```
   Agent(description: "Dev-loop research", model: "sonnet", prompt: "Run research cycle with intensity: <normal|high>. BACKEND_CAPS: <caps>. VAULT_TYPES: <types>. Scan code health and vault health per research/SKILL.md.")
   ```
   Pass intensity through (`normal` or `high`). Also pass
   `BACKEND_CAPS` and `VAULT_TYPES` (derived from config at REFRESH)
   so the research agent can skip Track B when `query_vault` not in
   BACKEND_CAPS.
   If it returns ranked recommendations, the next dev-loop cycle picks
   up the top item via the WORK step.
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

```
simplify-worker passes? (model: sonnet)
  ├── NO  → fix issues, re-run simplify-worker
  └── YES → run E2E (if applicable)
              ├── any tier fails? → fix, re-run from simplify-worker
              └── ALL PASS        → DEPLOY (if applicable)
                                     ├── deploy fails? → report, do not retry auth
                                     └── deploy OK     → PUSH: bump → commit → push → tag (CI publishes)
                                                              └── CI green? → proceed to RETRO
                                                                   └── CI red?  → fix workflow, re-push tag
```

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
10. **`/clear` is session-end only.** `/compact` is the in-loop tool.
11. **Consolidation is every 3 cycles, not per-cycle.** DISTILL, AUDIT,
    VERIFY share the 3-cycle cadence and run as a single phase.
12. **Tier 1 is project, Tier 2 is global.** Project retros stay in
    `projects/{slug}/`. Generalized patterns lift to `concepts/` only
    via DISTILL.
13. **Publishing follows config.** `publish_via: ci-tag-trigger` is the
    safe default. Local `npm publish` prompts for auth and breaks
    `/loop` idempotency.
14. **Idle cycles run maintenance.** When CORE finds no claimable work,
    run consolidation and maintenance instead of exiting idle. Never
    waste a cycle. When `lint_vault` in BACKEND_CAPS: run skillwiki
    maintenance skills. Otherwise: run git-based housekeeping.
15. **Counts are not a contract.** E2E success is `exit 0`, not a magic
    number of assertions. Discover counts at cycle start; never
    hardcode them in this skill.
16. **Fix friction in-cycle.** When a retro identifies a code-fixable
    friction (e.g., lint --fix creating duplicates, missing schema),
    implement the fix in the same cycle rather than filing it as
    backlog. Backlog is for deferred decisions, not for known code
    fixes. Filing a known fix as backlog and re-discovering it in
    future cycles is waste.
17. **Verify CI after push.** After PUSH (step 10), check CI status
    with `gh run list --limit 1` and `gh run watch` if in-progress.
    Do NOT proceed to RETRO while CI is failing. If CI fails, inspect
    `gh run view <id> --log-failed`, fix the workflow, and re-push
    the tag.
18. **Use local CLI, not global** when `lint_vault` in BACKEND_CAPS.
    When the project has a local build of skillwiki (or a
    `cli_entry_override` in config), prefer it over the globally
    installed `skillwiki` binary. A stale global version produces false
    lint warnings and missing schema detections. Use `npx skillwiki` or
    the config override, not `skillwiki` directly. When `lint_vault`
    not in BACKEND_CAPS: not applicable (no skillwiki binary needed).
19. **Respect `BACKEND_CAPS`.** Each step checks capability membership
    before invoking backend-specific operations. When a capability is
    absent, use the documented git-based alternative or document why
    the step is intentionally skipped. Never silently fail — the user
    must see which steps were skipped and why. When new backends are
    added, they declare capabilities in the config; steps pick them
    up automatically.
20. **Block on skill-source drift.** If REFRESH detects that the cached
    SKILL.md differs from the source but the user hasn't reloaded
    plugins, block the cycle. Running stale skill logic silently is
    worse than stopping and asking the user to `/reload-plugins`.
21. **Execution subagents always run on sonnet.** When `subagent_dispatch`
    in PRD_CAPS, every subagent spawned during EXECUTE (implementer,
    spec reviewer, code quality reviewer) must include
    `model: "sonnet"`. The superpowers:subagent-driven-development
    templates omit `model` — the controller MUST add it. None of these
    roles benefit from the parent model. If `CLAUDE_CODE_SUBAGENT_MODEL`
    is set to a non-empty value, it globally overrides per-agent model
    parameters — it must remain empty (`""`) for this rule to work.

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

## Bootstrap Mode

If the user explicitly asks to bootstrap a new project (or REFRESH
fallback 3 fires), run the **two-step bootstrap**:

### Step A: Create config file

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

## Research Agent

The companion research agent prompt lives in `research/SKILL.md` adjacent to
this `SKILL.md`. It is invoked from IDLE DISCOVERY step 4. The research
agent shares the same project config; do not duplicate config fields.
