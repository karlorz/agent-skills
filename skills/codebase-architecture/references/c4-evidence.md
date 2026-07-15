# C4 Evidence Discipline (analyze)

Use with `codebase-architecture-analyze`. Adapted from evidence-first C4 reverse-engineering practice (e.g. lmammino/c4-codebase-architecture-skill patterns). Complements deep-module vocabulary in `codebase-design`.

## C4 levels vs design vocabulary

| Term | Meaning here |
|------|----------------|
| C4 **Context / Container / Component** | Diagram taxonomy (who talks to what, deployable units, internal structure of a container) |
| Design **module / interface / seam** | Deep-module design language for leverage, testability, and AI-navigability |

Never rename design modules to "components" in extract filenames or implementation decisions. A C4 Component view may describe several **modules**.

## Epistemology

### Observed vs inferred

Label claims explicitly:

- **Observed** — backed by a path, symbol, manifest, route, IaC resource, or test. Cite it.
- **Inferred** — reasonable but not proven in-repo. Mark as inference; do not present as fact.
- **Unknown** — open question for the user or a follow-up scan.

Do not present guesses as facts.

### Scope statement (every extract set)

State which of these the analysis covers:

- This repository only
- One service inside a larger platform
- A monorepo slice / package
- Partial implementation of a broader architecture

A repository is not always the whole system.

## High-value questions only

When code is insufficient, ask concise batches (scope, actors, deployment topology, ambiguous external deps). Prefer discoverable-in-code answers over interrogation.

## Shape heuristics (optional)

| Shape | Prefer |
|-------|--------|
| Monolith | One container; component/module views on high-churn packages |
| FE+BE monorepo | Separate containers per deployable; shared libs as modules |
| Serverless | Functions/queues/stores as containers; careful with "boundary" overload — use seam for design |
| Microservices | Context + multi-container; avoid inventing services not in code/IaC |
| Library / SDK | Emphasize public interface and adapters; skip full system Context if N/A |

## Suggested closeout sections

Every full extract (or topology + blueprint pair) should include:

1. **Scope**
2. **Observations** (path-cited)
3. **Assumptions and inferences**
4. **Open questions**
5. **Suggested next refinements** (optional improve / to-spec / migrate)

## Output formats

Default: Markdown + Mermaid. PlantUML / Structurizr only when the user asks or the repo already uses them.
