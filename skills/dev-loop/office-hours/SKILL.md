---
name: office-hours
description: >
  Use when running an attended dev-loop office-hours checkpoint before prep,
  promotion, or /goal to choose one current-project topic and capture requirements.
---

# Dev-Loop Office Hours

Attended requirements intake for **one** current-project topic. Runs before
`/dev-loop prep`, promotion to planned work, or `/goal`: refreshes project brain
context unattended, lists current-project candidates, asks concrete requirement
questions one at a time, writes a vault-native report, and stops with a
recommended next action.

Office-hours is not `/dev-loop prep`. Prep approves automation readiness for
known work; office-hours helps decide what one thing needs clearer requirements
before prep or execution.

## Hard Rules

1. Run in the `main session only`. Do NOT spawn subagents for intake,
   candidate selection, or approval. `Do NOT call structured question tools from subagents`.
2. Handle exactly one topic, capture, or work item per invocation.
3. Brain and memory refresh is fully unattended — never ask the user to choose
   memory pages, wiki layers, or project-index refresh strategy.
4. Do NOT auto-select a no-topic candidate. List current-project candidates
   first, then ask the user which one to focus on.
5. `Do NOT modify raw transcripts` (immutable in v1).
6. `Do NOT auto-create planned work`.
7. `Do NOT set preflight readiness` fields (`automation_ready`,
   `human_questions_resolved`, `spec_preflight_approved`,
   `plan_preflight_approved`, `preflight_state`, `last_preflight`).
8. `Do NOT start or manage `/goal``.
9. Always write a report when the session reaches a selected topic, even if the
   decision is defer or research more.

## First-Run Anchoring

Prevent a fresh topic from anchoring to stale or completed work. Apply during
candidate selection and topic confirmation.

- A fresh user-supplied free-text topic is a valid selected topic after
  refresh. Do not force the user to pick an inventory candidate; list related
  candidates as context only.
- Completed or abandoned work items are **evidence**, not active candidates.
  Surface them only for context unless the user explicitly asks to reopen one.
- If the invocation names a `completed` or `abandoned` work item, state that it
  is completed and ask whether to reopen it or treat it as evidence before
  proceeding. Do not silently resume completed work.
- Reports must label fresh follow-up topics versus resumed work items (Report).

## Non-Interactive Guard

Office-hours is attended. Before prompting, detect non-interactive context: an
active `/goal` evaluator or unattended orchestrator; `codex exec`, CI, cron,
scheduled satellite, or no TTY-style channel; or a subagent/nested-worker. If
non-interactive, do not ask questions or write decisions — emit:

```text
Office-hours requires an attended main session. Run it before /goal or prep.
```

If the user supplied a topic, you may still perform read-only brain refresh and
print candidate context, but stop before any prompt or write.

## Inputs

```text
/dev-loop:office-hours
/dev-loop:office-hours --all
/dev-loop:office-hours <topic>
/dev-loop:office-hours <work-item-slug>
/dev-loop:office-hours raw/transcripts/<file>.md
```

`--all` (or a "show all" request) expands the candidate list from the default
bounded batch to full current-project scope. Keep the workflow one-topic after
the user selects a candidate.

## Refresh

Resolve the same project context dev-loop uses:

1. Read `.claude/dev-loop.config.md` if present.
2. Resolve `<slug>` from config; fall back to the repo basename.
3. Resolve `<vault>` from the configured SkillWiki backend. If `auto` or absent,
   run `skillwiki path`; if that fails, use a validated `~/wiki` only when
   `~/wiki/SCHEMA.md` and `~/wiki/projects/` exist.
4. Resolve `<repo>` as the current working repository.
5. Resolve the skill directory so helper calls run relative to this skill root.

If no SkillWiki vault resolves, refuse v1 office-hours:

```text
Office-hours v1 requires a SkillWiki vault so it can list project work and
write a requirements report.
```

### Brain Refresh

Run read-mostly, without asking the user to choose:

```bash
skillwiki memory index --project <slug>
skillwiki memory topics --project <slug> --limit <n>
skillwiki project-index <slug>
```

Treat `skillwiki project-index <slug>` as an orientation/staleness read only —
never turn it into readiness approval. Summarize compactly: memory index
(refreshed/already fresh/missing/failed), memory topics (top themes, recency),
project index (fresh/stale/missing/failed), and any limiting failures. Report
memory failures and continue; do not ask the user how to handle them.

### Candidate Inventory

Run the deterministic preflight inventory helper from the dev-loop skill
directory:

```bash
node scripts/preflight-inventory.js \
  --project <slug> --vault <vault> --repo <cwd> --limit <n>
```

Default `<n>` from `preflight.default_limit` when configured, otherwise `5`.
With `--all` or a "show all" request, rerun with `--all`.

Present candidates grouped by helper lane: `work` (planned, in-progress, or
repairable work items), `captures` (unclaimed project raw transcript tasks or
bugs), `hygiene` (structural issues needing human attention). Keep the list
project-scoped — do not list global wiki items unless linked to the current
project. If there are no candidates, present the brain refresh topics and ask
for one free-text focus topic.

## Select One Topic

Apply the First-Run Anchoring rules here.

- If the invocation names a work item, raw transcript, or topic: first check
  whether a named work item is `completed` or `abandoned` — if so, apply the
  completed-as-evidence rule (ask reopen-vs-evidence) before doing anything
  else. Otherwise treat it as the selected topic after refresh and surface
  related candidates for context.
- If no topic is supplied, ask the user to pick one candidate or provide a
  free-text topic.
- Never choose the top candidate automatically.
- Re-read the selected source immediately before asking requirement questions.
- If the source changed since inventory, state it is stale and ask whether to
  continue read-only or rerun inventory.
- If the selected source is a raw `task` or `bug` capture, re-run the helper
  read-only over the current project candidates and check whether that capture
  now appears in `hygiene` with `possibly_implemented_without_closure`. When it
  does, present the helper's evidence (`implemented_evidence` terms,
  `git_matches`, and relevant files) before normal intake. Ask the user to
  choose the handling path: `discard`, `merge-existing`, `hygiene-cleanup`,
  `research-more`, or continue normal requirements intake. Do not archive,
  edit raw transcripts, add `closes:`, or mark the capture complete from this
  heuristic alone.

Use a structured question for candidate choice when available (it is a decision
point). Put the recommended candidate first only with an evidence-based
recommendation; otherwise list in inventory order.

## Question Runner

Use structured question tools for decision points:

| Platform | Structured question tool |
|---|---|
| Claude Code | `AskUserQuestion` |
| Codex CLI or Codex App | `request_user_input` in Codex Plan mode; numbered conversational fallback in Codex Default mode |
| Antigravity CLI | `ask_question` |
| None available | `conversational fallback` |

Probe the live tool surface before calling a structured question tool.
In Codex App/CLI, use `request_user_input` only in Plan mode when the tool is exposed.
In Codex Default mode, do not call it; use conversational fallback with numbered
choices and wait for a normal user reply.

Decision points: choose one focus candidate; continue read-only after stale
inventory or rerun; choose the final decision; confirm a managed `## Office
Hours` section update on a work-item spec.

Use conversational free text for nuanced requirements. Ask one question at a
time, then decide the next. Stop once the next action is clear — prefer 2-5
good questions over a long checklist. All questions must be in the main session
only.

## Infer Intake Mode

Infer an internal mode from the selected source. Do not present
`product | builder | maintenance` as the primary user picker.

| Mode | Signals | Question focus |
|---|---|---|
| `product` | User-facing behavior, UX, customer value | User, outcome, scope, acceptance |
| `builder` | Implementation plan, API, tests, architecture, developer workflow | Behavior delta, constraints, files, compatibility, verification |
| `maintenance` | Hygiene, stale work, broken schema, failed validation, cleanup | Symptom, invariant, risk, rollback, validation |

If confidence is low, ask: "What decision should this office-hours session
unlock: product scope, implementation direction, or maintenance triage?" Record
the inferred mode and confidence in the report.

## Requirement Questions

Ask only enough to remove the next-action blocker.

**Product.** 1. Who is affected, and what should be different after this ships?
2. What is explicitly out of scope for v1? 3. What acceptance signal proves
this is done? 4. What risk would make you defer or split the work?

**Builder.** 1. What behavior or interface should change? 2. Which existing
files, conventions, or compatibility constraints must be respected? 3. What
validation is enough (tests, manual smoke, docs, release check, another
command)? 4. Is there a simpler path that preserves the required behavior?

**Maintenance.** 1. What symptom or stale state should disappear? 2. What must
remain unchanged? 3. What is the safe rollback or no-op boundary? 4. Which
command or vault validation proves the cleanup is safe?

If an answer reveals multiple topics, choose one with the user and record the
rest under remaining uncertainty.

## Decision

End with one recommended next action and the user's decision. Do not execute it
automatically — office-hours stops after the report.

- `promote-to-prep` — run `/dev-loop prep` for this now-clear work.
- `direct-dev-loop` — scope is clear enough for a single attended or normal
  dev-loop cycle, without readiness approval.
- `research-more` — evidence insufficient; use investigate or deep research.
- `merge-existing` — link to an existing work item instead of creating another.
- `hygiene-cleanup` — likely implemented but unclosed; create or update only a
  managed follow-up/report so a human can add an explicit closure or archive
  later.
- `defer` — keep the report as context, no immediate work.
- `discard` — no action.

## Report

Always write the report after a topic is selected:

```text
projects/<slug>/requirements/YYYY-MM-DD-office-hours-<topic>.md
```

Use the local date and a filesystem-safe `<topic>` slug; if the path exists,
append `-2`, `-3`, etc.

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

Required sections: `# Dev Loop Office Hours - <Topic>`, `## Context`, `## Brain
Refresh Summary`, `## Inferred Intake Mode`, `## Questions And Answers`, `##
Decision`, `## Recommended Next Action`, `## Links`.

The body records: selected candidate and lane (if any); source path and hash
(if available); inferred mode and confidence; asked questions; recommended
defaults; user answers; remaining uncertainty; decision; recommended next
action; stale-actionability recheck evidence when applicable; links to related
work items, raw transcripts, query pages, or concepts.

**Fresh-vs-resumed labelling:** in `## Context`, explicitly state whether this
is a fresh follow-up topic or a resumed work item. If a completed/abandoned item
was treated as evidence, record that and note it was not reopened.

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

Only edit this managed `## Office Hours` section; preserve all other content.
After editing, run `skillwiki validate <path-to-spec.md>`. If validation fails,
repair only the managed section when obvious; otherwise revert it and report the
blocker.

If the selected source is a raw transcript, do NOT modify raw transcripts. Link
it from the report and recommend the explicit promotion, research, merge, defer,
or discard action.

## Relationship To Other Skills

`grill-me` is an optional future escalation hook, not a v1 dependency. If the
conversation becomes too broad or adversarial clarification would help, record
that the next session should invoke `grill-me` for the selected topic. Do not
invoke `grill-me` automatically from office-hours v1.
