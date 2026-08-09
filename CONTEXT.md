# agent-skills — dev-loop domain context

Domain language for the dev-loop orchestration engine, including adaptive workflow policy and interactive interview capabilities. Dev-loop coordinates the development cycle; installed skills and SkillWiki provide capabilities behind explicit interfaces without becoming a second orchestration engine.

## Workflow Profile Language

**Workflow discipline**:
An independently selectable development practice or gate, such as brainstorming, specification, planning, TDD, worktree isolation, implementation review, or simplification. A discipline is not a complete workflow profile by itself.

**Workflow profile**:
The resolved policy for how much procedural development structure applies to one dev-loop run. A profile selects or permits workflow disciplines; it does not implement them. The three profiles are `native`, `guided`, and `full`.

**Native profile** (`native`):
Uses the model and harness's native development behavior without imposing a bundled external workflow. Repository instructions, verification requirements, SkillWiki invariants, and independent required gates still apply. The agent may use an available discipline when the task itself requires it, but installation alone never preloads or mandates a complete pipeline.

**Guided profile** (`guided`):
Loads only the workflow disciplines justified by task risk, ambiguity, or recorded capability evidence. It may require targeted planning, TDD, worktree isolation, or review without imposing the complete Superpowers-style sequence. This is the normal scaffolding profile for lite models and higher-risk work performed by otherwise self-directed models.

**Full profile** (`full`):
Applies the complete configured structured workflow, currently represented by the Superpowers-style planning and execution pipeline. `full` is explicit-only. Skill installation or unrestricted automatic discovery cannot activate it. A current user instruction, work-item declaration, project policy, user policy, or legacy `prd_pipeline: full` compatibility signal (when newer workflow keys are absent) must explicitly select it.

**Profile selection mode**:
The policy determining how a workflow profile is chosen. `fixed` selects a recorded profile. `adaptive` resolves only to `native` or `guided` from task and capability evidence; it never resolves to `full`. `adaptive` is a selection mode, not a fourth workflow profile.

**Workflow Profile Resolver**:
The implemented pure module that applies selection authority and returns one resolved workflow profile or an explicit unresolved result. It owns profile selection only. Planning, execution, dispatch, vault mutation, and harness-specific instruction loading remain implementations behind other interfaces or adapters.

**Availability evidence**:
Proof that a workflow skill, command, or harness operation can be invoked. Installation and discovery produce availability evidence only; they never select a workflow profile.

**Capability evidence**:
A configured or harness-provided signal about how much workflow support a run may need. Model product names are not durable architecture and must not be the sole source of capability evidence. Unknown evidence can justify `guided` for risky work but can never justify implicit `full` activation.

**Activation depth**:
How much procedural instruction is loaded into a harness. Activation depth is an output concern of harness adapters, not a synonym for workflow profile. All activation depths retain mandatory SkillWiki authority, managed-write, provenance, and vault-placement rules.

**Selection authority**:
The precedence used by the Workflow Profile Resolver: current user instruction, work-item declaration, project configuration, user-level default, then the built-in adaptive default. A higher-precedence explicit choice cannot be overridden by model or task heuristics.

**Noninteractive profile resolution**:
Goal, headless, CI, and satellite sessions never prompt for a workflow profile. They consume recorded policy and deterministic evidence. When required policy is missing or invalid, the caller follows its recorded fail-or-skip policy instead of silently assuming `full`.

### Workflow Profile Invariants

- Installation proves availability, never activation.
- `full` is explicit-only.
- Adaptive selection chooses only `native` or `guided`; it never chooses `full`.
- Explicit policy outranks all heuristics.
- Invalid configuration resolves as unresolved, not `full`.
- Session-kind resolution is an input, not duplicated profile logic.
- Harness-specific loading remains in harness adapters.
- `simplify:simplify` remains an independent required review gate.
- SkillWiki Markdown/YAML and deterministic CLI operations remain authoritative for knowledge and managed vault mutation.

## Current Dev-Loop Maintenance Notes

- SkillWiki config should be portable by default: use `knowledge_backends.skillwiki.vault: auto` and resolve the actual vault root with `skillwiki path`.
- Durable docs should refer to project wiki locations as vault-relative paths such as `projects/agent-skills`, not `/Users/.../wiki/projects/agent-skills`.
- Do not add `memory_layer`, `interview.work_item.default`, or `interview.work_item.source` to generated dev-loop configs unless the engine grows explicit parser support for those fields.
- The 2026-06-15 OpenHanako closeout produced three dev-loop follow-ups now tracked in the agent-skills wiki: dirty critical-path code can be invisible when related work items are completed, worker `Agent(...)` spawn failure needs inline fallback, and Codex packages must include skill-relative reference docs such as `skills/dev-loop/references/codex-tools.md`.

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

- **Workflow Profile Resolver** consumes selection authority, session kind, task evidence, capability evidence, and availability evidence; it emits a resolved profile or unresolved result
- **Native profile** trusts model/harness-native development behavior while preserving repository and knowledge invariants
- **Guided profile** selects targeted workflow disciplines without imposing a complete pipeline
- **Full profile** applies the configured complete pipeline and requires explicit authorization
- **Profile selection mode** determines whether the resolver uses a fixed profile or bounded adaptive selection
- **Activation depth** is emitted through harness adapters after profile resolution; it does not select the profile
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

- "Installed workflow" previously conflated availability with activation — resolved: installation produces **availability evidence** only; the **Workflow Profile Resolver** owns activation policy.
- "Adaptive profile" previously risked becoming a fourth profile — resolved: **adaptive** is a **profile selection mode** that chooses only `native` or `guided`.
- "Full" previously behaved like an installation-derived default — resolved: the **full profile** is explicit-only and cannot be inferred from installation.
- "Frontier model" and "lite model" are useful product discussion labels but unstable architecture terms — resolved: selection consumes configured or harness-provided **capability evidence**, never a product name alone.
- "Activation depth" and "workflow profile" were used interchangeably — resolved: profile is policy; activation depth is harness-specific instruction loading after resolution.
- "grill" was used to mean both the setup interview and the work-item interview — resolved: these are `setup_interview` and `work_item_interview`, two distinct capabilities.
- "simplified version of grill-me" was initially ambiguous between copying, forking, or building native — resolved: native interview is a dev-loop-built minimal AskUserQuestion routine, not a fork.
