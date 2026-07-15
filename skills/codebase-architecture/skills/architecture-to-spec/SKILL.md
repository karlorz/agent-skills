---
name: architecture-to-spec
description: Use when turning architecture analysis or the current design conversation into a reimplementation or feature PRD/spec without interviewing the user, or when chaining after codebase-architecture-analyze / improve-codebase-architecture.
disable-model-invocation: true
metadata:
  upstream: https://github.com/mattpocock/skills/tree/main/skills/engineering/to-spec
  upstream_license: MIT
---

# Architecture to Spec

Synthesize the current conversation and codebase understanding into a **spec (PRD)**. Do **not** interview — only use what is already known (plus quick code reads to fill gaps).

This is the **spec** step of the reimplementation playbook after analyze/extract (and optional improve). See [playbook-chain.md](../../references/playbook-chain.md).

## Mandatory skill load

**Invoke skill `codebase-design`** before writing the spec. Use design vocabulary and the project domain glossary throughout.

## Process

1. If architecture extracts exist (wiki `projects/{slug}/architecture/` or `{repo}/docs/architecture/`), read them first.
2. Sketch **test seams** — prefer existing highest seams; propose new seams only at the highest useful point. Fewer seams is better (ideal: one primary seam per feature). Confirm seams with the user before publishing.
3. Write the spec with the template below.
4. **Resolve publish path** per [output-routing.md](../../references/output-routing.md) (spec section). **Announce the path to the user before writing.**
   1. Explicit path from user
   2. Else if slug algorithm finds an **existing** wiki project: `projects/{slug}/work/YYYY-MM-DD-{topic}/spec.md` (create `work/` + dated folder under that project as needed)
   3. Else if issue tracker is clearly configured in this session **and** project convention exists: create issue + ready-for-agent-style label — **optional third choice only**
   4. Else: `{TARGET_REPO}/docs/architecture/spec-{repo_basename}.md` (`{repo_basename}` = remote basename or directory basename; always defined)

Issue trackers are never required. Prefer wiki work items in SkillWiki fleets; docs fallback is always valid.

## Spec template

```markdown
## Problem Statement

The problem from the user's perspective.

## Solution

The solution from the user's perspective.

## User Stories

Long numbered list:

1. As an <actor>, I want a <feature>, so that <benefit>

## Implementation Decisions

- Modules to build/modify (design vocabulary: module, interface, seam)
- Interface changes (invariants, errors — not ephemeral file paths)
- Architectural decisions, schema, external contracts
- Do NOT include specific file paths or large code dumps
- Exception: prototype snippets that encode a decision (state machine, schema) — trim to decision-rich parts

## Testing Decisions

- Good tests assert external behaviour through seams, not implementation details
- Which modules / seams are tested
- Prior art in the codebase

## Out of Scope

...

## Further Notes

...
```

## After publish

Point to next execution skill: external `codebase-migrate` (or repo migrate workflow) for multi-file transforms; normal implementation skills for small features. Migrate is **not** bundled in this plugin.
