---
name: Dev loop project config (template)
description: Copy this file to .claude/dev-loop.config.md in your project repo, then fill in the fields below. The dev-loop skill reads this at REFRESH and uses it for every step.
type: template
---

# Dev Loop — {project-name}

> **Edit this file when porting the dev-loop to a new project.**
> Every field here replaces a hardcoded value in the engine.
> Empty fields disable the corresponding step (e.g., empty `e2e_scripts`
> skips step 8; empty `publish_via` skips step 9).
>
> Set `knowledge_layer: none` to run the loop without a vault or wiki —
> all knowledge steps use git-based alternatives.
>
> The knowledge layer is pluggable. Steps branch on **capabilities**, not
> backend names — adding a new backend means declaring which capabilities
> it supports in the `knowledge_backends` registry.

## Parser contract

Dev-loop reads this Markdown document through
`scripts/dev-loop-config-schema.js`, which invokes the read-only
`dev-loop-config-schema.py` bridge. Runtime parsing requires Python 3 and
PyYAML. If either capability is unavailable, status, config-lint, and migration
report a structured parser error and fail closed; they never fall back to
line-oriented regular expressions.

- Put configuration only in `yaml` or `yml` fenced blocks. Initial Markdown
  frontmatter is document metadata and is not part of the dev-loop config.
- Blocks merge in document order. Maps merge recursively; a later scalar or
  list replaces the earlier value at the same path.
- Every normalized path retains the one-based source line of its winning key
  or list item. Lint and migration diagnostics expose that provenance.
- The schema rejects malformed YAML, duplicate mapping keys, unknown schema
  keys, and incorrect nested value types. Explicit extension maps such as
  `preflight.defaults` and `notes` may contain project-defined keys.
- A key-shaped YAML declaration outside a fenced block is an error. Ordinary
  Markdown prose, headings, and non-YAML code fences remain valid.
- `dev-loop-config-migrate.js` is an advisor only. It consumes the same parsed
  object, emits suggested YAML, and never rewrites this file.

## Identity

```yaml
slug: <project-slug>
release_branch: <branch-name>  # e.g., main, dev, master
```

## PRD layer

Controls which skill suite drives the brainstorm → spec → plan → execute →
review pipeline. The `prd_layer` field names the primary backend; its
capabilities are resolved at REFRESH into `PRD_CAPS`. Steps 3–6 check
capability membership instead of naming specific skills.

Pipeline templates (`prd_pipeline`) control which steps run. `PRD_CAPS`
controls which skill to invoke per step. These are two separate concerns.

```yaml
prd_layer: superpowers             # superpowers | codestable | tdd | manual | none
prd_pipeline: full                 # full | tdd-first | single-pass | debug-only | manual
                                    # (default per prd_layer; override from config)
```

### PRD backends registry (optional)

Override skill mappings or add future backends. If absent, defaults are
derived from `prd_layer` + installed skills.

```yaml
prd_backends:
  superpowers:
    capabilities: [brainstorm, spec, plan, execute, review, subagent_dispatch]
    skills:
      brainstorm: superpowers:brainstorming
      plan: superpowers:writing-plans
      execute: superpowers:subagent-driven-development
      execute_fallback: superpowers:executing-plans
      review: simplify
  codestable:
    capabilities: [spec, execute, review]
    skills:
      spec_execute: codestable:generate
      review: codestable:validate
  tdd:
    capabilities: [spec, plan, execute, review]
    skills:
      spec: inline
      plan: superpowers:writing-plans
      execute: superpowers:test-driven-development
      review: superpowers:requesting-code-review
  manual:
    capabilities: [execute]
    skills:
      execute: inline
  none:
    capabilities: []
```

**Capabilities by backend:**

| Capability | superpowers | codestable | tdd | manual | none |
|---|---|---|---|---|---|
| `brainstorm` | yes | no | no | no | no |
| `spec` | yes (via brainstorm) | yes | inline | no | no |
| `plan` | yes | no | yes | no | no |
| `execute` | yes | yes | yes | inline | no |
| `review` | yes | yes | yes | manual | no |
| `subagent_dispatch` | yes | no | no | no | no |

### Cross-cutting disciplines (optional)

Disciplines are advisory overlays, not pipeline stages. They declare
when they apply and whether they are advisory, mandatory, or reactive.

```yaml
prd_disciplines:
  - skill: superpowers:test-driven-development
    when: execute       # apply during EXECUTE step
    mode: mandatory     # hard gate — must follow TDD
    include_paths:                    # NEW — only fires when changed files match
      - <glob-or-path>                # e.g., packages/convex/convex/resumes.ts
    # exclude_paths: [...]            # NEW — escape hatch, files to skip even when
                                      # they'd match include_paths
  - skill: superpowers:test-driven-development
    when: execute
    mode: advisory      # applies to all other files — catch-all
    # no include_paths → matches all files NOT matched by a stricter discipline
    # above. Engine resolves first-match-wins.
  - skill: superpowers:systematic-debugging
    when: failure       # invoke when EXECUTE encounters errors
    mode: reactive      # interrupt EXECUTE, invoke debugging, resume
```

`when` values: `execute`, `review`, `failure`, `always`
`mode` values: `advisory` (skill decides), `mandatory` (hard gate), `reactive` (interrupt on trigger)
`include_paths` (NEW, optional): list of globs or file paths — discipline only fires when changed files match. Omit for global scope.
`exclude_paths` (NEW, optional): list of globs or file paths — escape hatch from `include_paths`. Applied after include_paths. Only meaningful when `include_paths` is set.

### Discipline resolution: first-match-wins

When multiple disciplines share the same `{skill, when}` pair, the engine
intersects changed files with each discipline's paths. First match wins:

1. Start from the top of `prd_disciplines[]`.
2. For each discipline matching the current step's `when`:
   - If `include_paths` is set → intersect with changed files.
   - If any changed file matches → **this discipline applies, stop.**
   - If `include_paths` is NOT set → matches all files (catch-all). Stop.
3. If no discipline matches → no discipline injected for this step.

**Example resolution:**

```yaml
prd_disciplines:
  - skill: superpowers:test-driven-development
    when: execute
    mode: mandatory
    include_paths: [packages/convex/convex/aiScoring*.ts]    # TDD mandatory here
  - skill: superpowers:test-driven-development
    when: execute
    mode: advisory                                            # TDD advisory everywhere else
```

A change to `aiScoringUtils.ts` → matches first entry → `mode: mandatory`.
A change to `README.md` → skips first entry (path mismatch), falls to second → `mode: advisory`.

**Backwards compatibility:** `include_paths` and `exclude_paths` are both optional.
Omitting both preserves the current global behavior — the discipline applies to
all files. Existing configs continue to work unchanged.

**Friction guard:** a discipline with `mode: mandatory` and no `include_paths`
triggers a warning at REFRESH: "`mandatory` discipline <skill> has no
`include_paths` — this creates a global hard gate. Consider scoping it to
critical paths." The discipline still runs — this is a warning, not an error.

## Critical paths (optional)

Declares project hot-spots — code files, vault concept pages, and history
incidents that matter more than average files. The dev-loop engine uses
critical paths for:

- **REFRESH**: load into `CRITICAL_PATHS` session variable (missing → empty dict)
- **QUERY**: bias wiki-query toward listed vault pages first
- **IDLE research Track A**: rank coverage gaps in `code:` paths above other
  source files
- **WORK**: when a claimable item touches a path under any `critical_paths.*.code`,
  mark the work item `priority: high` automatically

```yaml
critical_paths:
  <name>:
    code: [<glob-or-path>, ...]           # source files this path covers
    vault: [<concept-or-query-page-slug>, ...]  # vault pages to bias toward
    history_pins: [<free-text incident reference>, ...]  # dated incident references
```

**Example:**

```yaml
critical_paths:
  resume_search:
    code:
      - packages/convex/convex/resumes.ts
      - packages/convex/convex/search.ts
    vault:
      - resume-search-architecture
    history_pins:
      - "2026-03-14: 16 MiB byte-limit incident on resume import"
  ai_scoring:
    code:
      - packages/convex/convex/aiScoring*.ts
    vault:
      - llm-primary-scoring
    history_pins:
      - "PR #674: LLM-primary scoring switch"
```

Omit the section entirely or leave it empty (`critical_paths: {}`) if the
project has no hot-spots. The engine defaults to equal priority for all files.

## Fact-check tier (optional)

Controls how dev-loop agents access external knowledge sources when writing
specs, plans, or debugging. Without this section, agents rely on local repo
context and vault queries only — no web access.

```yaml
fact_check:
  enabled: true
  source_order:                     # priority order for fact lookups
    - local_repo                    # search codebase first
    - context7                      # Context7 library docs (if installed)
    - vault_query                   # skillwiki vault (if available)
    - web_search                    # web search via configured tool
  web_tools:
    primary: <mcp-tool-name>        # e.g., mcp__grok-search__web_search
    deep_fetch: <mcp-tool-name>     # e.g., mcp__grok-search__web_fetch
    site_map: <mcp-tool-name>       # e.g., mcp__grok-search__web_map
    plan_first: <mcp-tool-name>     # e.g., mcp__grok-search__plan_intent
  triggers:
    - <free-text trigger>           # e.g., "version claims", "CVE checks", "deprecation notices"
  evidence_contract:
    require_sources_used_section: true   # outputs must cite sources
    cite_session_id: true               # for reproducibility
```

**Source order explanation:**
- `local_repo` — search codebase with grep/glob before hitting external services
- `context7` — use Context7 MCP for library/framework docs (fast, free, versioned)
- `vault_query` — check the skillwiki vault for prior decisions and concepts
- `web_search` — live web search as a last resort (costly, may be rate-limited)

**Web tool backends:**
Any MCP server exposing `web_search`, `web_fetch`, `site_map` tools works.
Common choices:
- `mcp__grok-search__*` — xAI Grok (real-time-friendly, X integration)
- Built-in `WebSearch` / `WebFetch` — Claude Code's native web tools
- `perplexity-mcp` — Perplexity-based search
- `brave-search-mcp` — Brave Search API

**Evidence contract:** When `require_sources_used_section: true`, any
SPEC/PLAN output that used external sources must include a `## Sources Used`
section. The simplify review checks for this on non-trivial outputs.

Omit the section or set `enabled: false` to skip fact-checking — agents
work from local context only. Missing `web_tools` entries are detected at
REFRESH and the web tier is skipped with a warning.

## Idle deep-research (optional)

When the IDLE DISCOVERY mechanical scan returns no P2+ findings, the loop
exits idle — wasting cron cycles. Idle deep-research turns dead cycles
into a vault-resident research backlog by invoking `/deep-research` on
rotating topics.

```yaml
idle_deep_research:
  enabled: true
  skill: deep-research                 # /deep-research skill
  trigger:
    when: idle_after_mechanical_scan   # fires only when truly idle
    if: no_p2_or_higher_findings       # safety: don't burn budget if there's P2+ work
    cooldown: every_3rd_idle_cycle     # prevents budget burn on back-to-back idles
    max_per_day: 4                     # absolute cap across all cycles
  topic_seeds: [<free-text topic>, ...]  # rotating research topics
  topic_selection:
    bias_toward: critical_paths        # prefer topics matching critical_paths.*.code
    skip_if_recent_query_page_exists: 14d  # skip topic if vault has recent query page
  output_mode: vault                   # writes queries/<slug>.md
  budget:
    web_searches: 3
    deep_fetches: 3
    context7_calls: 3
  followups:
    on_finding: schema_compatible_vault_queue  # queue findings without making them executable
    p_score_default: P3               # deep-research findings start at P3
```

**How it works:**
1. When IDLE DISCOVERY step 3 (mechanical research) returns no P2+ findings,
   check if `idle_deep_research.enabled` and cooldown allows.
2. Pick the next rotating topic from `topic_seeds` (round-robin), biased
   toward topics matching `critical_paths.*.code` if declared.
3. Skip the topic if the vault already has a query page for it created
   within `skip_if_recent_query_page_exists` days.
4. Invoke `/deep-research <topic> --vault` with the declared budget.
5. Extract 1-3 actionable ideas → route through the schema-compatible vault
   queue. If the active schema lacks a non-executing work-item status, write
   ad-hoc captures under `raw/transcripts/` instead of creating invalid work
   items.
6. Mark the cooldown timestamp for the next eligible idle cycle.

**Why this matters:** Long-running cron loops (e.g., `*/15 * * * *`)
generate 96 cycles/day. Without idea-generation, ~70% of those are no-op
idle exits. Wiring `/deep-research` turns dead cycles into compounding
research backlog.

Omit the section or set `enabled: false` to disable — idle cycles exit
after maintenance with no research.

## Investigate mode (optional)

Proactive finding queue mode. When invoked via `/dev-loop investigate`, scans
project health and queues schema-valid findings in the vault. Proposed work
items are used only when the active skillwiki schema validates a non-executing
`status: proposed`; otherwise findings are captured under `raw/transcripts/`
for human promotion. Current SkillWiki schemas such as 0.9.16 reject
`status: proposed`, so raw captures are the expected queue shape for those
vaults.

```yaml
investigate:
  max_items: 5                # cap per invocation (high doubles it to 10)
  topic_seeds: []             # fallback deep-research topics; reuses idle_deep_research.topic_seeds if empty
```

**Fields:**
- `max_items` (int, default 5): Maximum work items created per investigate
  invocation. High intensity doubles this value.
- `topic_seeds` (list, default []): Topics for deep-research in high mode
  when no user topic is provided. Falls back to
  `idle_deep_research.topic_seeds` if empty — projects that already
  configured those get investigate deep-research for free.

**Invocation examples:**
```
/dev-loop investigate                           # normal, autonomous scan, cap 5
/dev-loop investigate high                      # adds deep-research, cap 10
/dev-loop investigate "plugin SDK changes"      # steers deep-research to topic
/dev-loop investigate high "plugin SDK changes" # high + user topic
```

Omit the section to use defaults (max_items: 5, topic_seeds from
idle_deep_research). Investigate mode itself is always available when
`query_vault` in BACKEND_CAPS — the config section only controls tuning.

## Preflight prep mode (optional)

Human-attended readiness mode. When invoked via `/dev-loop prep`, the loop
inventories current project work, dry-runs selection, batches all questions
that would otherwise interrupt implementation, and writes only approved
readiness metadata plus managed body sections. It does not execute code
changes and does not start `/goal`.

```yaml
preflight:
  enabled: true
  default_limit: 5
  default_lanes: [work, captures, hygiene]
  require_approved_spec_and_plan: true
  unattended_not_ready_behavior: skip
  defaults:
    compatibility_policy: "Platform compatibility changes are additive unless explicitly scoped otherwise."
```

**Fields:**
- `enabled` (bool, default `true`): Allows `/dev-loop prep`. Set false only
  when a project intentionally manages readiness outside dev-loop.
- `default_limit` (int, default 5): Small batch size for attended review.
  Use `/dev-loop prep --all` for full-project sweeps.
- `default_lanes` (list, default `[work, captures, hygiene]`): Inventory
  lanes scanned by default. Override per invocation with `--lane`.
- `require_approved_spec_and_plan` (bool, default true): Marks items
  executable only after both the spec and plan are approved.
- `unattended_not_ready_behavior` (`skip`, default): In `/goal` or other
  unattended contexts, not-ready work is skipped and reported instead of
  prompting a human.
- `defaults` (map, optional): Stable project-level answers that preflight
  can recommend in the batch question manifest. Promote defaults only after
  explicit human approval.

At REFRESH, dev-loop resolves this block into `PREFLIGHT_POLICY`.
`/dev-loop prep` applies the policy when constructing inventory commands,
question manifests, readiness writes, and suggested `/goal` text.

### Readiness metadata

Preflight stores fast gates in work-item frontmatter and durable rationale
in managed body sections. Unknown frontmatter fields are advisory and must
be backed by body text so future schema rewrites can repair them.

```yaml
automation_ready: true
human_questions_resolved: true
spec_preflight_approved: true
plan_preflight_approved: true
preflight_state: ready
last_preflight: 2026-06-05
merge_auto_approved: false
```

`merge_auto_approved` is independent from general automation readiness. Keep
it false unless the operator explicitly approves auto-merge for this one work
item.

Recommended managed sections:
- `## Preflight Approval` - approval timestamp, approved defaults, deferred
  questions, and human overrides.
- `## Automation Readiness` - why the item is or is not safe for unattended
  execution.
- `## Open Questions` - any unresolved decisions that must block `/goal`
  pickup.

Common `preflight_state` values:

```yaml
# Ready for unattended /goal pickup.
automation_ready: true
human_questions_resolved: true
spec_preflight_approved: true
plan_preflight_approved: true
preflight_state: ready

# A human answer is still required.
automation_ready: false
human_questions_resolved: false
spec_preflight_approved: true
plan_preflight_approved: false
preflight_state: needs_human

# The user deferred this item from the approved batch.
automation_ready: false
human_questions_resolved: true
spec_preflight_approved: false
plan_preflight_approved: false
preflight_state: deferred

# Disk/git evidence suggests the item may already be obsolete or shipped.
automation_ready: false
human_questions_resolved: true
spec_preflight_approved: false
plan_preflight_approved: false
preflight_state: stale_or_done

# The item needs schema or structural repair before it can be approved.
automation_ready: false
human_questions_resolved: true
spec_preflight_approved: false
plan_preflight_approved: false
preflight_state: invalid
```

### Runtime behavior

`/dev-loop prep` calls `scripts/preflight-inventory.js` with the resolved
project slug, vault path, repo path, `default_limit`, and selected lanes. It
then verifies selected items against disk/git state, synthesizes one batch
question manifest with recommended defaults, asks for approval in the main
session, writes only approved items, validates touched specs/plans, and writes
a report under `projects/{slug}/requirements/`.

Invocation examples:
```
/dev-loop prep
/dev-loop prep --limit 10
/dev-loop prep --lane work --lane captures
/dev-loop prep --work 2026-06-05-dev-loop-preflight-prep-mode
/dev-loop prep --all
```

## Browser verification (optional)

Automated browser verification gate for projects with browser-facing code.
Runs between SIMPLIFY and MERGE to catch browser regressions (a11y
violations, console errors, broken routes) before they reach the PR.

```yaml
browser_verification:
  enabled: true
  trigger:                          # path globs that fire the gate
    - "apps/**/*.tsx"
    - "apps/**/*.css"
  prerequisites:                     # commands that must be running before gate
    - "make dev"                     # e.g., start dev server
  driver: playwright-cli             # /playwright-cli skill
  base_url: http://localhost:5173
  smoke_routes:                      # routes to verify
    - /
    - /dashboard
  reviser_workflow:                   # ordered MCP tool calls
    - take_snapshot
    - list_console_messages
    - evaluate_script
  e2e_fallback: <command>            # full e2e when /playwright-cli too narrow
```

**How it works:**
1. **Trigger check**: Only fires when changed files match `trigger` globs.
   If no changed files match, the gate is skipped entirely.
2. **Prerequisite check**: Before running, verify that prerequisites are
   healthy (e.g., `curl -fsS <base_url> >/dev/null`). If not running,
   block the gate with an actionable message.
3. **Driver dispatch**: Spawn `/playwright-cli` agent (model: sonnet)
   with smoke routes and reviser workflow.
4. **Console-error gate**: Console errors/warnings during
   `list_console_messages` → **fail gate**, return to EXECUTE for fix.
   The merge-blocker is console errors, not snapshot diffs.
5. **E2E fallback**: If `/playwright-cli` is too narrow for the change,
   run `e2e_fallback` command instead.

Omit the section or set `enabled: false` to disable — no browser
verification gate runs.

## Reactive debugging (optional)

Controls how dev-loop handles EXECUTE failures — retry budget, evidence
capture, fact-checking of external-lib errors, and escalation policy.
Without this section, reactive debugging is unbounded: agents may retry
indefinitely on the same error.

```yaml
reactive_debugging:
  enabled: true
  auto_retry_attempts: 2              # max retries before escalation
  evidence_dir: .claude/dev-loop-debug/
  evidence_capture:                    # commands run on each failure
    - "make check 2>&1 | tee {evidence_dir}/{cycle}.log"
    - "git diff --stat"
    - "git log --oneline -5"
  fact_check_tool: <mcp-tool>         # e.g., mcp__grok-search__web_search
  escalate_after:
    consecutive_idle_cycles: 3         # escalate if failing across cycles
    same_error_signature: true         # dedup by stack-trace hash
  escalation_action: surface_p1_finding  # next idle picks it up as P1
```

**How it works:**
1. When EXECUTE fails, invoke `prd_disciplines[].when: failure` (existing).
2. **Before retry**: capture evidence per `evidence_capture` commands, hash
   the error signature (top-3 stack frames + library name).
3. **Fact-check external libs**: if the stack trace contains an external
   library name (Convex/Hono/Vite/etc.) AND `fact_check_tool` is set,
   call the tool with the error message before retrying. This catches
   version-specific breakage without burning the whole retry budget.
4. **Retry up to `auto_retry_attempts`**: if still failing, fall through
   to escalation.
5. **Escalation**: write a P1 finding to `raw/transcripts/` with
   `kind: bug` + error signature hash. Future cycles can dedup against
   this hash to prevent the same bug being filed N times.

**Evidence dir gitignore:** The evidence dir (`.claude/dev-loop-debug/`
by default) must be in `.gitignore` regardless of `knowledge_layer`.
Evidence captures are transient session artifacts, not repo or vault
content — they should never be committed.

**Signature hashing:** Top-3 frames from the stack trace + detected
library name (regex match against known frameworks). This is a
deterministic hash that identifies "the same error" across retries and
cycles, preventing duplicate escalation.

Omit the section or set `enabled: false` to disable — reactive debugging
runs with unbounded retries (legacy behavior).

## Code review (optional, since v1.15.0)

Configures the REVIEW step's code-review backends. The base `simplify:simplify`
skill always runs for code changes, preferably through the
`dev-loop:simplify-worker` subagent adapter when worker dispatch is available.
An optional second-opinion backend (`dev-loop:codex-review-worker`, which wraps
`codex:codex-rescue`) can be enabled per-intensity. When enabled, REVIEW step
6 runs the simplify pass first, then spawns the optional worker via
`Agent(model: "sonnet")`; findings concatenate under per-backend section
headers. No auto-reconciliation between reports.

```yaml
code_review:
  parallel: true                        # always true for now; reserved
  codex:
    enabled_in_normal: false            # opt-in for /dev-loop (no `high`)
    enabled_in_high: false              # opt-in for /dev-loop high
    agent: dev-loop:codex-review-worker # the wrapper agent (do not change)
```

Engine wiring:

1. **REFRESH** resolves the `code_review` block into `CODE_REVIEW_BACKENDS`:
   - Always includes `simplify:simplify` as the required base skill; prefer
     `dev-loop:simplify-worker` for subagent isolation when available.
   - Conditionally appends `dev-loop:codex-review-worker` when the
     current intensity's `enabled_in_*` toggle is true AND neither
     `dev-loop:codex-review-worker` nor `codex:codex-rescue` is in
     `DEP_DRIFT` (doctor-worker reports the latter at REFRESH step 7).
2. **REVIEW step 6** runs the simplify pass via `dev-loop:simplify-worker`
   when possible, or inline `Skill("simplify:simplify")` when worker dispatch
   is unavailable. It spawns optional worker backends in
   `CODE_REVIEW_BACKENDS` when present. Output is concatenated.
3. Missing config block → defaults to base-only (preserves
   pre-v1.15.0 behavior). Backwards compatible.

Cost note: enabling Codex in normal mode means **every** full-pipeline
cycle pays Codex's per-call cost. Suitable for projects where a second
opinion matters (security-critical code, complex refactors). Skip for
high-throughput trivial-fast-path work.

Omit the section to keep base-only review (current default behavior).

## Knowledge layer

Controls how the loop captures, queries, and maintains project knowledge.
The `knowledge_layer` field names the primary backend; its capabilities
are resolved at REFRESH into `BACKEND_CAPS`. Steps check capability
membership instead of the backend name directly.

When `knowledge_layer: none`, the loop uses git-based alternatives
for work items, retros, distillation, and lint. No vault is required.

```yaml
knowledge_layer: skillwiki       # skillwiki | none
```

### Knowledge backends registry (optional)

Override backend-specific config or add future backends. If absent,
defaults are derived from `knowledge_layer`.

```yaml
knowledge_backends:
  skillwiki:
    vault: auto                 # portable: resolve with `skillwiki path`
    cli_entry: skillwiki         # or npx tsx packages/cli/src/cli.ts for local dev
  none:
    work_dir: .claude/dev-loop-work/
```

For SkillWiki, `vault: auto` is the portable default. At REFRESH, dev-loop
resolves it by running `skillwiki path`; if that fails, it may use a
validated `~/wiki` fallback only when `~/wiki/SCHEMA.md` and `~/wiki/projects/`
exist. If neither resolves, vault-backed capabilities are disabled for the
cycle with a clear warning. Explicit non-`auto` paths remain supported as
intentional overrides, but dev-loop warns when an explicit path differs from
`skillwiki path`:

```
Configured SkillWiki vault '<configured>' differs from `skillwiki path` '<resolved>'.
Use `vault: auto` for portable configs, or keep the explicit path only if this
repo is intentionally pinned to one machine.
```

Legacy top-level `vault` is still supported as an alias for older configs, but
new and migrated configs should put vault settings under
`knowledge_backends.skillwiki.vault`.

**Capabilities by backend:**

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

Steps branch on **capabilities**, not backend names. When a capability is
absent from BACKEND_CAPS, use the documented git-based alternative or
document why the step is intentionally skipped.

Vault type directories are **discovered from SCHEMA.md** at REFRESH time,
not hardcoded here. The REFRESH step parses the `## Layers` section of
`{vault}/SCHEMA.md` to extract the list of typed-knowledge subdirectories
(e.g., `entities/`, `concepts/`, `comparisons/`, `queries/`, `meta/`).
If SCHEMA.md doesn't exist or can't be parsed, the REFRESH step falls back
to listing directories in the vault root that contain `.md` files.

When `query_vault` not in BACKEND_CAPS, vault settings are ignored — the loop
uses git history and local work items instead of a vault.

## Vault write hygiene (optional, since v1.17.0)

Controls whether the dev-loop SAVE step auto-commits vault changes made
by Edit/Write tool calls during the cycle. The skillwiki CLI's AUTO_COMMIT
only triggers on CLI writes, not on native tool calls — this flag fills
that gap.

```yaml
vault_auto_commit: true   # commit dirty vault files at end of SAVE step 7 (default: true)
```

When `true` (default), SAVE step 7 runs `git -C $VAULT add -A && git -C $VAULT commit`
before crystallize logic. Clean tree → skip silently. When `false`, vault
commits are left to the user.

AUDIT step 13 also checks vault tree cleanliness — if dirty, it warns the
user to commit manually or enable `vault_auto_commit`.

## Vault sync coordination (optional, since v1.18.0)

Controls whether dev-loop acquires the skillwiki advisory lockfile before
pushing vault changes. Requires skillwiki >= v0.6.0 (which ships the
`--acquire-lock` / `--release-lock` flags). When `peer_aware: true`,
SAVE step 7 and MERGE step 6b-2 gate vault `git push` behind lock
acquisition with a 30-second timeout — preventing the rebase-conflict-storm
pattern when dev-loop and other sessions (Obsidian, parallel shells) race
on vault git operations.

```yaml
vault_sync:
  peer_aware: true              # acquire advisory lock before vault push (default: true when vault_auto_commit: true)
  lock_timeout_seconds: 30      # max wait for lock acquisition before deferring
  retry_budget: 3               # max consecutive deferrals before surfacing P2 finding
  presync_skill: auto-detect    # auto-detect | always | never — invoke vault-local wiki-presync before push
```

When `peer_aware: false` or skillwiki lacks `--acquire-lock`:
- SAVE step 7 and MERGE step 6b-2 push directly (current behavior)
- A one-time warning is emitted: "vault_sync.peer_aware is disabled — vault pushes are not coordinated with peer sessions"

**Lock acquisition is best-effort, never blocking.** If a peer holds the
lock, the cycle defers the push and continues. The vault commit stays
local until the next cycle. AUDIT step 13 reports contention events.

**`presync_skill` modes:**
- `auto-detect` (default): probe `$VAULT/.claude/skills/wiki-presync/SKILL.md`
  at cycle start. If present, invoke it before each vault push — it runs lint
  gate, collision dedup, and `git pull --rebase`. If the presync skill fails,
  the push is skipped (presync failure means the vault has issues that should
  block a push). Vaults without the skill see no change.
- `always`: require the skill; warn if missing but push anyway.
- `never`: skip the presync probe entirely, even if the skill is present.

## Interview

Controls interactive interview phases. The `interview` section is separate from
`knowledge_backends` — interviews are session-scoped and interactive, not
persistent knowledge operations. Two capabilities: `setup_interview` (one-time
project bootstrap) and `work_item_interview` (conditional, per SPEC step).

When the `interview` section is absent, both capabilities are off — the loop
runs fully automated with no interactive phases.

```yaml
interview:
  setup:
    skill: setup-dev-loop          # bundled, always available
    glossary: grill-with-docs      # delegates domain section when installed (optional)
  work_item:
    # Native interview is the implied fallback when no upgrade is installed.
    upgrade: grill-with-docs       # optional: grill-with-docs | grill-me
    trigger: auto                  # auto | manual | never
    goal_override: never           # never | allow — behavior when goal_context in ORCHESTRATION_CAPS (v1.22.0)
```

**Interview backends:**

| Backend | Type | Provides | Install |
|---------|------|----------|---------|
| `native` | Built-in | `work_item_interview` | None (always available) |
| `grill-with-docs` | External | `setup_interview` (glossary), `work_item_interview` | `npx skills@latest add mattpocock/skills --skill grill-with-docs -a claude-code -g -y` |
| `grill-me` | External | `work_item_interview` | `npx skills@latest add mattpocock/skills --skill grill-me -a claude-code -g -y` |
| `setup-dev-loop` | Bundled | `setup_interview` | None (bundled with dev-loop) |

**Trigger modes:**
- `auto` — run ambiguity detection before SPEC, grill if ambiguous (default)
- `manual` — only grill when work item has `grill: true`
- `never` — fully automated, no interviews

**Goal override (v1.22.0):**
- `never` (default) — skip GRILL entirely when running under /goal context.
  Requirements should be clarified BEFORE setting /goal.
- `allow` — proceed with normal trigger logic even under /goal. Useful when
  the user intentionally monitors a /goal session and wants to answer
  interview questions manually.

## Code layout

Used by introspection, research agent, and trivial-cycle scoping.

```yaml
cli_src: <glob-or-path>          # e.g., packages/cli/src/commands/, src/
cli_test: <glob-or-path>         # e.g., packages/cli/test/commands/
skills_glob: <glob-or-empty>     # e.g., packages/skills/*/SKILL.md, or empty
cli_entry_override: <command>    # e.g., npx tsx packages/cli/src/cli.ts, or empty
```

If `cli_entry_override` is set, the loop uses it instead of the
installed binary when the project's CLI is part of the work.

## E2E

Each script must exit 0 to pass. Counts are NOT part of the contract —
the engine never depends on a specific assertion count.

```yaml
e2e_scripts:
  - scripts/e2e-local.sh
  - scripts/e2e-remote.sh
  - scripts/e2e-plugin.sh
```

Set to empty list `[]` to skip step 8 entirely.

## Release

```yaml
bump_script: <path-or-empty>      # e.g., ./scripts/bump-version.sh
publish_via: <mode>                # ci-tag-trigger | local | none
deploy_script: <path-or-empty>     # e.g., bash apps/hub/deploy/update-msi1.sh, or empty
manifests_count: <N>               # how many manifests bump_script touches (sanity check)
remote_hosts: [<host>, ...]        # e.g., [sg01], or [] if not applicable
```

`publish_via` modes:

| Mode | Behavior |
|------|----------|
| `ci-tag-trigger` | Bump → commit → push → tag → CI publishes. Verify tag landed on remote after push. |
| `local` | Project's local release script runs on dev host (caution: interactive auth breaks /loop idempotency). |
| `none` | Skip step 10 (PUSH). Deploy may still run if `remote_hosts` or `deploy_script` is set. |

`deploy_script` is the command line to execute for step 9 (DEPLOY).
It should be idempotent and handle its own rollback on failure.
Leave empty to skip DEPLOY entirely.

## Release policy (optional)

Controls whether step 10 (PUSH) auto-bumps version when committed files
match declared globs. Without this block, PUSH expects the user (or an
upstream skill) to have already bumped the version manifests before the
cycle reaches step 10 (pre-1.19.0 behavior).

```yaml
release_policy:
  auto_bump: true                        # default: false. Set true to enable PUSH gating.
  channel: beta                          # default: stable. Passed to bump_script as RELEASE_CHANNEL env var.
  trigger_globs:                         # any committed file matching these makes PUSH fire
    - "packages/skills/**"
    - "packages/cli/**"
    - "packages/shared/**"
    - ".claude-plugin/marketplace.json"
    - "scripts/bump-version.sh"
  skip_globs:                            # cycles where ALL files match these skip PUSH
    - "raw/**"
    - "concepts/**"
    - "entities/**"
    - "queries/**"
    - "projects/**"
    - "_archive/**"
    - "*.md"                             # standalone doc-only commits
  tag_format: "v{version}"               # consumed by bump_script / tag-push logic
  verify_after_push: true                # ls-remote + gh run watch after tag push
```

Semantics:

- **`auto_bump: false`** (or block absent) → preserves pre-1.19.0 behavior.
  Manual bump expected before the cycle reaches PUSH.
- **Glob matching** uses shell-style glob with `**` for recursive path
  matching (Python `glob` semantics), patterns relative to repo root.
  Example: `skills/**` matches any file under `skills/` at any depth.
- **Decision logic**: PUSH skips entirely when (a) no changed files match
  any `trigger_globs` pattern, OR (b) every changed file matches at least
  one `skip_globs` pattern. Otherwise `bump_script` runs.
- **Channel** is a hint to `bump_script` (passed as `RELEASE_CHANNEL` env
  var). dev-loop does NOT compute version strings — the project's
  `bump_script` owns version computation.
- **`verify_after_push: true`** is recommended — without it, a failed
  publish.yml run is silent until the next cycle.

## CI Configuration

Controls how required checks are discovered and how CI health is monitored
during MERGE and IDLE DISCOVERY. CI configuration is observational: it does
not grant authority to merge a PR. Merge authority is configured separately
under `merge_policy`.

Set `ci_configured: true` after running `/dev-loop setup` Section F,
which generates GitHub Actions workflows and optionally configures
branch protection.

### CI discovery mode (how required checks are resolved)

**Default: `runtime`** — dev-loop queries the GitHub API at merge time
to discover required status checks from branch protection. No config
duplication; GitHub is the source of truth. This is the recommended
mode for repos where `/dev-loop setup` has configured branch protection.

**Optional override: `explicit`** — list required check names in config.
Use this when branch protection is not configured (or managed outside
dev-loop) and you need dev-loop to know which checks matter.

```yaml
ci_configured: false              # set to true after /dev-loop setup Section F
ci_discovery: runtime             # runtime | explicit (default: runtime)

# Only used when ci_discovery: explicit
required_checks:                  # check names matching GitHub Actions job names
  - ci                            # from .github/workflows/ci.yml
  - e2e                           # from .github/workflows/e2e.yml
  # - security-scan              # uncomment when security.yml is added
```

When `ci_configured: false` (the default), the MERGE step can still create a
PR but cannot satisfy the auto-merge CI gate. When `true`, dev-loop observes
the configured checks. Only an exact `healthy` classification can satisfy the
CI gate; `degraded`, `broken`, missing, and unknown results fail closed.

**Runtime discovery** uses:
- `gh api repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks`
  to discover which checks are required
- Falls back to `gh api repos/{owner}/{repo}/actions/runs --jq`
  if branch protection is not configured (lists all recent workflow runs)

**Explicit mode** is for repos where:
- Branch protection is managed by a different team/tool
- You want dev-loop to monitor specific checks regardless of branch protection
- You have workflows that are required but not enforced by branch protection

## Merge policy

Controls repository routing and auto-merge authority independently from CI
discovery. Omitting the block applies the fail-closed defaults shown below.

```yaml
merge_policy:
  strategy: repo-policy                # repo-policy | branch-policy alias | pull-request
  auto_merge: false                    # explicit repository capability switch
  merge_method: squash                 # squash | merge | rebase
  require_work_item_approval: true     # required whenever auto_merge is true
```

- `repo-policy` preserves the normal route: direct push on
  `release_branch`, PR from a feature branch.
- `branch-policy` is accepted as a compatibility alias for `repo-policy`.
- `pull-request` refuses a release-branch commit/push and requires work to be
  performed on a feature branch so a PR can be created.
- `auto_merge: true` does not authorize any individual work item. The active
  `spec.md` must also contain `merge_auto_approved: true`.
- `require_work_item_approval` must remain `true` when auto-merge is enabled.
  Config lint rejects the unsafe combination.
- Auto-merge is eligible only for a PR with repository authorization,
  per-work-item approval, and an exact `healthy` CI classification.

Recommended default:

```yaml
merge_auto_approved: false
```

`/dev-loop prep` may set this work-item field to `true` only after the operator
explicitly approves automatic merging for that candidate. General preflight
approval is not merge approval.

## Notes (optional)

Free-form project-specific gotchas, compatibility notes, paths to
canonical specs, etc. The engine reads this for context but does not
parse fields.

```yaml
notes:
  canonical_spec: <path-to-spec>
  compat: <free-form>
  conventions: <free-form>
```

## Gitignore

When `knowledge_layer: none`, the loop creates local work items under
`.claude/dev-loop-work/`. These are session artifacts — add to
`.gitignore`:

```
.claude/dev-loop-work/
```

When `knowledge_layer: skillwiki`, no gitignore entry is needed — work
items live in the vault, not the repo.

---

## Worked example (commented — do not activate)

<!--
slug: llm-wiki
release_branch: dev

knowledge_layer: skillwiki
knowledge_backends:
  skillwiki:
    vault: auto
    cli_entry: skillwiki

cli_src: packages/cli/src/commands/
cli_test: packages/cli/test/commands/
skills_glob: packages/skills/*/SKILL.md
cli_entry_override: npx tsx packages/cli/src/cli.ts

e2e_scripts:
  - scripts/e2e-local.sh
  - scripts/e2e-remote.sh
  - scripts/e2e-plugin.sh

bump_script: ./scripts/bump-version.sh
publish_via: ci-tag-trigger
manifests_count: 6
remote_hosts: [sg01]

ci_configured: true
ci_discovery: runtime
# required_checks: not needed — branch protection is the source of truth

merge_policy:
  strategy: repo-policy
  auto_merge: false
  merge_method: squash
  require_work_item_approval: true

notes:
  canonical_spec: ~/wiki/projects/llm-wiki/history/specs/2026-05-02-llm-wiki-skill-design.md
  hermes_compat: ~/.skillwiki/.env primary, ~/.hermes/.env fallback
  conventions: 14 SKILL.md files; CLI commands paired with test files
-->
