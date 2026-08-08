---
title: "One-time block-match migration for unmarked v0.2.0 AGENTS.md"
status: accepted
date: 2026-08-09
---

# ADR-2: One-time block-match migration for unmarked v0.2.0 AGENTS.md

## Context

ADR-1 introduces a `<!-- grok-build-harness:begin/end -->` marker block, but
hosts installed with v0.2.0 (including this one) have an unmarked
`## Subagent contract` section. Without migration, the first v0.3.0 run would
either duplicate the contract or (with insert-only) leave a stale unmarked
copy.

## Decision

On the first run where the existing file has no harness marker: if the file
contains a `## Subagent contract` section whose final known line is
`- Full rules: read `~/.grok/agentrules.md`.`, replace exactly that block
(from the heading through that final line) with the new marked contract
block. Everything before and after it is preserved verbatim. If the known
block is not found, fall back to inserting the marked contract at the top
(after the skillwiki marker if present) without removing anything.

## Consequences

- The live host's `## User preferences` section (after the contract) survives
  migration.
- The migration is heuristic but safe: it only removes text that exactly
  matches the known contract shape; anything else is preserved and backed up
  by copy_if_changed.
- After one run, the file is in canonical marked form and subsequent runs use
  pure marker splicing.

## Alternatives Considered

- Insert-only migration: safe, but leaves a duplicate stale contract block.
- No migration: leaves the live host in the old shape indefinitely.
