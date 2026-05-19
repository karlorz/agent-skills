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

### 3. Confirm and write

Show the user a draft of `./.claude/dev-loop.config.md` and `docs/agents/domain.md`. Let them edit before writing.

### 4. Write

Write `./.claude/dev-loop.config.md` using the filled-in template from `templates/project-config.md`.

If vault is available, run `skillwiki:proj-init` with the project slug.

### 5. Done

Tell the user:
- Config written to `./.claude/dev-loop.config.md`
- Domain docs in `docs/agents/` (and `CONTEXT.md` if grill-with-docs ran)
- Next: run a dev-loop cycle — the engine will pick up the new config automatically
- To change config later, edit `./.claude/dev-loop.config.md` directly
