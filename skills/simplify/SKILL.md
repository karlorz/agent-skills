---
name: simplify
description: Review and simplify recently changed code for reuse, clarity, and efficiency while preserving behavior. Use when the user asks to simplify, refine, polish, clean up, or make code clearer, or after finishing a logical chunk of implementation that should be tightened before commit.
argument-hint: "[options] [focus] [<base-ref>]"
---

# Simplify

Use this skill to improve recently changed code without changing what it does.

## Usage

```
/simplify                              # Review current uncommitted changes
/simplify HEAD~3                       # Review changes from 3 commits ago to HEAD
/simplify main                         # Review changes from main branch to HEAD
/simplify abc123                       # Review changes from commit abc123 to HEAD
/simplify focus on error handling      # Focus review on specific concerns
/simplify focus on memory efficiency   # Focus review on memory efficiency
```

## Modes

```
/simplify --quick           # Single-pass quick review (commit prep)
/simplify --staged-only     # Review only staged changes
/simplify --json            # Output findings as JSON for tooling
/simplify --report-only     # Report findings without making changes
```

### Mode Descriptions

| Mode | Behavior |
|------|----------|
| `--quick` | Single-pass review focusing on high-impact issues only. Skips parallel agents. Best for quick commit prep. |
| `--staged-only` | Only review files in git staging area (`git diff --cached`). Ignores unstaged changes. |
| `--json` | Output findings as JSON array for CI/tooling integration. Format: `[{file, line, category, issue, suggestion}]` |
| `--report-only` | Generate report of findings without auto-fixing. Useful for CI comments. |

### Combined Usage

```
/simplify --quick --staged-only    # Quick review of staged files only
/simplify --json --report-only     # CI-friendly JSON report
```

## Workflow

### Mode Detection

First, parse the arguments to detect active modes:

- `--quick`: Set `QUICK_MODE=true`
- `--staged-only`: Set `STAGED_ONLY=true`
- `--json`: Set `JSON_OUTPUT=true`
- `--report-only`: Set `REPORT_ONLY=true`

Any remaining argument is treated as `<base-ref>`.

### 1. Scope the review

- If `STAGED_ONLY=true`, use `git diff --cached` to review only staged changes.
- If a `<base-ref>` argument is provided, use `git diff <base-ref>..HEAD` to get all changes from that reference to HEAD.
- Otherwise, prefer the current diff first.
- Use `git diff` for unstaged changes, or `git diff HEAD` when staged changes exist and you want the full working-tree delta.
- If there are no git changes, review files the user named or files you edited earlier in the session.
- Keep the scope narrow unless the user asks for a broader refactor.

### 2. Run review passes

**Quick Mode (`QUICK_MODE=true`):**
Do a single-pass review yourself, combining reuse, quality, and efficiency checks. Focus only on high-impact issues. Skip spawning parallel sub-agents.

**Standard Mode:**
Use parallel sub-agents when available. Give each pass the full diff or exact changed files plus enough surrounding context to make concrete recommendations. If parallel delegation is unavailable, do the same passes yourself sequentially.

#### Pass A: Reuse

- Search for existing helpers, utilities, shared components, common types, and adjacent patterns before keeping new code.
- Replace duplicated or near-duplicate logic with an existing abstraction when that reduces complexity.
- Prefer existing constants, enums, shared helpers, and common validation/parsing code over new ad hoc logic.

#### Pass B: Quality

- Remove redundant state, cached values that can be derived, unnecessary observers/effects, and dead branches.
- Reduce parameter sprawl. Prefer reshaping interfaces over threading more booleans, flags, or one-off options.
- Collapse copy-paste variants into a shared abstraction when it improves readability.
- Fix leaky abstractions, unclear naming, and control flow that is harder to follow than necessary.
- Prefer explicit, readable code over clever compression.
- Avoid style-only churn that does not improve maintainability.

#### Pass C: Efficiency

- Remove repeated work, duplicate I/O, N+1 patterns, and redundant computation.
- Parallelize independent operations when the codebase and runtime make that safe.
- Keep hot paths lean: startup code, request handlers, render paths, tight loops, and frequently called helpers.
- Flag recurring no-op updates: state/store updates inside polling loops, intervals, or event handlers that fire unconditionally without change-detection guards.
- Avoid pre-checking file or resource existence when it is cleaner to perform the operation and handle the error directly.
- Watch for unbounded collections, missing cleanup, leaked listeners, and long-lived resources that never get released.
- Flag overly broad operations: reading entire files when only a portion is needed, loading all items when filtering for one.

### 3. Fix or report issues

**Report-Only Mode (`REPORT_ONLY=true`):**
Do not make any changes. Instead, compile findings into a report. If `JSON_OUTPUT=true`, format as JSON array:

```json
[
  {
    "file": "src/example.ts",
    "line": 42,
    "category": "quality",
    "issue": "Redundant state variable",
    "suggestion": "Remove cachedValue and derive from source"
  }
]
```

**Standard Mode:**
- Aggregate the findings and fix high-confidence issues that materially improve the code.
- Skip false positives, speculative architecture changes, and low-value nits.
- Preserve behavior, public APIs, tests, and user-visible output unless the user explicitly asked for behavioral changes.

### 4. Validate the result

- Run focused validation for the touched area when practical: relevant tests, lint, typecheck, or a targeted build step.
- Prefer the smallest validation that can catch likely regressions.
- If validation is unavailable or too expensive for the moment, say what you did not run.

### 5. Report clearly

- Summarize what you simplified.
- Note any findings you intentionally skipped.
- Call out remaining risks or follow-up work only if they are real and actionable.

## Guardrails

- Follow the repository's own instructions and conventions first.
- Prefer smaller, reversible edits over sweeping refactors.
- Do not widen the change into unrelated files unless required.
- If a simplification would make the code more magical, less debuggable, or less explicit, do not do it.
- When in doubt, choose clarity over terseness.

## Delegation Template

When spawning sub-agents, each pass should get:

- the full diff or exact changed files
- one clear objective: `reuse`, `quality`, or `efficiency`
- instructions to return only actionable findings with file references
- instructions to avoid speculative redesigns outside the changed scope
