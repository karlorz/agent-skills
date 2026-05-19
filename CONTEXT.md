# agent-skills — dev-loop interview integration

Extending the dev-loop orchestration engine with interactive interview capabilities — a setup bootstrap and per-work-item grilling phase — with pluggable backends that default to native (zero-dependency) and optionally upgrade to external interview skills.

## Language

**Interview phase**:
A dev-loop step where the agent asks the user clarifying questions before proceeding. Two variants: setup interview (once per project) and work-item interview (per SPEC step, conditional on ambiguity).

**Setup interview** (`setup_interview` capability):
Runs once per project. Bootstraps `dev-loop.config.md`, `docs/agents/`, and delegates domain glossary building to an interview backend. Provided by the bundled `/setup-dev-loop` skill.

**Work-item interview** (`work_item_interview` capability):
Runs before the SPEC step when ambiguity is detected or the user forces it. Sharpens scope, constraints, and acceptance criteria. Defaults to the native three-question interview; upgrades to `grill-with-docs` when installed.

**Native interview**:
The built-in minimal interview — three fixed `AskUserQuestion` calls (scope, constraints, acceptance criteria). Always available, zero dependencies. The fallback when no external interview backend is installed.

**Ambiguity detection**:
The heuristic dev-loop uses to decide whether a work item needs grilling. Hybrid approach: user can force with `grill: true | false` in the work item; if unset, a pre-spec scan checks for conflicting prior decisions, zero prior art, or vague language.

**Interview backend**:
A pluggable implementation that satisfies the interview capability contract. Two types: `native` (bundled, zero-dependency) and `external` (installed from a source like `mattpocock/skills`). Declared in the `interview` top-level config section.

**Config-based registry**:
The `interview` config block that maps capability names to skill names, sources, and install hints. Enables dev-loop to invoke external skills by name and tell the user how to install them if missing.

**Grill handoff**:
The interleaved delegation from `/setup-dev-loop` to an interview backend (e.g., `grill-with-docs`) for the domain glossary section. The user experiences one seamless interview; `/setup-dev-loop` owns the flow.

## Relationships

- **Setup interview** produces `dev-loop.config.md`, `docs/agents/`, and optionally `CONTEXT.md` (via delegated interview backend)
- **Work-item interview** produces a sharpened requirements summary that feeds into `spec.md`
- **Native interview** is the default work-item interview backend; **grill-with-docs** is the optional upgrade
- **Ambiguity detection** gates whether the work-item interview fires; `grill: true` forces it, `grill: false` suppresses it
- **Interview backends** are declared in the `interview` config section, separate from `knowledge_backends`

## Example dialogue

> **Dev:** "When dev-loop hits the SPEC step for a new feature, does it always grill?"
> **Architect:** "No — it runs ambiguity detection first. If the work item has `grill: true` or the pre-spec scan finds conflicting prior decisions or no prior art, it invokes the work-item interview. If it's a bug fix with clear context, it skips straight to inline SPEC."
> **Dev:** "And if grill-with-docs isn't installed?"
> **Architect:** "Falls back to the native interview — three questions: scope, constraints, acceptance criteria. No external dependency needed."

## Flagged ambiguities

- "grill" was used to mean both the setup interview and the work-item interview — resolved: these are `setup_interview` and `work_item_interview`, two distinct capabilities.
- "simplified version of grill-me" was initially ambiguous between copying, forking, or building native — resolved: native interview is a dev-loop-built minimal AskUserQuestion routine, not a fork.
