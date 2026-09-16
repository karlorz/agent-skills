---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
metadata:
  upstream: https://github.com/mattpocock/skills/tree/959a8e9f1edc3adbe2f7e3054bb6fbefa6696260/skills/engineering/grill-with-docs
  upstream_commit: 959a8e9f1edc3adbe2f7e3054bb6fbefa6696260
  upstream_license: MIT
  provenance: semantic-adaptation
---

# Grill with Docs

Compose two separately maintained capabilities in one attended main session:

1. Load and follow `grill-me:grilling` as the interview engine.
2. Load and apply `domain-modeling:domain-modeling` continuously while the interview runs.

Do not delegate the interview or any design decision. Factual scouts may inspect files, code, tools, and environment prerequisites, but the attended main session owns every question, recommendation, and user decision.

If either dependency is unavailable, stop before the interview and report the missing package with these installation commands:

```text
codex plugin add grill-me@karlorz-agent-skills
codex plugin add domain-modeling@karlorz-agent-skills
claude plugin install grill-me@karlorz-agent-skills
claude plugin install domain-modeling@karlorz-agent-skills
```

During the interview:

- Work through the grilling design-tree frontier one question at a time.
- Challenge fuzzy or conflicting terminology as soon as it appears.
- Capture a resolved glossary term immediately using the active local or SkillWiki storage mode.
- Offer an ADR only when the decision is hard to reverse, surprising without context, and the result of a real trade-off.
- Keep `CONTEXT.md` glossary-only; do not turn it into a specification or implementation log.

When the frontier is empty and the user confirms shared understanding, return this caller-facing result:

```markdown
## Requirements and decisions summary

- Scope:
- Constraints:
- Acceptance criteria:
- Canonical terms resolved:
- Decisions recorded:
- Open questions: none | <items>
```

The caller incorporates that summary into its active specification path. In SkillWiki projects, use only managed work-item and decision workflows; never mutate the vault directly.

Under `/goal`, `codex exec`, CI, scheduled runs, or other unattended contexts, do not begin the interview. Report that `grill-with-docs` requires an attended main session.
