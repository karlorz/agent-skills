---
name: rtk-output-design
description: "Use when designing, reviewing, or implementing CLI, skill, hook, or script output for AI agents. Distills RTK-style token-killing output patterns: compact summaries, failure-focused filtering, structured JSON, omission accounting, exit-code preservation, and verification checks for token-efficient developer tools."
---

# RTK Output Design

Use this skill to make CLI, skill, hook, and script output useful to an agent
without flooding its context. Treat output as a contract: preserve the signal
needed for the next action, make compression explicit, and keep raw detail
available on demand.

## Core Contract

Design every command around this shape:

```yaml
status: success | partial | failure
summary: one sentence with the important result
stats: counts, durations, paths, bytes, token estimates, or changed totals
items: only the highest-value errors, warnings, changed files, matches, or rows
omitted: what was hidden and why, with counts when possible
next_actions: concrete commands or fixes when the result is not done
provenance: command, mode, input scope, and source paths when relevant
```

For human output, render this shape as compact sections. For automation, expose
it as stable JSON.

## Output Modes

Provide these modes when the tool has non-trivial output:

| Mode | Purpose | Rules |
| --- | --- | --- |
| Default | Agent-readable terminal output | Compact summary first, failures before successes, bounded examples. |
| `--json` | Script and agent automation | Print one valid JSON object to stdout. Put non-JSON diagnostics on stderr. |
| `--verbose` / `-v` | Debugging | Add raw command, matched rules, and timing. Keep the default concise. |
| `--raw` | Escape hatch | Show unfiltered upstream output for audits, parser bugs, or human inspection. |
| `--dry-run` | Preview changes | Show planned writes or hook edits without mutating files. |

Preserve upstream exit codes unless the wrapper itself fails. If filtering fails,
prefer raw output plus a short filter warning over hiding command results.

## Filtering Strategy

Choose the cheapest strategy that preserves the next useful action:

| Input Shape | Strategy | Keep |
| --- | --- | --- |
| Successful build/test/install logs | Progress filtering | Final status, duration, warnings, changed artifacts. |
| Failed build/test/lint runs | Failure focus | Error blocks, failing test names, stack heads, file:line, repro command. |
| Repeated log lines | Deduplication | Unique message, count, first/last timestamp or location. |
| Search output | Group by pattern | Match counts by file or rule, then representative matches. |
| Large diffs or status | Stats extraction | File counts, additions/deletions, changed paths, conflict state. |
| Directory listings | Tree compression | Top-level structure, important files, counts for hidden children. |
| JSON or structured text | Structure-only or summarized JSON | Keys, types, counts, selected values needed for the task. |
| Language source dumps | Code filtering | Signatures, exports, imports, failing region, omitted body counts. |
| Streamed test output | State-machine parsing | Suite lifecycle, failures, skipped count, slow tests. |
| NDJSON or event streams | Streaming aggregation | Counts by event type plus the most actionable events. |

Never compress away:

- Non-zero status, panic, exception, traceback, failed assertion, or stderr.
- File paths, line numbers, command names, versions, config locations, or IDs
  needed for the next command.
- Security, permission, data-loss, migration, or destructive-action warnings.
- The fact that output was omitted.

## Default Text Template

Use this layout for CLI output that an agent will read:

```text
<STATUS>: <one-sentence summary>

Stats:
- <count or metric>
- <duration or scope>

Findings:
- <file:line or id> <message>
- <group> <count> occurrences, example: <short sample>

Omitted:
- <count> low-signal lines hidden; use --raw or --verbose for details

Next:
- <single best next command or action>
```

Omit empty sections. Keep the default output small enough to scan in one screen;
for broad commands, prefer the top 10 to 20 actionable items plus counts.

## JSON Schema

For `--json`, use one object with stable keys:

```json
{
  "status": "success",
  "summary": "3 files changed, no failures",
  "command": {
    "argv": ["tool", "check"],
    "cwd": "/repo",
    "exit_code": 0,
    "duration_ms": 1234
  },
  "stats": {
    "files": 3,
    "warnings": 0,
    "errors": 0,
    "omitted_lines": 248
  },
  "items": [
    {
      "kind": "change",
      "path": "src/main.rs",
      "line": 42,
      "message": "updated parser"
    }
  ],
  "omitted": [
    {
      "kind": "progress",
      "count": 248,
      "reason": "progress and success lines hidden"
    }
  ],
  "next_actions": ["run cargo test"],
  "meta": {
    "schema": "rtk-output-design.v1",
    "raw_available": true
  }
}
```

Rules:

- Keep keys stable across versions. Add optional keys instead of renaming.
- Use arrays for repeated data even when there is one item.
- Use `null` only when absence is meaningful; otherwise omit optional keys.
- Keep raw multiline blobs out of JSON unless explicitly requested.
- Include `schema` when downstream agents or tests may depend on the shape.

## Skill And Hook Output

For skills, prompts, and hooks:

- Start with the decision or result, then evidence. Do not make agents infer the
  status from a long transcript.
- Include the minimum procedure needed to reproduce or continue.
- Put large references behind paths or commands the agent can open only when
  needed.
- For generated plans or reports, label each item with status, owner/scope, and
  verification evidence.
- For hook rewrites or suggestions, show the original command, rewritten
  command, and reason in one compact block.

Example hook message:

```text
RTK: rewrite suggested
original: pytest -q
rewrite:  rtk pytest -q
reason:   filter passing tests; preserve failures and exit code
```

## CLI Development Checklist

Before shipping a CLI, skill helper, or script:

1. Define the default text output and `--json` schema before implementation.
2. Decide which filtering strategy applies to each verbose command path.
3. Preserve exit codes and stderr semantics.
4. Add `--raw` or an equivalent debug path for compressed output.
5. Make omissions visible with counts and reasons.
6. Sort findings by actionability: failures, unsafe warnings, changed paths,
   grouped summaries, then success details.
7. Bound examples and list lengths. Include totals so truncation is honest.
8. Test success, partial, failure, no-match, huge-output, and parser-error
   cases.
9. Snapshot JSON shape or validate it with schema assertions.
10. Verify the output from an agent perspective: can the next command be chosen
    without asking for the raw transcript?

## Anti-Patterns

- Printing banners, progress bars, spinners, dependency trees, or full passing
  test logs by default.
- Hiding non-zero exits behind a friendly summary.
- Returning prose-only output for data another script must parse.
- Emitting invalid JSON with comments, log prefixes, or trailing text.
- Showing raw files or diffs when counts plus changed paths would answer the
  question.
- Compressing output without saying what was omitted.
- Creating a skill that explains usage at length but does not define the output
  contract agents should follow.

## Acceptance Test

A tool follows this guide when an agent can answer these questions from default
output alone:

- Did it succeed, partially succeed, or fail?
- What changed or what was found?
- What exact file, line, command, or ID matters next?
- What was hidden, and how can raw detail be recovered?
- What command or edit should happen next?

If any answer requires scanning raw logs, redesign the output or add a focused
summary path.
