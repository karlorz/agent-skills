---
name: office-hours
description: >
  Use when running an attended dev-loop office-hours checkpoint before prep,
  promotion, or /goal to choose one current-project topic and capture requirements.
---

# Dev-Loop Office Hours

Attended requirements intake for one current-project topic. Office-hours runs
before `/dev-loop prep`, promotion to planned work, or `/goal`. It refreshes
project brain context unattended, lists current-project candidates, asks concrete
requirement questions one at a time, writes a vault-native report, and stops
with a recommended next action.

Office-hours is not `/dev-loop prep`. Prep approves automation readiness for
known work. Office-hours helps the user decide what one thing needs clearer
requirements before prep or execution.

## Hard Rules

1. Run in the main session only. Do NOT spawn subagents for intake,
   candidate selection, or approval.
2. Handle exactly one topic, capture, or work item per invocation.
3. Brain and memory refresh is fully unattended. Do not ask the user to choose
   memory pages, wiki layers, or project-index refresh strategy.
4. Do NOT auto-select a no-topic candidate. List current-project candidates
   first, then ask the user which one to focus.
5. Do NOT modify raw transcripts. Raw files are immutable in v1.
6. Do NOT auto-create planned work.
7. Do NOT set preflight readiness fields such as `automation_ready`,
   `human_questions_resolved`, `spec_preflight_approved`,
   `plan_preflight_approved`, `preflight_state`, or `last_preflight`.
8. Do NOT start or manage `/goal`.
9. Do NOT call structured question tools from subagents.
10. Always write an office-hours report when the session reaches a selected
    topic, even if the decision is defer or research more.

## Non-Interactive Guard

Office-hours is attended. Before prompting, detect whether the session is
interactive:

- Active `/goal` evaluator context or other unattended orchestrator
- `codex exec`, CI, cron, scheduled satellite, or no TTY-style user channel
- Subagent or nested worker context

If non-interactive, do not ask questions and do not write decisions. Emit a
short report to the transcript:

```text
Office-hours requires an attended main session. Run it before /goal or prep.
```

If the user supplied a topic, you may still perform read-only brain refresh and
print the candidate context, but stop before any prompt or write.

## Inputs

Supported invocations:

```text
/dev-loop:office-hours
/dev-loop:office-hours --all
/dev-loop:office-hours <topic>
/dev-loop:office-hours <work-item-slug>
/dev-loop:office-hours raw/transcripts/<file>.md
```

Use `--all` or the user's "show all" request to expand the candidate list from
the default bounded batch to full current-project scope. Keep the workflow
one-topic after the user selects a candidate.

## Refresh

Resolve the same project context that dev-loop uses:

1. Read `.claude/dev-loop.config.md` if present.
2. Resolve `<slug>` from config; fall back to the repo basename.
3. Resolve `<vault>` from the configured SkillWiki backend. If the vault is
   `auto` or absent, run `skillwiki path`; if that fails, use a validated
   `~/wiki` only when `~/wiki/SCHEMA.md` and `~/wiki/projects/` exist.
4. Resolve `<repo>` as the current working repository.
5. Resolve the skill directory so helper calls run relative to this skill root.

If a SkillWiki vault cannot be resolved, refuse v1 office-hours with:

```text
Office-hours v1 requires a SkillWiki vault so it can list project work and
write a requirements report.
```

### Brain Refresh

Run these read-mostly refresh steps without asking the user to choose:

```bash
skillwiki memory index --project <slug>
skillwiki memory topics --project <slug> --limit <n>
skillwiki project-index <slug>
```

Treat `skillwiki project-index <slug>` as an orientation/staleness read unless
the CLI requires an explicit apply flag for writes. Do not turn project-index
results into readiness approval.

Summarize the refresh compactly:

- Memory index: refreshed, already fresh, missing command, or failed
- Memory topics: top themes and recency notes
- Project index: fresh, stale, missing, or failed
- Any command failures that limit confidence

Do not ask the user what to do with memory failures. Report them and continue
with available context.

### Candidate Inventory

Run the existing deterministic preflight inventory helper from the dev-loop
skill directory:

```bash
node scripts/preflight-inventory.js \
  --project <slug> \
  --vault <vault> \
  --repo <cwd> \
  --limit <n>
```

Default `<n>` from `preflight.default_limit` when configured, otherwise `5`.
When the invocation includes `--all` or the user asks "show all", rerun with:

```bash
node scripts/preflight-inventory.js \
  --project <slug> \
  --vault <vault> \
  --repo <cwd> \
  --all
```

Present candidates grouped by the helper lanes:

- `work` - planned, in-progress, or repairable work items
- `captures` - unclaimed project raw transcript tasks or bugs
- `hygiene` - structural issues that need human attention

Keep the list project-scoped. Do not list every global wiki item unless it is
linked to the current project. If there are no candidates, present the brain
refresh topics and ask for one free-text focus topic.

## Select One Topic

Selection rules:

- If the invocation names a work item, raw transcript, or topic, treat it as
  the selected topic after refresh and still surface any closely related
  candidates for context.
- If no topic is supplied, ask the user to pick one candidate from the grouped
  list or provide a free-text topic.
- Never choose the top candidate automatically.
- Re-read the selected source immediately before asking requirement questions.
- If the selected source changed since inventory, state that it is stale and
  ask whether to continue read-only or rerun inventory.

Use a structured question for candidate choice when available because this is a
decision point. Put the recommended candidate first only when there is an
evidence-based recommendation; otherwise list in inventory order.

## Question Runner

Use structured question tools for decision-point questions:

| Platform | Structured question tool |
|---|---|
| Claude Code | `AskUserQuestion` |
| Codex CLI or Codex App | `ask_user_question` |
| Antigravity CLI | `ask_question` |
| None available | conversational fallback |

Decision-point examples:

- Choose one focus candidate.
- Continue read-only after stale inventory, or rerun inventory.
- Choose the final decision: promote to prep, defer, research more, direct
  dev-loop execution, merge with existing work, or discard.
- Confirm whether to update a managed `## Office Hours` section on a selected
  work-item spec.

Use conversational free text for nuanced requirements questions. Ask one
question at a time, wait for the answer, then decide the next question.

All questions must be asked in the main session only.

## Infer Intake Mode

Infer an internal mode from the selected source. Do not present
`product | builder | maintenance` as the primary user picker.

| Mode | Signals | Question focus |
|---|---|---|
| `product` | User-facing behavior, product requirement, UX, customer value | User, outcome, scope, acceptance |
| `builder` | Implementation plan, API, tests, architecture, developer workflow | Behavior delta, constraints, files, compatibility, verification |
| `maintenance` | Hygiene, stale work, broken schema, failed validation, cleanup | Symptom, invariant, risk, rollback, validation |

If confidence is low, ask one outcome-oriented clarification:

```text
What decision should this office-hours session unlock: product scope,
implementation direction, or maintenance triage?
```

Record the inferred mode and confidence in the report.

## Requirement Questions

Ask only enough questions to remove the next-action blocker. Prefer 2-5 good
questions over a long checklist.

### Product Mode

1. Who is affected, and what should be different after this ships?
2. What is explicitly out of scope for v1?
3. What acceptance signal proves this is done?
4. What risk would make you defer or split the work?

### Builder Mode

1. What behavior or interface should change?
2. Which existing files, conventions, or compatibility constraints must be
   respected?
3. What validation should be enough: tests, manual smoke, docs, release check,
   or another command?
4. Is there a simpler path that preserves the required behavior?

### Maintenance Mode

1. What symptom or stale state should disappear?
2. What must remain unchanged?
3. What is the safe rollback or no-op boundary?
4. Which command or vault validation should prove the cleanup is safe?

When the answer reveals that the selected topic is actually multiple topics,
choose one with the user and record the rest under remaining uncertainty.

## Decision

End with one recommended next action and the user's decision:

- `promote-to-prep` - run `/dev-loop prep` for this now-clear work.
- `direct-dev-loop` - scope is clear enough for a single attended or normal
  dev-loop cycle, without readiness approval.
- `research-more` - evidence is insufficient; use investigate or deep research.
- `merge-existing` - link to an existing work item instead of creating another.
- `defer` - keep the report as context, no immediate work.
- `discard` - no action.

Do not execute the next action automatically. Office-hours stops after the
report and recommendation.

## Report

Always write the report after a topic is selected:

```text
projects/<slug>/requirements/YYYY-MM-DD-office-hours-<topic>.md
```

Use the local date and a filesystem-safe `<topic>` slug. If the path exists,
append `-2`, `-3`, and so on.

Recommended frontmatter:

```yaml
---
title: "Dev Loop Office Hours - <Topic>"
project: "[[<slug>]]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
kind: decision
status: completed
---
```

Required sections:

```markdown
# Dev Loop Office Hours - <Topic>

## Context
## Brain Refresh Summary
## Inferred Intake Mode
## Questions And Answers
## Decision
## Recommended Next Action
## Links
```

The body must record:

- Selected candidate and candidate lane, if any
- Source path and source hash if available
- Inferred mode and confidence
- Asked questions
- Recommended defaults
- User answers
- Remaining uncertainty
- Decision
- Recommended next action
- Links to related work items, raw transcripts, query pages, or concepts

Keep this report distinct from `/dev-loop prep` reports. Do not put readiness
approval language in the report unless the user is explicitly told that
office-hours does not set readiness fields.

## Backreferences

If the selected source is a work item, ask whether to add or update a managed
section in that work item's `spec.md`:

```markdown
## Office Hours

- Date: YYYY-MM-DD
- Report: projects/<slug>/requirements/YYYY-MM-DD-office-hours-<topic>.md
- Decision: <decision>
- Recommended next action: <next-action>
```

Only edit this managed `## Office Hours` section. Preserve all other content.
After editing, run:

```bash
skillwiki validate <path-to-spec.md>
```

If validation fails, repair only the managed section when obvious; otherwise
revert the managed section edit and report the blocker.

If the selected source is a raw transcript, do NOT modify raw transcripts. Link
the raw transcript from the report and recommend the explicit promotion,
research, merge, defer, or discard action.

## Relationship To Other Skills

`grill-me` is an optional future escalation hook, not a v1 dependency. If the
conversation becomes too broad or adversarial clarification would help, record
that the next session should invoke `grill-me` for the selected topic. Do not
invoke `grill-me` automatically from office-hours v1.
