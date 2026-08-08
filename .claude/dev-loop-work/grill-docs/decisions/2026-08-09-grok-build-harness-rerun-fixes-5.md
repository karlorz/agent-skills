---
title: "Regression tests for field-test scenarios, local + E2E"
status: accepted
date: 2026-08-09
---

# ADR-5: Regression tests for field-test scenarios, local + E2E

## Context

All three v0.2.0 field-test failures (AGENTS.md user-content drop, disabled
list clobber, keyed-config downgrade) were invisible to the scratch-home test
script and E2E because those environments start empty: no user content in
AGENTS.md, no host-specific config keys, no previously injected keys.

## Decision

Add regression coverage in both layers:

- `scripts/test-grok-build-harness.sh` (runs in the CI step):
  - re-run over a keyed config renders identical (no backup, no churn)
  - keyless re-run over a keyed config skips the render and warns
  - `--force-render` over a keyed config produces env-only
  - AGENTS.md merge preserves a user section on re-run
  - unmarked-contract migration converts to the marked form, keeping user
    content before and after the block
- `.github/workflows/e2e.yml`: a final phase that seeds user edits (user
  section in AGENTS.md, `disabled` entry in config) on the scratch home, then
  re-runs and asserts they survive.

## Consequences

- The specific behaviors that failed in the field are pinned by CI.
- E2E stays green-gated on the real-host-shaped user-edit path.
- Slightly longer test/E2E runtimes.

## Alternatives Considered

- Test script only: misses the real-host-shaped path in E2E.
- No automated tests: next install.sh change can silently re-break
  preservation.
