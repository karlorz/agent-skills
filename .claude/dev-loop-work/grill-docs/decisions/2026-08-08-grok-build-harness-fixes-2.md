---
title: "Repo test script for the harness plugin"
status: accepted
date: 2026-08-08
---

# ADR-2: Repo test script for the harness plugin

## Context
grok-build-harness is the only plugin in the karlorz-agent-skills repo
without a test suite, and CI does not exercise its installer or config
generator. Other plugins set the pattern (scripts/test-*.sh, tests/).

## Decision
Add `scripts/test-grok-build-harness.sh` covering, without needing a grok
binary: `bash -n` on install.sh/generate-config.py (shell + python syntax),
config generation in with-keys / env-only / restrictive modes with TOML
validation and token checks, `install.sh --dry-run` output sanity,
AGENTS.md skillwiki-marker merge, and re-run idempotency on a scratch
GROK_HOME. Wire it as a step in `.github/workflows/ci.yml` after the
preflight inventory check.

## Consequences
Every push gates the installer's static behavior. CI has no grok binary, so
runtime behavior (plugin installs, verify) stays covered by the separate
E2E workflow (ADR-9) and by local scratch runs.

## Alternatives Considered
- Test script without CI wiring (deferred — weaker guarantee).
- Folding assertions into test-plugin-metadata.sh (rejected — different
  concern, would muddy that suite).
