---
name: codebase-architecture-analyze
description: Use when analyzing or explaining codebase architecture, extracting C4 diagrams, ADRs, tech debt, module/seam-cluster specs, reimplementation blueprints, topology maps, or when the user asks to document, reverse-engineer, or produce reimplementation-grade architecture docs for a repo.
metadata:
  upstream:
    - "https://github.com/mattpocock/skills (design vocabulary lineage)"
    - "FindSkill codebase-architecture-explainer (analysis phases)"
    - "https://github.com/lmammino/c4-codebase-architecture-skill (evidence vs inference patterns)"
  upstream_license: MIT where applicable
---

# Codebase Architecture Analyze & Extract

Transform an opaque codebase into durable architecture documentation. This is the **analysis / extract** half of the reimplementation playbook (see [playbook-chain.md](../../references/playbook-chain.md) and vault `comparisons/codebase-analysis-reimplementation-skills.md`).

## Mandatory skill load

Before writing durable extracts, **invoke skill `codebase-design`** (load glossary + principles). Use its terms exactly — module, interface, depth, seam, adapter, leverage, locality — in every extract.

**C4 vs design vocabulary:** C4 *Component* is a diagram level only. Extract files and design prose use **module** / **seam cluster**. See [c4-evidence.md](../../references/c4-evidence.md).

## Output routing (mandatory)

Before writing files, resolve the extract root per [output-routing.md](../../references/output-routing.md):

1. Explicit `--save` / path from user
2. Else if SkillWiki vault **and** `projects/{slug}/` exists (slug algorithm in output-routing) → **`{WIKI}/projects/{slug}/architecture/`**
3. Else → **`{TARGET_REPO}/docs/architecture/`**
4. `--ephemeral` → terminal only

Announce the resolved output root to the user before bulk writes.

Pin source commit/tag in every file header. Plugin version: read `.claude-plugin/plugin.json` → `version` (see output-routing). Prefer numbered extract set:

| File | Content |
|------|---------|
| `00-reimplementation-blueprint.md` | E2E flow + milestone plan + verify commands |
| `01-topology.md` | Tree, stack, entry points, deps, **scope**, observed vs inferred; short C4 overview may live here |
| `02-module-{name}.md`, `03-module-{name}.md`, … | Sequential major module / seam cluster specs (start at `02`) |
| `04-adrs.md` or `adrs/ADR-*.md` | Optional when ADR register is large; else ADRs section in `01`/`00` |
| `05-tech-debt.md` | Optional when debt register is large |
| `08-*.md` / `09-*.md` | Optional layer inventories |

## Workflow

### Phase 0 — Target, scope & pin

1. Identify target repo (cwd or user path).
2. Record: remote, `git describe --tags --always`, short SHA, package/UI versions if they differ.
3. State **scope** (repo-only / monorepo slice / service-in-platform / partial). See [c4-evidence.md](../../references/c4-evidence.md).
4. Resolve output root (above). Announce path before bulk writes.
5. Optional pack: repomix / code2prompt when the tree is large.

### Phase 1 — Reconnaissance

1. Stack: language, frameworks, build, storage, external integrations.
2. Directory tree and roles.
3. Entry points: main app, routers, workers, CLI, schedulers.
4. Config: manifests, env templates, CI, compose/IaC.

Write `01-topology.md` early. Separate **Observed** vs **Inferred** bullets.

### Phase 2 — Structural analysis

For each major **module** (design vocabulary):

- Purpose, location, public **interface**, dependencies, dependents, key files
- Dependency graph (Mermaid); flag cycles and layer leaks
- Data flows: request path, events, background jobs (sequence diagrams)

### Phase 3 — Pattern recognition

Document structural patterns (layered, hexagonal, event-driven, …), design patterns in use, data patterns (repository, CQRS, …). Note deviations from textbook form with file evidence.

### Phase 4 — C4 + decisions + debt

- C4: Context → Container → Component (Code sparingly). Label diagram levels as C4; map internals to **modules**. Prefer embedding a short C4 overview in `01-topology.md`; use a separate file only if large.
- ADRs for load-bearing decisions found in code (status: Discovered | Active | …) → `04-adrs.md` / `adrs/` or a section in `00`/`01`.
- Tech debt register: code / architecture / dependency / docs / infra → `05-tech-debt.md` or a section in `00`/`01`.

### Phase 5 — Reimplementation extract (when goal is rebuild or full playbook)

Produce:

1. Architecture overview + NFR
2. **Module / seam-cluster specs**: interface contracts, state, errors, config, deps
3. Data model / schema notes
4. Integration points (HTTP/gRPC/events, auth, quotas)
5. Testing strategy at highest stable **seams**
6. `00-reimplementation-blueprint.md` with bottom-up milestones and verify commands

### Phase 6 — Closeout

1. Link extracts with relative paths or wikilinks (wiki mode).
2. Ensure topology or blueprint includes **Open questions** and **Assumptions and inferences**.
3. If wiki project: run `skillwiki project-index --project {slug} --apply` when available.
4. Report: output root, file list, source pin, known gaps vs HEAD, suggested next skill (`improve-codebase-architecture` / `architecture-to-spec` / external migrate).

## Interactive vs batch

- **Default (full extract):** run phases 1–5 without waiting when user asked to analyze/extract/document.
- **Exploratory:** after Phase 1, summarize and ask which areas to deepen before Phase 2–5.
- Ask only high-value questions when code cannot answer (see [c4-evidence.md](../../references/c4-evidence.md)).

## Alignment with related skills

| Need | Skill |
|------|--------|
| Deep-module language | `codebase-design` (load first) |
| Find shallow clusters to refactor | `improve-codebase-architecture` |
| Turn analysis into PRD | `architecture-to-spec` |
| Batched multi-file rewrite | external `codebase-migrate` (not bundled) |
| External GitHub / freshness evidence | `deep-research` / PavedPath |
| Full chain chooser | `codebase-architecture` router |

## Guardrails

- Evidence over assertion: every structural claim cites paths or symbols; mark inferences.
- Don't invent a wiki project; fall back to `docs/architecture/`.
- Don't put improve-architecture HTML into wiki/docs (temp only).
- Prefer repo-relative paths in durable docs.
- Redact secrets from extracts.
