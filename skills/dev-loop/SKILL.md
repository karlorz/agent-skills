---
name: dev-loop
description: "Generic single-pass PRD + skillwiki dev cycle. Project-agnostic engine that reads `.claude/dev-loop.config.md` from CWD for project specifics, falling back to CLAUDE.md introspection then repo autodiscover. Pass `high` for aggressive mode."
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

## System Context

| Layer | Tool | Role |
|-------|------|------|
| PRD | Any compatible skill (superpowers, CodeStable, custom) | Brainstorm, spec, plan, execute, review |
| Knowledge | Pluggable via `knowledge_layer` config — default `skillwiki`, also `none` | Ingest, validate, query, crystallize, distill, decide, lint, audit |
| Quality | `/simplify` (or equivalent reviewer) | Pre-push code review gate |
| Hygiene | `claude-md-management:claude-md-improver`, `/compact` | Long-session context maintenance |

The knowledge layer is pluggable via `knowledge_layer` in the project config.
Steps branch on **capabilities**, not backend names — check `if <capability> in
BACKEND_CAPS` rather than `if knowledge_layer == "skillwiki"`. This lets new
backends slot in by declaring which capabilities they provide.

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
│  9. DEPLOY    deploy artifacts to remote hosts (if any)     │
│ 10. PUSH      release per project config (CI publishes)     │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — single-cycle (mandatory)                         │
│ 11. RETRO     append one-line retro to vault log (Tier 1)   │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — every-3-cycles consolidation (conditional)       │
│ 12. DISTILL   proj-distill (concepts) / proj-decide (ADRs)  │
│ 13. AUDIT     claude-md-improver → CLAUDE.md updates        │
│ 14. VERIFY    skillwiki wiki-audit → provenance integrity   │
├─────────────────────────────────────────────────────────────┤
│ POSTLUDE — context hygiene (conditional)                    │
│ 15. COMPACT   /compact if context >70% or 5+ cycles in      │
├─────────────────────────────────────────────────────────────┤
│ IDLE DISCOVERY (when CORE finds no claimable work)          │
│  Skip to POSTLUDE steps 11–15 regardless of cadence.        │
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

2. **Reload plugins** — run `/reload-plugins` to pick up any skill or
   command changes from prior cycles. Skip on first cycle if no edits.

3. **Load project config** in this order:
   - **Primary**: read `./.claude/dev-loop.config.md` (relative to CWD).
     Parse the YAML-style fields described in `templates/project-config.md`.
     Parse `knowledge_layer` (default: `skillwiki`). Then resolve
     `BACKEND_CAPS` — read the `knowledge_backends` map if present in
     config (see templates/project-config.md for schema); otherwise derive
     defaults from `knowledge_layer` + `vault` fields. If `query_vault` in
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
     BACKEND_CAPS from it),
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
     prompt user with: *"No dev-loop config found. Run `bootstrap` to
     scaffold `.claude/dev-loop.config.md`?"* If the user declines or
     `knowledge_layer` cannot be determined, default to `none` and
     proceed with git-based alternatives.

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
further step. No bypass. (`/simplify` is provided by the superpowers
skill suite; if not installed, do a manual code review instead.)

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

   **If `lint_vault` not in BACKEND_CAPS (git-local maintenance):**
   - Run `git gc --auto` if the repo is large
   - Prune stale local branches: `git branch --merged | grep -v main`
   - Run project lint/format if available (e.g., `npm run lint`)
   - Check for outdated dependencies if lockfile exists
   - Check for unpushed commits: `git log origin/$RELEASE_BRANCH..HEAD --oneline`
   - Verify work-item directories are complete (spec + retro present)

4. Invoke research agent — see `research.md` in this skill directory.
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

### Vault-Only Fast-Path

When the work item is **purely vault edits** (no code touched, no git
push needed), further collapse the trivial pipeline:

1. **QUERY** — normal.
2. **WORK** — skip (no code spec/plan needed for vault-only edits).
3. **SPEC** — skip.
4. **PLAN** — skip.
5. **EXECUTE** — inline vault edits (page creation, frontmatter fixes,
   citation normalization).
6. **VALIDATE** — `skillwiki validate` on each modified page (required
   before touching `index.md` or `log.md`).
7. **SIMPLIFY** — skip (no code to review).
8. **E2E / PUSH** — skip by default. Push vault changes only if the
   vault has accumulated significant edits (git commit + push).

This shorter path avoids creating work-item directories for routine
vault maintenance (typing a query page, fixing citations, enriching a
thin page). The standard trivial path remains available for vault work
that benefits from work-item tracking (e.g., a multi-page enrichment
campaign).

## Pre-Push Gate (when PUSH applies)

```
/simplify passes?
  ├── NO  → fix issues, re-run simplify
  └── YES → run E2E (if applicable)
              ├── any tier fails? → fix, re-run from simplify
              └── ALL PASS        → DEPLOY (if applicable)
                                     ├── deploy fails? → report, do not retry auth
                                     └── deploy OK     → PUSH: bump → commit → push → tag (CI publishes)
                                                              └── CI green? → proceed to RETRO
                                                                   └── CI red?  → fix workflow, re-push tag
```

A push that bypasses simplify is a broken release. Treat E2E and DEPLOY
with the same discipline if the project has them.

## N9 Reingest Protocol

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

## Hard Rules

1. **Always REFRESH first.** Reload plugins, load project config, read
   CLAUDE.md and MEMORY.md fresh every cycle.
2. **Always start work with proj-work.** Redirect paths come from
   there, not from the PRD skill.
3. **PRD skill is pluggable.** superpowers is the default, not required.
4. **Never push without simplify.** Hard gate for code changes;
   git-only and vault-only work skip simplify (nothing to review). E2E
   joins the gate when the project has it.
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
18. **Use local CLI, not global.** When the project has a local build
    of skillwiki (or a `cli_entry_override` in config), prefer it over
    the globally installed `skillwiki` binary. A stale global version
    produces false lint warnings and missing schema detections. Use
    `npx skillwiki` or the config override, not `skillwiki` directly.
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

## Obsidian Integration

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
2. **From Claude** — `/wiki-add-task <text>` appends to
   `raw/transcripts/YYYY-MM-DD-ad-hoc-captures.md`.

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

The companion research agent prompt lives in `research.md` adjacent to
this `SKILL.md`. It is invoked from IDLE DISCOVERY step 4. The research
agent shares the same project config; do not duplicate config fields.
