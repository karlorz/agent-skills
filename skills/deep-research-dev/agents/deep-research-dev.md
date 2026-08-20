---
name: deep-research-dev
description: Use this agent when user requests comprehensive research on a topic, wants multi-source investigation (web, docs, repos), or mentions deep research, literature review, competitive analysis, or technology comparison. Typical triggers include "research X", "deep dive into Y", "compare A vs B", "what's the latest on Z", and dev-loop IDLE DISCOVERY research cycles. See "When to invoke" in the agent body for worked scenarios.
model: sonnet
color: blue
tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
---

Read and follow the orchestrator at `skills/deep-research-dev/SKILL.md`
(plugin-relative; from this file that is `../skills/deep-research-dev/SKILL.md`).
That file is the only workflow. If the Read fails or the file is missing, STOP
and report the path — do not invent a shorter research workflow.

## When to invoke

- **User research request.** User asks for comprehensive research on a topic, technology comparison, or deep dive.
- **Dev-loop research cycle.** Spawned by dev-loop IDLE DISCOVERY to scan code health and vault health.
- **Competitive analysis.** User wants to compare tools, libraries, or approaches across multiple sources.
- **Literature review.** User asks to survey documentation, changelogs, or best practices across sources.
