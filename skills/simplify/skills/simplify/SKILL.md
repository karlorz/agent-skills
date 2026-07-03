---
name: simplify
description: Use when reviewing recent code changes for simplification before commit, when the user asks to simplify, refine, polish, or clean up code, or when dev-loop requires its simplify review gate.
---

# Simplify

Use this skill to improve changed code without changing intended behavior. It
matches the Claude Code `/simplify` v2.1.199 shape:

`/simplify -> 4 cleanup agents in parallel -> apply the fixes`

This is not a correctness-bug hunt. Review for reuse, simplification,
efficiency, and altitude issues; leave bug-finding to code review or debugging
workflows.

## Usage

```
/simplify                         # Review the current diff
/simplify HEAD~3                  # Review changes from HEAD~3 to HEAD
/simplify main                    # Review changes against main
/simplify path/to/file.ts         # Review an explicit file target
/simplify 123                     # Review an explicit PR target when supported
/simplify focus on error handling # Keep the same flow, with added focus
```

## Phase 0 - Gather the diff

Treat the gathered diff as the review scope.

1. If the user passed a PR number, branch name, or file path, review that
   target instead of guessing a default range.
2. Otherwise, prefer `git diff @{upstream}...HEAD`.
3. If there is no upstream, fall back to `git diff main...HEAD`, then
   `git diff HEAD~1`.
4. If there are uncommitted changes, or the selected range diff is empty, also
   run `git diff HEAD` and include the working-tree changes. This review often
   runs before the next commit.
5. If all diff commands are empty, review only files the user explicitly named
   or files changed earlier in the current session. If there is still no scope,
   say that there is no changed code to simplify.

Keep the scope narrow. Do not widen into unrelated files unless the user asks
for a broader cleanup.

## Phase 1 - Review

Launch 4 independent review agents in one message when the platform supports
parallel agents. Pass every agent the same diff and exactly one review angle.
If parallel delegation is unavailable, perform the same four reviews yourself
while keeping the findings separated by angle.

Each finding must include `file`, `line`, a one-line `summary`, and the
concrete cost: what is duplicated, wasted, or harder to maintain.

### Reuse

Flag new code that re-implements something the codebase already has. Search
shared or utility modules and files adjacent to the change, then name the
existing helper, type, component, constant, or pattern to use instead.

### Simplification

Flag unnecessary complexity added by the diff: redundant or derivable state,
copy-paste with small variations, deep nesting, dead code left behind, and
control flow that is harder than the behavior requires. Name the simpler form
that does the same job.

### Efficiency

Flag wasted work introduced by the diff: redundant computation, repeated I/O,
independent operations run sequentially, and blocking work added to startup or
hot paths. Also flag long-lived objects built from closures or captured
environments because they keep the enclosing scope alive for the object's
lifetime; prefer a class, struct, or plain data object that copies only the
fields it needs. Name the cheaper alternative.

### Altitude

Check that each change is implemented at the right depth rather than as a
fragile bandaid. Special cases layered on shared infrastructure usually mean
the fix is not deep enough; prefer generalizing the underlying mechanism over
adding one-off branches.

## Phase 2 - Apply the fixes

Wait for all four reviews to finish. Then dedup findings that point at the same line
or mechanism, then fix each remaining high-confidence issue directly.

Skip a finding when the fix would change intended behavior, require changes
well outside the reviewed diff, or appear to be a false positive. Note the skip
briefly instead of arguing with the finding.

Preserve behavior, public APIs, tests, and user-visible output unless the user
explicitly requested a behavior change.

## Validate

Run the smallest relevant validation for the files you changed: targeted tests,
lint, typecheck, or a focused build. If no useful validation is available or it
is too expensive for the moment, say exactly what was not run.

## Report

Finish with a short summary:

- What was fixed.
- What was skipped and why.
- Any real remaining risk or follow-up.

If there were no actionable findings, say the changed code was already clean
for the four simplify angles.

## Guardrails

- Follow repository instructions and local patterns first.
- Prefer small, reversible edits over sweeping refactors.
- Do not turn explicit code into clever or magical code.
- Do not make style-only churn.
- When a simplification would make the code less debuggable, keep the clearer
  version.
