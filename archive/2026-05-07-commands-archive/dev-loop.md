---
description: Run one pass of the PRD + skillwiki dev loop (single-cycle, idempotent). Pass 'high' for aggressive mode.
---

Read the canonical dev loop prompt at
`~/.claude/projects/-Users-karlchow-Desktop-code-llm-wiki/memory/dev-loop-prompt.md`
and execute exactly ONE single-pass cycle as documented there.

## Intensity Level

Parse `$ARGUMENTS` for the keyword `high` (case-insensitive). If present,
set **intensity = high**; otherwise **intensity = normal**.

### normal (default)
Current behavior — respect priority tiers. Pick up P2+ items; only fall
through to P3 when nothing higher exists.

### high
Aggressive mode — **ignore priority gates entirely.** Every finding is
claimable work regardless of its P-score. Specifically:

- **WORK step**: pick the top-ranked item from the backlog without checking
  its priority tier. P3 and P4+ items are treated the same as P0.
- **IDLE DISCOVERY step 5**: remove the "only P3 if no P2+" guard. Execute
  the top research recommendation unconditionally.
- **Trivial fast-path**: prefer it more aggressively — anything under ~80 LOC
  qualifies (raised from ~50).
- **Research trigger**: after idle maintenance, always run
  `/dev-loop-research high` (passes high through to the research agent).
- **P3+ pickup**: in high mode there is no such thing as "only P3 left" —
  all items are equal. Do NOT exit idle when the backlog has any items.

Rules for this invocation:
- Run ONE cycle only — do not iterate internally.
- If no claimable work exists and nothing is in progress, skip to IDLE
  DISCOVERY in the prompt. After maintenance, invoke
  `/dev-loop-research` (with `high` if intensity is high) to scan for next
  work items. Do not invent work.
- If a previous cycle left a work item mid-step, resume at the next
  unfinished step rather than restarting.
- Never `/clear` during this invocation. `/compact` is allowed only at the
  COMPACT step per the documented thresholds.

Recommended schedules:
- `/loop 15m /dev-loop` — active session
- `/loop 1h /dev-loop` — background polling
- `/loop 10m /dev-loop high` — intensive sprint
