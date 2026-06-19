---
name: setup-dev-loop
description: Scaffold per-repo dev-loop config (PRD layer, knowledge layer, release config, vault path) and build the project glossary with grill-with-docs. Run once per repo before using dev-loop.
---

# Setup Dev-Loop

Scaffold the per-repo configuration that dev-loop consumes:

- **PRD layer** — which skill suite drives brainstorm → spec → plan → execute → review
- **Knowledge layer** — how the loop captures, queries, and maintains project knowledge
- **Release config** — how artifacts are published and deployed
- **Vault path** — where skillwiki vault lives (if any)
- **Interview config** — when and how dev-loop asks clarifying questions per work item
- **Domain glossary** — CONTEXT.md and ADR directory via delegation to grill-with-docs

This is a prompt-driven skill, not a deterministic script. Explore, present findings, confirm with user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `CLAUDE.md` and `AGENTS.md` — does either exist?
- `CONTEXT.md` and `CONTEXT-MAP.md` at repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `./.claude/dev-loop.config.md` — does it already exist?
- Installed skills — `ls ~/.claude/skills/` for available PRD backends
- Installed interview backends — check for `grill-with-docs`, `grill-me` under `~/.claude/skills/`
- `skillwiki path` — is a vault configured?
- **Dependency doctor** — spawn `dev-loop:doctor-worker` (sonnet) to enumerate
  missing optional plugins:

  ```
  Agent(description: "Setup dep doctor", subagent_type: "dev-loop:doctor-worker", model: "sonnet", prompt: "Probe skills/dev-loop/dependencies.yaml. Report JSON.")
  ```

  Use the `missing_optional[]` output to drive install hints in Sections D
  (grill-with-docs), E (work-item interview backends), H (web search MCP for
  fact-check), I (deep-research), and J (playwright-cli). Each install hint
  pairs the missing ref with its documented fallback so users can decide:
  install for richer behavior, or accept the fallback.

  If `status: broken` (any required dep missing), abort setup with the
  required install commands — dev-loop can't run without them.

### 2. Present findings and ask

Summarise what's present and what's missing. Walk through decisions **one at a time**:

**Section A — PRD layer.**

> Explainer: The PRD layer is the skill suite that drives the brainstorm → spec → plan → execute → review pipeline. Pick the workflow that matches how you want to work.

Default posture: if superpowers skills are installed, propose `superpowers`. If only TDD skills are available, propose `tdd`. Otherwise `manual`.

Options:
- **superpowers** — brainstorming, writing-plans, subagent-driven-development (full pipeline)
- **codestable** — generate + validate (single-pass)
- **tdd** — test-driven-development with red-green-refactor
- **manual** — user drives everything, dev-loop is orchestrator only

**Section B — Knowledge layer.**

> Explainer: The knowledge layer controls how dev-loop captures retros, distills patterns, and maintains project knowledge. With skillwiki, everything persists to a queryable vault. Without it, dev-loop uses local files.

Default posture: if `skillwiki path` succeeds, propose `skillwiki`. Otherwise `none`.

Options:
- **skillwiki** — vault-backed knowledge with global queryability
- **none** — git-based alternatives, no vault dependency

**Section C — Release config.**

> Explainer: How are changes in this repo published and deployed? This controls the PUSH and DEPLOY steps.

Ask:
- How do you publish? (ci-tag-trigger, local, or none)
- Do you deploy to remote hosts? If so, which ones?
- What's the release branch? (main, dev, master)

**Section D — Domain glossary (delegate to grill-with-docs).**

> Explainer: A shared language document (CONTEXT.md) helps agents use precise terminology instead of 20 words where 1 will do. Invest 5 minutes now — it pays off every session.

If `grill-with-docs` is installed, tell the user: "I'll now invoke grill-with-docs to build the project glossary." Load it via `Skill("grill-with-docs")` and follow its interview process. When it finishes, resume here.

If `grill-with-docs` is NOT installed, tell the user: "For a richer glossary-building experience, install grill-with-docs: `npx skills@latest add mattpocock/skills --skill grill-with-docs -a claude-code -g -y`. For now, I'll capture key terms in CONTEXT.md manually." Then ask 2-3 domain questions and write a basic CONTEXT.md.

**Section E — Interview config.**

> Explainer: Dev-loop can ask clarifying questions before writing a spec. Two capabilities: **setup interview** (the bootstrap flow you're in now — always available) and **work-item interview** (optional per-work-item grilling before the SPEC step). The work-item interview uses a backend — native (3 fixed questions, zero dependencies), grill-with-docs (adaptive + terminology + CONTEXT.md), or grill-me (adaptive, no persistent files). You can also control when it fires.

Present the available backends:

| Backend | Install | When to pick |
|---------|---------|--------------|
| `native` | None (always available) | Quick alignment, CI contexts, minimal interaction |
| `grill-with-docs` | `npx skills@latest add mattpocock/skills --skill grill-with-docs -a claude-code -g -y` | Codebases you'll revisit, building shared language |
| `grill-me` | `npx skills@latest add mattpocock/skills --skill grill-me -a claude-code -g -y` | Adaptive questioning without persistent docs |

Default posture:
- Propose `native` — always works, no install required
- If `grill-with-docs` or `grill-me` is already installed, note it and offer as alternatives
- If Section D already chose grill-with-docs for glossary, mention the synergy: same skill handles both glossary building and work-item interviews

Then ask about trigger mode:

> Explainer: When does the interview fire? **auto** detects ambiguity (conflicting prior decisions, vague descriptions, zero prior art) and interviews only when needed. **manual** only interviews when a work item explicitly requests it. **never** disables interviews — the loop runs fully automated.

Options:
- **auto** (recommended) — ambiguity detection gates the interview, so it only fires when useful
- **manual** — only work items with `grill: true` trigger an interview
- **never** — no interviews, fully automated cycles

Default posture: propose `auto`. Most projects never notice the interview is there — ambiguity detection skips it for clear, well-scoped tasks.

**Section F — CI Setup.**

> Explainer: Dev-loop can create PRs with auto-merge after each cycle, but auto-merge without CI checks means code can merge untested. Setting up a minimal CI workflow ensures every PR is validated before it lands on main.

Check for existing CI:
- Does `.github/workflows/ci.yml` already exist? If yes, skip to confirmation.
- Does `.github/workflows/` exist with any other workflow? Note it for context.

If no CI workflow exists, detect the repo framework:

| Signal | Framework | CI steps |
|--------|-----------|----------|
| `package.json` with `scripts.lint` | Node.js | lint + type-check + test |
| `package.json` without `scripts.lint` | Node.js (minimal) | npm install + npm test |
| `Makefile` with `check` target | Make-based | make check |
| `pyproject.toml` | Python | ruff check + pytest |
| `Cargo.toml` | Rust | cargo clippy + cargo test |
| None of the above | Generic | echo "No CI steps detected — add manually" |

Present the detected framework and proposed CI steps. Ask:
> "I'll generate `.github/workflows/ci.yml` with these steps. Should I also enable branch protection on main (require CI to pass before merge)?"

Options:
- **Yes, CI + branch protection** — generate workflow and configure `gh api` branch protection
- **CI workflow only** — generate workflow, skip branch protection
- **Skip for now** — don't generate anything, set `ci_configured: false`

Default posture: propose "CI + branch protection" for new projects, "CI workflow only" for existing repos where branch protection might conflict with current workflows.

The generated workflow uses:
- `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }` to avoid duplicate runs
- Triggers on `push` to main and `pull_request` targeting main
- Caching for dependency installation (npm ci with cache, pip cache, etc.)
- No secrets required — all steps use public actions and local tooling

After generating the workflow:
- Set `ci_configured: true` in the `dev-loop.config.md` output
- Set `ci_workflow: .github/workflows/ci.yml` in the config

**Section G — Critical paths.**

> Explainer: Critical paths declare project hot-spots — code files, vault pages, and incident references that matter more than average files. The dev-loop engine biases research, query, and work-item priority toward these paths.

Ask:
> "Which areas of the codebase are most critical — the ones where bugs hurt most or changes are most frequent? Name 1-3 critical paths."

For each path the user names, ask:
1. **Code files** — "Which source files does this path cover? (glob patterns OK)"
2. **Vault pages** — "Are there concept or query pages in the vault related to this path? (slugs, optional)"
3. **History pins** — "Any memorable incidents or decisions tied to this path? (free-text, optional)"

If the user has no critical paths, leave the section empty. The engine defaults to equal priority for all files.

Default posture: if the repo has a CLAUDE.md or CONTEXT.md with known hot-spots, pre-populate suggestions.

**Config emitted:**

```yaml
critical_paths:
  <name>:
    code:
      - <glob-or-path>
    vault:
      - <concept-or-query-page-slug>
    history_pins:
      - <free-text incident reference>
```

**Runtime behavior:** Loaded at REFRESH into `CRITICAL_PATHS`. QUERY biases vault search toward `*.vault` slugs. WORK auto-escalates `priority: high` if changed files match `*.code` globs. Research agent ranks coverage gaps in `*.code` above other files. Schema reference: `templates/project-config.md` § Critical paths.

**Section H — Fact-check tier.**

> Explainer: Dev-loop agents can consult external knowledge sources (web search, library docs, vault queries) when writing specs and plans. Without fact-checking, agents rely on local context only — which can lead to version-sensitive errors or stale API assumptions.

Detect installed web MCP servers by checking available tool names:
- Look for `mcp__grok-search__*`, `mcp__brave-search__*`, or built-in `WebSearch`/`WebFetch`
- If none found, note: "No web search MCP detected — fact-check tier will be limited to local and vault sources."

Ask:
> "Should dev-loop agents be able to search the web for facts when writing specs and plans? I've detected: [list installed tools]."

Options:
- **Full fact-checking** — enable with detected web tools as primary, include source order and evidence contract
- **Local + vault only** — enable fact-checking but skip web tier (context7 + vault + local_repo)
- **Skip for now** — no fact-checking, agents use local context only

If the user picks full fact-checking:
1. Confirm the primary web tool (default: first detected)
2. Ask about evidence contract: "Should spec/plan outputs cite their sources?" Default: yes
3. Ask about triggers: "Any topics that should always trigger fact-checking? (e.g., version claims, CVEs, deprecation notices)"

Default posture: if grok-search is installed, propose full fact-checking with grok-search as primary. Otherwise, propose local + vault only.

**Config emitted:**

```yaml
fact_check:
  enabled: true
  source_order:
    - local_repo
    - context7
    - vault
    - web
  web_tools:
    primary: mcp__grok-search__web_search
  evidence_contract:
    require_sources_used_section: true
  triggers:
    - "version "
    - "deprecat"
    - "CVE-"
```

**Runtime behavior:** Loaded at REFRESH into `FACT_CHECK_CAPS` (source_order, `web_available` bool, evidence_contract). Passed to SPEC and PLAN — PRD skills consult sources in declared order for version/API/deprecation claims. Output specs include `## Sources Used` if contract requires it. REVIEW gate flags missing section. Schema reference: `templates/project-config.md` § Fact-check tier.

**Section I — Idle deep-research.**

> Explainer: When dev-loop's IDLE cycle finds no claimable work, it normally exits after maintenance. Idle deep-research turns those dead cycles into a research backlog by invoking `/deep-research` on rotating topics — building up forward-looking ideas that compound over weeks.

Ask:
> "Should idle dev-loop cycles run deep-research on rotating topics? This is useful for long-running cron loops that would otherwise exit idle."

Options:
- **Enable with custom topics** — specify 3-8 research topic seeds manually. Config output: `topic_seeds: [user-provided list]`, `bias_toward: critical_paths` (if Section G declared).
- **Enable with critical-path bias** — auto-generate `topic_seeds` from critical paths declared in Section G. Config output: `topic_seeds: [<auto-derived from critical_paths.*.code filenames and vault slugs>]`, `bias_toward: critical_paths`. Same as custom topics but pre-filled — the user can edit the derived list before writing.
- **Skip for now** — idle cycles exit after maintenance only. No `idle_deep_research` section in config.

If the user picks enable:
1. Ask for topic seeds: "Name 3-8 topics you'd like the loop to research when idle. These rotate round-robin." Suggest topics derived from `critical_paths.*.code` and any detected pain points.
2. Confirm cooldown and daily cap defaults: every 3rd idle cycle, max 4/day.
3. Confirm budget defaults: 3 web searches, 3 deep fetches, 3 context7 calls per research run.

Default posture: if the project has critical_paths, propose "enable with critical-path bias" as the default. Otherwise, propose "skip for now" — idle deep-research is most valuable on projects with long-running cron loops.

**Config emitted:**

```yaml
idle_deep_research:
  enabled: true
  topic_seeds:
    - <topic-1>
    - <topic-2>
  bias_toward: critical_paths
  cooldown_cycles: 3
  max_per_day: 4
  skip_if_recent_query_page_exists: 7
  budget:
    web_searches: 3
    deep_fetches: 3
    context7_calls: 3
```

**Runtime behavior:** Idle Discovery step 4.5 — fires only when research step 4 returns no P2+ findings and cooldown allows. Round-robins through `topic_seeds`, biased toward `critical_paths.*.code` matches when `bias_toward` is set. Honors `budget.*` caps per run. Output ideas route through the schema-compatible vault queue; use raw transcript captures when the active schema lacks a non-executing work-item status. Default score: `p_score_default: P3`. Schema reference: `templates/project-config.md` § Idle deep-research.

**Section J — Browser verification gate.**

> Explainer: Browser-facing changes can ship regressions (a11y violations, console errors, broken routes) if there's no automated verification gate. The browser verification step runs `/playwright-cli` between code review and merge to catch these before the PR is created.

Detect web frameworks:
- Look for `vite.config.*`, `next.config.*`, `package.json` with React/Vue/Svelte deps
- Look for existing `playwright.config.*`
- Check if `/playwright-cli` skill is available

If no web framework detected, skip this section with: "No web framework detected — browser verification not applicable."

If web framework detected, ask:
> "I detected [framework]. Should dev-loop verify browser changes before merge? This adds a `/playwright-cli` gate between code review and PR creation."

Options:
- **Enable browser verification** — configure trigger globs, dev server, smoke routes
- **Skip for now** — no browser gate, rely on manual testing

If enabled:
1. Ask: "Which file globs should trigger the browser gate?" (default: detected framework patterns, e.g., `apps/**/*.tsx`)
2. Ask: "What command starts the dev server?" (default: auto-detect from `package.json` scripts)
3. Ask: "What's the base URL?" (default: `http://localhost:5173` for Vite, `http://localhost:3000` for Next.js)
4. Ask: "Which routes should be smoke-tested?" (suggest common routes, user confirms/adds)
5. Ask: "Reviser workflow — the ordered steps /playwright-cli runs. Default: take_snapshot → list_console_messages → evaluate_script. Adjust?"
6. Ask: "E2E fallback — when /playwright-cli is too narrow, which command runs? (optional)"

Default posture: if Vite/React is detected and playwright-cli is installed, propose "enable" with sensible defaults. Otherwise, propose "skip."

**Config emitted:**

```yaml
browser_verification:
  enabled: true
  trigger:
    - "apps/**/*.tsx"
  prerequisites:
    - "curl -fsS http://localhost:5173 >/dev/null"
  base_url: http://localhost:5173
  smoke_routes:
    - /
    - /login
  reviser_workflow:
    - take_snapshot
    - list_console_messages
    - evaluate_script
  e2e_fallback: npm run test:e2e
```

**Runtime behavior:** Step 6a (between REVIEW and MERGE). Skipped unless changed files match `trigger` globs. Validates `prerequisites` (block on unhealthy), spawns `playwright-cli:browser-worker` (model: sonnet) to walk `reviser_workflow` on `smoke_routes`. Console errors fail the gate → return to EXECUTE. Schema reference: `templates/project-config.md` § Browser verification.

**Section K — Reactive debugging budget.**

> Explainer: When EXECUTE fails, dev-loop invokes systematic-debugging and retries. Without a budget, a reproducible failure can burn the daily web budget and lock the loop into the same broken step. The reactive-debug budget caps retries, captures evidence, fact-checks external-lib errors, and escalates persistent failures.

Ask:
> "Should reactive debugging have a retry budget and escalation policy? Without it, dev-loop retries indefinitely on the same error."

Options:
- **Enable with full budget** — output `reactive_debugging:` with `auto_retry_attempts`, `evidence_capture`, `fact_check_tool`, `escalate_after`, and `escalation_action`. Cap retries, capture evidence, fact-check external libs, escalate after N cycles.
- **Enable fact-check only** — output `reactive_debugging:` with `auto_retry_attempts` and `fact_check_tool` only. Skip `evidence_capture` and `evidence_dir` (not needed). Cap retries + fact-check external libs, no evidence capture.
- **Legacy behavior** — no `reactive_debugging:` section in config. Unbounded retries, no budget, no escalation.

If not legacy:
1. Confirm retry cap: "How many auto-retries before escalation?" (default: 2)
2. If full budget: Confirm evidence capture: "Capture evidence (make check log, git diff, last commits) on each failure?" (default: yes)
3. Confirm fact-check tool: if grok-search is detected (from Section H), offer: "Use grok-search to fact-check external-lib errors before retrying?" (default: yes)
4. Confirm escalation: "Escalate after how many consecutive idle cycles with the same error?" (default: 3)

Default posture: if fact-checking is enabled (Section H), propose "enable with budget" using the same fact_check_tool. Otherwise, propose "enable with budget" without fact-check.

**Config emitted:**

```yaml
reactive_debugging:
  enabled: true
  auto_retry_attempts: 2
  evidence_dir: .claude/dev-loop-debug/
  evidence_capture:
    - "make check 2>&1 | tee {evidence_dir}/{cycle}-check.log"
    - "git diff > {evidence_dir}/{cycle}-diff.patch"
  fact_check_tool: mcp__grok-search__web_search
  escalate_after:
    consecutive_idle_cycles: 3
    same_error_signature: true
```

**Runtime behavior:** Sub-step of EXECUTE — fires only when a `when: failure, mode: reactive` discipline is matched. Captures evidence under `evidence_dir` (with `{evidence_dir}`/`{cycle}` interpolation), hashes error signature, fact-checks external libs via `fact_check_tool`, retries up to `auto_retry_attempts`. On exhaustion + `escalate_after` match, files a P1 finding to `raw/transcripts/` keyed by hash (future cycles dedup). `evidence_dir` MUST be in `.gitignore`. Schema reference: `templates/project-config.md` § Reactive debugging.

**Section L — Discipline path scoping.**

> Explainer: Disciplines like TDD can be scoped to specific files via `include_paths` / `exclude_paths`. Instead of TDD mandatory everywhere (high friction) or advisory everywhere (no gate), you can make TDD mandatory on critical paths and advisory on everything else.

Ask:
> "Should any disciplines be scoped to specific files? For example, TDD mandatory on critical paths, advisory everywhere else."

Options:
- **Scope via critical_paths (recommended)** — auto-fill `include_paths` from critical paths declared in Section G. TDD mandatory on those files, advisory on everything else.
- **Scope manually** — specify include/exclude paths per discipline
- **Global scope** — disciplines apply to all files (current behavior)

If the user picks "scope via critical_paths":
- Auto-generate two discipline entries for each scoped discipline:
  ```yaml
  - skill: superpowers:test-driven-development
    when: execute
    mode: mandatory
    include_paths: [<auto-filled from critical_paths.*.code>]
  - skill: superpowers:test-driven-development
    when: execute
    mode: advisory
    # catch-all — no include_paths
  ```
- Show the generated entries and let the user adjust.

If the user picks "scope manually":
- Ask which skill to scope
- Ask for include_paths (glob patterns, one per line)
- Ask for exclude_paths (optional escape hatches)

Default posture: if critical_paths (Section G) were declared AND TDD is in `prd_disciplines[]`, strongly recommend "scope via critical_paths." This is the primary use case for Section L — the trends worked example needs TDD mandatory only on `critical_paths.*.code` files.

**Config emitted:**

```yaml
prd_disciplines:
  - skill: superpowers:test-driven-development
    when: execute
    mode: mandatory
    include_paths:
      - packages/convex/convex/aiScoring*.ts
    # exclude_paths optional — escape hatch from include_paths
  - skill: superpowers:test-driven-development
    when: execute
    mode: advisory
    # no include_paths → catch-all for everything else
```

**Runtime behavior:** Resolved at REFRESH per `{skill, when}` group. EXECUTE intersects changed-files-since-WORK with each entry's `include_paths` (omitted = catch-all), applies `exclude_paths`, picks first match per group. Different `{skill, when}` groups are independent — matching one does not suppress another. Backwards-compat: omitted `include_paths` keeps prior global-scope behavior. Warning emitted at REFRESH when `mode: mandatory` has no `include_paths`. Schema reference: `templates/project-config.md` § Cross-cutting disciplines.

**Section M — Code review backends (since v1.15.0).**

> Explainer: dev-loop's REVIEW step always invokes the `simplify:simplify` skill as the base code reviewer for code changes, preferably through the `dev-loop:simplify-worker` subagent adapter when worker dispatch is available. This is a required skill pass over the current diff, not an informal manual scan. Optionally, a second reviewer can run in parallel — `codex:codex-rescue` via the `dev-loop:codex-review-worker` wrapper — to provide an independent out-of-distribution second opinion. Two reviewers, two independent reads, no auto-reconciliation. Opt-in per intensity (normal / high) to avoid cost surprises.

Detect: probe whether the Codex **runtime** is usable via the companion's
own self-check (not a file-existence guess).

1. Glob `~/.claude/plugins/cache/*/codex/*/scripts/codex-companion.mjs` to
   locate the companion script. If zero matches, treat as not-installed
   and skip Section M with the install hint below.
2. Run `node <companion-path> setup --json`. Parse the JSON. If the
   command fails (non-zero exit, missing `node`, permissions error,
   etc.), treat as not-installed per step 5 below — do not crash the
   setup flow.
3. Treat as **Codex-available** iff `ready === true` AND
   `codex.available === true`.
4. If `ready === false` AND `auth.loggedIn === false`, surface the
   auth-specific hint instead of the generic install hint: "Codex
   installed but not authenticated — run `codex login` then re-run
   `/setup-dev-loop`."
5. Any other failure (JSON parse error, missing fields, non-zero exit) →
   treat as not-installed and skip Section M.

Why runtime probe: filesystem checks for `agents/codex-rescue.md` give
false negatives when the agent file isn't cached locally even though
`codex-cli` is installed and authenticated. The companion's
`setup --json` output is the authoritative signal — same classification
the Codex runtime uses when accepting code-review work.

The doctor-worker filesystem probe (Section 1 Explore / REFRESH step 7)
still drives `DEP_DRIFT` for generic dependency health. Section M uses
the runtime probe because it answers a stricter question ("is the
runtime usable?") than doctor-worker's generic question ("is the agent
file present?"). Do not reuse doctor-worker's filesystem result here.

If Codex is NOT installed (no companion script found) → skip this
section with install hint: "Install the Codex plugin to enable Codex
code review: `/plugin add openai-codex` (or check the marketplace for
the current install path). For now, dev-loop will run `simplify:simplify`
through `dev-loop:simplify-worker` when worker dispatch is available, or inline
when it is not."

If Codex IS installed → present 2 toggles:

> "Enable Codex code review for **normal**-intensity cycles? Each REVIEW step will run `simplify:simplify`, preferably via simplify-worker when subagents are available, and when enabled also spawn codex-review-worker. Adds latency + Codex cost; useful for catching issues the simplify pass misses (logic errors, security, OOD code paths). Default: no."

> "Enable Codex code review for **high**-intensity cycles (`/dev-loop high`)? High mode already raises aggressiveness; enabling here turns 'aggressive' into 'two independent reviewers per cycle.' Default: no."

Default posture: propose no/no even when Codex is installed — opt-in is the safe default; the user can toggle freely later by editing config. If the user accepts both, surface a one-line cost reminder.

**Config emitted:**

```yaml
code_review:
  parallel: true
  codex:
    enabled_in_normal: false   # or true if user opted in
    enabled_in_high: false     # or true if user opted in
    agent: dev-loop:codex-review-worker
```

**Runtime behavior:** Loaded at REFRESH into `CODE_REVIEW_BACKENDS` session list. Always includes `simplify:simplify` as the required base skill invocation for code changes; dev-loop should prefer `dev-loop:simplify-worker` for subagent isolation and fall back to inline `Skill("simplify:simplify")` when worker dispatch is unavailable. Appends `dev-loop:codex-review-worker` when (a) current intensity's `enabled_in_*` flag is true AND (b) neither `dev-loop:codex-review-worker` nor `codex:codex-rescue` is in `DEP_DRIFT`. REVIEW step 6 runs the simplify pass first, then spawns optional worker backends with `model: "sonnet"` when enabled. Findings are concatenated under per-backend section headers. No auto-reconciliation. Schema reference: `templates/project-config.md` § Code review.

**Section N — Release policy (since v1.19.0).** Controls whether step
10 PUSH auto-bumps version on shippable commits. Optional; omit the
block to preserve pre-1.19.0 manual-bump behavior.

Present this section only if `publish_via` was set to a non-`none`
value earlier in setup. If `publish_via: none`, skip Section N (no
PUSH happens regardless).

Ask the user, in order:

> "Do you want dev-loop to auto-bump version on shippable commits? (yes/no, default: no)"

If `no` → skip the rest of Section N; omit `release_policy` from the
generated config.

If `yes`:

> "Which channel — `beta` (pre-release tags like `v1.2.3-beta.4`) or `stable` (`v1.2.3`)? Default: stable."

> "Which file globs indicate a shippable commit? (comma-separated fnmatch patterns relative to repo root)"
> Suggest defaults derived from detected layout:
> - If `cli_src` matches `packages/*/src/...`, suggest `packages/cli/**`.
> - If `skills_glob` is set, suggest `packages/skills/**` (or the
>   detected glob's parent directory).
> - Always include `.claude-plugin/marketplace.json` and the
>   `bump_script` path if set.

> "Which file globs indicate a noise-only commit to skip? (comma-separated; default shown)"
> Default: `raw/**, concepts/**, entities/**, queries/**, projects/**, _archive/**, *.md`
> The default skip list mirrors typical vault directories and standalone
> markdown commits.

> "Enable `verify_after_push` (ls-remote + gh run watch after tag push)? (yes/no, default: yes)"

`tag_format` is fixed at `v{version}` (the canonical SemVer tag format).
If a project needs a different tag format, ask the user to set
`release_policy.tag_format` manually in the generated config — setup
does not expose this field interactively.

**Config emitted:**

```yaml
release_policy:
  auto_bump: true
  channel: <beta|stable>
  trigger_globs:
    - "<pattern>"
    # ...
  skip_globs:
    - "<pattern>"
    # ...
  tag_format: "v{version}"
  verify_after_push: <true|false>
```

**Runtime behavior:** Loaded at REFRESH into `RELEASE_POLICY` session
variable. PUSH step (10) checks changed files since last tag against
`trigger_globs`/`skip_globs` and gates whether to invoke `bump_script`.
When the block is absent, `RELEASE_POLICY = None` and PUSH preserves
pre-1.19.0 behavior. Schema reference: `templates/project-config.md`
§ Release policy.

### 3. Confirm and write

Show the user a draft of `./.claude/dev-loop.config.md` covering all thirteen sections (PRD, knowledge, release, interview, glossary, CI setup, critical paths, fact-check tier, idle deep-research, browser verification, reactive debugging, discipline path scoping, release policy). Let them edit before writing.

### 4. Write

Write `./.claude/dev-loop.config.md` using the filled-in template from `templates/project-config.md`.

If vault is available, run `skillwiki:proj-init` with the project slug.

### 5. Done

Tell the user:
- Config written to `./.claude/dev-loop.config.md`
- Domain docs in `docs/agents/` (and `CONTEXT.md` if grill-with-docs ran)
- Next: run a dev-loop cycle — the engine will pick up the new config automatically
- To change config later, edit `./.claude/dev-loop.config.md` directly
- If Section F was completed: CI workflow written to `.github/workflows/ci.yml`, `ci_configured: true` in config
- If Section F was skipped: set `ci_configured: false` — dev-loop MERGE step will warn about missing CI
- If Section G was completed: `critical_paths:` block in config with 1-3 named hot-spots
- If Section G was skipped: `critical_paths: {}` (empty, engine uses equal priority)
- If Section H was completed: `fact_check:` block with source order, web tools, and evidence contract
- If Section H was skipped: no `fact_check` section — agents use local context only
- If Section I was completed: `idle_deep_research:` block with topic seeds, cooldown, budget
- If Section I was skipped: no `idle_deep_research` section — idle cycles exit after maintenance
- If Section J was completed: `browser_verification:` block with trigger globs, dev server, smoke routes
- If Section J was skipped: no `browser_verification` section — no browser gate before merge
- If Section K was completed: `reactive_debugging:` block with retry budget, evidence capture, escalation
- If Section K was skipped: no `reactive_debugging` section — legacy unbounded retry behavior
- If Section L was completed: `include_paths`/`exclude_paths` on scoped disciplines, first-match-wins resolution
- If Section L was skipped: no path scoping — disciplines apply globally (current behavior)
