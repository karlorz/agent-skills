---
title: "AGENTS.md merge preserves user content via harness marker block"
status: accepted
date: 2026-08-09
---

# ADR-1: AGENTS.md merge preserves user content via harness marker block

## Context

Field-test re-run of v0.2.0 revealed that `merge_agents_md` replaces
everything in `~/.grok/AGENTS.md` except the llm-wiki skillwiki marker block
with the bundled subagent contract. The live host had a user-authored
`## User preferences` section after the contract; the re-run backed it up and
removed it from the live file. The scratch/E2E tests did not catch this
because scratch homes have no user content in AGENTS.md.

## Decision

Adopt the llm-wiki pattern: the harness contract is wrapped in its own
`<!-- grok-build-harness:begin --> ... <!-- grok-build-harness:end -->`
marker block. The merge keeps ALL existing content verbatim and replaces only
the harness-owned block (or inserts it when absent).

## Consequences

- User additions to AGENTS.md survive re-runs; no silent content loss.
- Idempotency is preserved: re-run over the merged result is byte-identical.
- The asset becomes a marked block instead of a bare `## Subagent contract`
  section; the skillwiki marker (a separate, llm-wiki-owned block) is
  untouched.

## Alternatives Considered

- Append-only merge: safe for user content but leaves stale contract
  duplicates when the asset changes.
- Warn + prompt before overwrite: still drops content on unattended (-y)
  runs and adds interaction cost.
