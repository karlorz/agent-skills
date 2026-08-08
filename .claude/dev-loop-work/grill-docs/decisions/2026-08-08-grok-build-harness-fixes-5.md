---
title: "bump-version.sh generic SKILL.md locate"
status: accepted
date: 2026-08-08
---

# ADR-5: bump-version.sh generic SKILL.md locate

## Context
`scripts/bump-version.sh` resolves the SKILL.md existence gate through two
hardcoded patterns (`skills/<plugin>/skills/<plugin>/SKILL.md` or
`skills/<plugin>/SKILL.md`). grok-build-harness's skill is named
`grok-build-init`, so the tool refuses to bump it and every release was a
manual edit.

## Decision
Add a third resolution branch: when both known patterns miss, locate any
`skills/*/SKILL.md` (depth 2) under the plugin directory. SKILL_MD is used
only as an existence gate — the edits touch only the JSON manifests — so
this is safe for multi-skill plugins (dev-loop still matches branch one).
Update the die message accordingly.

## Consequences
`bump-version.sh grok-build-harness patch` works; existing fixtures
(demo-codex, demo-basic) still hit branch one and keep passing.

## Alternatives Considered
- Documentation-only (rejected — the tool should just work).
- Leaving the gap (rejected — recurring manual-bump cost).
