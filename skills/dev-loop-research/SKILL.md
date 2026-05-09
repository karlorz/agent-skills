---
name: dev-loop-research
description: "Standalone research agent — scans repo health (CLI, skills, spec drift) and vault health (raw-to-page coverage, cross-link density, page quality, type coverage). Outputs prioritized work-item recommendations. Pass `high` for aggressive mode."
argument-hint: "[high]"
---

# Dev-Loop Research Agent (Standalone)

Standalone entry point for the research agent. Enables invocation
independent of the dev-loop idle path:

- One-shot: `/dev-loop-research` or `/dev-loop-research high`
- Recurring: `/loop 1h dev-loop-research`

## Intensity Level

Parse arguments for `high` (case-insensitive). If present,
**intensity = high**; otherwise **intensity = normal**. Full threshold
definitions live in the companion prompt (see Execution below).

## Project Config

Load the same way dev-loop does (`.claude/dev-loop.config.md`, then
CLAUDE.md introspection, then repo autodiscover). If session variables
from a prior REFRESH are already in scope (`$BACKEND_CAPS`,
`$VAULT_TYPES`, etc.), reuse them — do not re-read unchanged files.

## Execution

Read the full research agent prompt from the dev-loop skill's companion
file at `~/.claude/plugins/cache/karlorz-agent-skills/dev-loop/<version>/research.md`
(check the version directory) and execute exactly one research pass as
documented there. If the cache path is unavailable, fall back to
`skills/dev-loop/research.md` relative to the repo root.

The companion prompt is the canonical execution spec — it defines
intensity thresholds, Track A/B steps, SYNTHESIZE scoring, idle
fast-path, and save/exit protocol. This SKILL.md is the invocable
wrapper only.

## Rules

- One research pass per invocation — do not iterate.
- Delegate all logic to research.md; do not re-state its rules here.
