---
name: setup-dev-loop
description: Scaffold per-repo dev-loop config (PRD layer, knowledge layer, release config, vault path) and build the project glossary with grill-with-docs. Run once per repo before using dev-loop.
disable-model-invocation: true
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

### 3. Confirm and write

Show the user a draft of `./.claude/dev-loop.config.md` covering all six sections (PRD, knowledge, release, interview, glossary, CI setup). Let them edit before writing.

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
