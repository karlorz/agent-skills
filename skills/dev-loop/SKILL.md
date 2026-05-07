---
name: dev-loop
description: "Generic single-pass PRD + skillwiki dev cycle. Project-agnostic engine that reads `.claude/dev-loop.config.md` from CWD for project specifics, falling back to CLAUDE.md introspection then repo autodiscover. Pass `high` for aggressive mode."
argument-hint: "[high]"
---

# Dev Loop — PRD + Skillwiki (Generic Engine)

> **Status: ACTIVE.** Phase 3 cutover complete.
> Spec at `~/wiki/projects/llm-wiki/work/2026-05-07-dev-loop-skill-extraction/spec.md`.

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

## System Context

| Layer | Tool | Role |
|-------|------|------|
| PRD | Any compatible skill (superpowers, CodeStable, custom) | Brainstorm, spec, plan, execute, review |
| Knowledge | `skillwiki` (CLI + skills) | Ingest, validate, query, crystallize, distill, decide, lint, audit |
| Quality | `/simplify` (or equivalent reviewer) | Pre-push code review gate |
| Hygiene | `claude-md-management:claude-md-improver`, `/compact` | Long-session context maintenance |

The active PRD skill is pluggable. Default chain:
`superpowers:brainstorming` → `superpowers:writing-plans` →
`superpowers:subagent-driven-development` (fallback `executing-plans`).

## Knowledge Tiers

| Tier | Where | When |
|---|---|---|
| 1 — Cycle journal | **Project wiki** (`projects/{slug}/work/.../`, vault log) | Every cycle (RETRO) |
| 2 — Generalized concepts | **Global wiki** (`concepts/dev-loop-*.md`) | Every 3 cycles (DISTILL) |
| 3 — Workflow ADRs | **Project wiki** ADR (+ optional global concept) | On workflow shift only |

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
│  6. SIMPLIFY  /simplify → fix every issue (HARD GATE)       │
├─────────────────────────────────────────────────────────────┤
│ OPTIONAL (run if config declares)                           │
│  7. SAVE      wiki-crystallize → session insights           │
│  8. E2E       project test suites → all must exit 0         │
│  9. PUSH      release per project config (CI publishes)     │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — single-cycle (mandatory)                         │
│ 10. RETRO     append one-line retro to vault log (Tier 1)   │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — every-3-cycles consolidation (conditional)       │
│ 11. DISTILL   proj-distill (concepts) / proj-decide (ADRs)  │
│ 12. AUDIT     claude-md-improver → CLAUDE.md updates        │
│ 13. VERIFY    skillwiki wiki-audit → provenance integrity   │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — context hygiene (conditional)                    │
│ 14. COMPACT   /compact if context >70% or 5+ cycles in      │
├─────────────────────────────────────────────────────────────┤
│ IDLE DISCOVERY (when CORE finds no claimable work)          │
│  Skip to POSTLUDE steps 10–14 regardless of cadence.        │
│  Then run any applicable skillwiki maintenance skills:      │
│  - wiki-lint     → vault health check                       │
│  - wiki-audit    → provenance integrity                     │
│  - wiki-crystallize → session insights (if any)             │
│  - proj-distill  → concept page promotion                   │
│  - proj-decide   → ADR for pending workflow shifts          │
│  Then invoke research agent (see research.md).              │
│  Exit with one-line summary of what was done.               │
└─────────────────────────────────────────────────────────────┘
```

## Step Details

### 0. REFRESH — context hygiene + config load (mandatory, ~15s)

1. **Reload plugins** — run `/reload-plugins` to pick up any skill or
   command changes from prior cycles.

2. **Load project config** in this order:
   - **Primary**: read `./.claude/dev-loop.config.md` (relative to CWD).
     Parse the YAML-style fields described in `templates/project-config.md`.
   - **Fallback 1**: read `CLAUDE.md` for "Current counts" and "Where
     things live" sections; extract slug, paths, e2e scripts. Use these
     deterministic patterns (verified in Phase 2 verification work
     item, T2):

     | Field | Source pattern | Notes |
     |-------|----------------|-------|
     | `slug` | basename of CLAUDE.md's parent directory | implicit project identity |
     | `vault` | first occurrence of `~/wiki` (or other tilde-path) in CLAUDE.md body | empty if no match → skip vault steps |
     | `cli_src` | first match of `packages/[a-z-]+/src/commands/` or `src/commands/` | check existence before accepting |
     | `cli_test` | first match of `packages/[a-z-]+/test/commands/` or `test/commands/` | check existence before accepting |
     | `skills_glob` | `packages/skills/*/SKILL.md` if `packages/skills/` exists, else `skills/*/SKILL.md` | runtime discovery for count |
     | `release_branch` | regex `default branch \(\`([^\`]+)\`\)` | falls back to `main` if no match |
     | `e2e_scripts` | regex `e2e-[a-z]+\.sh` from CLAUDE.md, **excluding** `e2e-common.sh` (helper, not a runnable suite) | each entry prefixed `scripts/` |
     | `manifests_count` | regex `([0-9]+) manifests` | optional sanity check field |
     | `remote_hosts` | look for SSH host names in e2e-remote / e2e-plugin descriptions (e.g., `sg01`) | empty list if none |
     | `cli_entry_override` | NOT recoverable from CLAUDE.md — leave empty, fall through to fallback 3 if dev-mode tsx wrapper is required |
   - **Fallback 2**: introspect repo conventions:
     - CLI src: `packages/*/src/commands/`, `src/commands/`, or `cli/`
     - Skills glob: `packages/*/SKILL.md` or `skills/*/SKILL.md`
     - E2E scripts: `scripts/e2e-*.sh` or `test/e2e/*.sh`
     - Vault: `~/wiki` if it exists, else skip vault-dependent steps
   - **Fallback 3**: if critical fields (slug, vault) cannot be
     resolved, prompt user with: *"No dev-loop config found. Run
     `bootstrap` to scaffold `.claude/dev-loop.config.md`?"*

3. **Read CLAUDE.md and MEMORY.md fresh** — the system-prompt copy
   loaded at session start goes stale if a prior cycle edited them.

   First cycle in a session that hasn't edited skills or CLAUDE.md can
   skip step 1 (plugin reload) as a no-op, but must always do step 2
   (config) and step 3 (CLAUDE.md/MEMORY.md re-read).

### 1. QUERY — `skillwiki:wiki-query` (mandatory)

Search the vault (resolved from `vault` config field) for prior specs,
plans, concepts, decisions overlapping the task. Feed results into the
PRD skill's exploration step. Skip if `vault` is empty.

### 2. WORK — `skillwiki:proj-work` (mandatory)

Create or open a work item under
`{vault}/projects/{slug}/work/YYYY-MM-DD-{work-slug}/`. proj-work emits
redirect paths for `spec.md` and `plan.md`. Pass these to steps 3–4.

### 3. SPEC — `<PRD brainstorming/design skill>` (mandatory)

Default: `superpowers:brainstorming`. Pass the redirect path so the
spec lands in the vault.

### 4. PLAN — `<PRD planning skill>` (mandatory)

Default: `superpowers:writing-plans`. Pass the redirect path.

### 5. EXECUTE — `<PRD execution skill>` (mandatory)

Preferred: `superpowers:subagent-driven-development`. Fallback:
`superpowers:executing-plans`.

### 6. SIMPLIFY — `/simplify` review (mandatory, hard gate)

Run on all modified/new files. Fix every issue raised before any
further step. No bypass.

### 7. SAVE — `skillwiki:wiki-crystallize` (optional)

At natural breakpoints, crystallize insights not captured in spec/plan.
Skip if `vault` is empty.

### 8. E2E (optional — run if `e2e_scripts` config field is non-empty)

Run each script from `e2e_scripts` in declared order. Each must exit 0
before the next starts. Counts are NOT a contract — only the exit code is.

### 9. PUSH (optional — run if `publish_via` config field is non-empty)

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

### 10. RETRO — Tier 1 cycle journal (mandatory)

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

### 11. DISTILL — `skillwiki:proj-distill` / `proj-decide` (conditional, every 3 cycles)

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

### 12. AUDIT — `claude-md-management:claude-md-improver` (conditional, every 3 cycles)

Run ONLY if any of:
- Three cycles have completed since the last AUDIT run.
- A retro this cycle had `ClaudeMd?: yes`.

Skip otherwise. Running every cycle creates churn-y diffs and noise.
The 3-cycle cadence aligns with DISTILL so consolidation happens in one
phase.

### 13. VERIFY — `skillwiki:wiki-audit` (conditional, every 3 cycles)

Run after DISTILL/AUDIT to verify per-page that every `^[raw/...]`
reference resolves and source frontmatter matches the body. Catches
broken provenance from rotated raw files or moved concept pages. Quick
read-only check — should report zero issues in healthy cycles.

### 14. COMPACT — `/compact` (conditional, context-driven)

Run ONLY if any of:
- Context window utilization is above ~70%.
- Five or more cycles have run in the current session.
- The session has crossed the daily-end checkpoint.

`/clear` remains forbidden mid-session.

## Idle Discovery (when CORE finds no claimable work)

When QUERY returns no claimable work and nothing is in progress, the
cycle doesn't end empty. Skip CORE steps 2–9 and run maintenance
instead:

1. Run RETRO (step 10) as a maintenance retro — no work-slug, just
   note that this was an idle cycle.
2. Run consolidation steps 11–13 regardless of their normal 3-cycle
   cadence (idle time is free — use it).
3. Run any applicable skillwiki maintenance skills:
   - `skillwiki:wiki-lint` — vault health, fix issues found
   - `skillwiki:wiki-audit` — provenance integrity check
   - `skillwiki:wiki-crystallize` — capture any session insights
   - `skillwiki:proj-distill` — promote compound entries to concepts
   - `skillwiki:proj-decide` — record any pending ADRs
4. Invoke research agent — see `research.md` in this skill directory.
   Pass intensity through (`normal` or `high`). If it returns ranked
   recommendations, the next dev-loop cycle picks up the top item via
   the WORK step.
5. **Pick up P3 work if no P2+ items exist** (normal mode). After
   research completes, if the backlog contains only P3 items, pick the
   top P3 item and execute it using the trivial cycle fast-path. In
   **high** mode, skip the priority guard entirely and pick up the
   top-ranked item regardless of P-score.
6. Exit with a one-line summary: `"Idle cycle — ran [skills executed],
   research: [findings summary]."` or `"P3 pickup — [work-slug]:
   [result]."`.

## Trivial Cycle Fast-Path

When the work item is scoped to a small, well-defined change (single
subcommand, config tweak, small bug fix, under ~50 LOC in normal mode
or ~80 LOC in high mode), collapse the pipeline:

1. **QUERY** — normal.
2. **WORK** — `proj-work` as usual, but note `kind: trivial` in the
   work item.
3. **SPEC** — inline spec in the work-item folder (skip brainstorming).
4. **PLAN** — skip (spec is the plan for trivial changes).
5. **EXECUTE** — inline (no subagent dispatch).
6. **SIMPLIFY** — still mandatory. Self-review diff against spec
   acceptance.
7. **E2E / PUSH** — if applicable.

Retro and consolidation steps are unchanged. The fast-path is a
*recommendation*, not a requirement — if scope creep makes a trivial
item non-trivial, escalate to the full pipeline.

## Pre-Push Gate (when PUSH applies)

```
/simplify passes?
  ├── NO  → fix issues, re-run simplify
  └── YES → run E2E (if applicable)
              ├── any tier fails? → fix, re-run from simplify
              └── ALL PASS        → bump → commit → push → tag (CI publishes)
                                          └── CI green? → proceed to RETRO
                                               └── CI red?  → fix workflow, re-push tag
```

A push that bypasses simplify is a broken release. Treat E2E with the
same discipline if the project has it.

## Hard Rules

1. **Always REFRESH first.** Reload plugins, load project config, read
   CLAUDE.md and MEMORY.md fresh every cycle.
2. **Always start work with proj-work.** Redirect paths come from
   there, not from the PRD skill.
3. **PRD skill is pluggable.** superpowers is the default, not required.
4. **Never push without simplify.** Hard gate. E2E joins the gate when
   the project has it.
5. **Validate before index.** `skillwiki validate` must pass before
   touching `index.md` or `log.md`.
6. **Raw is immutable.** Never modify files in `raw/` after ingestion.
7. **Trust the vault for history.** Query the wiki, not git history,
   for past decisions.
8. **Provenance stays project.** Pages: `provenance: project`,
   `provenance_projects: ["[[<project-slug>]]"]`.
9. **Fallback to wiki-ingest.** If proj-work redirect fails, use
   `wiki-ingest` manually.
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
    run consolidation and skillwiki maintenance skills instead of
    exiting idle. Never waste a cycle.
15. **Counts are not a contract.** E2E success is `exit 0`, not a magic
    number of assertions. Discover counts at cycle start; never
    hardcode them in this skill.

## Self-Learning Protocol

The Knowledge Tiers table above defines *where* each tier lands. This
section defines *when* each fires.

**Tier 1 — every cycle.** RETRO writes one line per cycle to the
project work item and the vault log. The flags (`Generalize?`,
`ClaudeMd?`, `WorkflowShift?`) are the deterministic input to Tiers 2
and 3.

**Tier 2 — every 3 cycles, or on demand.** DISTILL fires when either
the 3-cycle cadence elapses OR any retro in the window flagged
`Generalize?: yes`. Output: `concepts/dev-loop-<topic>.md` with
provenance back to the source retros.

**Tier 3 — on workflow shift only.** When a retro flags
`WorkflowShift?: yes`, run `skillwiki:proj-decide` to record an ADR.
Examples worth ADR-ing:
- Cadence changes (e.g., AUDIT cadence is 3, not 5).
- Hard-rule additions (e.g., no `/clear` during loops).
- Knowledge-tier reshuffles (e.g., promoting a project pattern to
  global).

If the ADR generalizes beyond the current project, add a corresponding
concept page in the global wiki on the same cycle.

This skill itself is updated when retros flag improvements — that
update IS a workflow shift, so record an ADR for non-trivial revisions.

## Bootstrap Mode

If the user explicitly asks to bootstrap a new project (or REFRESH
fallback 3 fires), copy `templates/project-config.md` into
`./.claude/dev-loop.config.md`, walk the user through filling in:

1. `slug` — project identifier
2. `vault` — wiki path (or empty)
3. `release_branch` — e.g., `main`, `dev`
4. Code layout fields (auto-detect candidates from repo structure)
5. E2E scripts (auto-detect from `scripts/`)
6. Release config (`publish_via`, `bump_script`, `manifests_count`)
7. Optional `notes` for project-specific gotchas

After bootstrap, re-run REFRESH to load the new config.

## Research Agent

The companion research agent prompt lives in `research.md` adjacent to
this `SKILL.md`. It is invoked from IDLE DISCOVERY step 4. The research
agent shares the same project config; do not duplicate config fields.
