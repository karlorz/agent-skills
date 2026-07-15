---
name: improve-codebase-architecture
description: Use when scanning a codebase for deepening opportunities, shallow modules, architectural friction, testability or AI-navigability refactors, or when the user wants an architecture review HTML report before redesigning a module.
disable-model-invocation: true
metadata:
  upstream: https://github.com/mattpocock/skills/tree/main/skills/engineering/improve-codebase-architecture
  upstream_license: MIT
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** — refactors that turn shallow modules into deep ones. Aim: testability and AI-navigability.

## Mandatory skill load

Before suggestions, **invoke skill `codebase-design`** (glossary + principles: deletion test, interface is the test surface, one adapter = hypothetical seam). Use those terms exactly — do not drift into "component," "service," "API," or "boundary."

Domain language: project `CONTEXT.md` when present. ADRs under `docs/adr/` (or wiki architecture ADRs) are decisions not to re-litigate lightly.

## Process

### 1. Explore

**Scope before scanning — YAGNI.** Deepening pays off where future change is likely. Decide *where* to look first:

1. If the user named a module, subsystem, or pain point — use that scope and skip hot-spot inference.
2. Otherwise walk recent history (`git log --oneline` over a useful stretch) for hot spots — files/areas that keep changing — and prefer those paths.
3. If changes are scattered with no clear hot spot, widen the net.

Read domain glossary and relevant ADRs in the scoped area first.

Walk the codebase (Explore subagent when available; e.g. `subagent_type=Explore`). Note friction organically:

- Understanding one concept requires many small modules
- Modules **shallow** — interface ≈ implementation
- Pure functions extracted for tests while bugs live in call wiring (no **locality**)
- Leaks across seams
- Untested or hard-to-test through current interface

Apply the **deletion test** to suspected shallow modules: would deleting it concentrate complexity, or only move it?

### 2. HTML report (temp only)

Write self-contained HTML to OS temp — **not** wiki, **not** `docs/`. See [html-report.md](../../references/html-report.md).

Path: `{TMPDIR}/architecture-review-{timestamp}.html`. Open it; tell the user the absolute path.

**Offline / no-CDN:** if the environment blocks CDN scripts, or the user asks for offline output, write Markdown to `{TMPDIR}/architecture-review-{timestamp}.md` with the same candidate cards and Mermaid fences instead of HTML. Prefer HTML when the browser path works.

Each candidate card:

- Files, Problem, Solution, **Wins** (locality / leverage / tests; ≤6 words each)
- Before/After diagram
- Strength badge: `Strong` | `Worth exploring` | `Speculative`
- Dependency category from [deepening.md](../../references/deepening.md)

Use CONTEXT.md domain names on cards (e.g. "Order intake module", not only handler class names).

Top recommendation section at end.

ADR conflicts: only surface when friction warrants reopening; mark clearly.

**Do not propose full interfaces yet.** Ask: "Which of these would you like to explore?"

### 3. Grilling loop

When the user picks a candidate:

1. Prefer skill `grill-me` / `grilling` if available — design tree, constraints, tests that survive.
2. Keep domain glossary current (`CONTEXT.md` or wiki concept terms).
3. Rejected with a load-bearing reason → offer ADR so future reviews don't re-suggest.
4. Alternative interfaces → [design-it-twice.md](../../references/design-it-twice.md) (requires `codebase-design` vocabulary).

Durable decisions from the grill may be written as markdown ADRs using [output-routing.md](../../references/output-routing.md) (wiki architecture or `docs/architecture/`), not as HTML.

## Chain position

Optional branch of the playbook: analyze extracts first if docs are missing, then improve, then `architecture-to-spec` for the chosen deepen. See [playbook-chain.md](../../references/playbook-chain.md).
