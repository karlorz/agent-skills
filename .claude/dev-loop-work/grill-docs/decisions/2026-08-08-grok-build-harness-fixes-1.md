---
title: "Scope: grok-build-harness fix round"
status: accepted
date: 2026-08-08
---

# ADR-1: Scope: grok-build-harness fix round

## Context
A `/grok-build-init` field test plus a subsequent review pass produced seven
improvement candidates for the grok-build-harness plugin, its release
tooling, this host's grok state, and the repo CI.

## Decision
All seven items are in scope for this round:
1. Repo test script for the harness plugin, wired into CI.
2. `--require-keys` flag + always-on warning for missing keys.
3. `grok models` sanity check in `--verify`.
4. `bump-version.sh` generic SKILL.md locate fallback.
5. Security: documentation + `--restrictive` flag.
6. Live-host hygiene (unknown config keys, context7 dedupe, stale backups,
   stale disabled IDs).
7. Separate CI E2E workflow running a full scratch bootstrap with a real
   grok binary.

## Consequences
The installer gains flags and verification depth; the repo gains a test
suite entry and a second workflow; the host config gets cleaned. Each item
is independently testable and all land in one release.

## Alternatives Considered
- Restricting scope to plugin fixes only (deferred — user chose all seven).
