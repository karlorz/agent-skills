---
title: "Separate CI E2E workflow"
status: accepted
date: 2026-08-08
---

# ADR-9: Separate CI E2E workflow

## Context
The fast verify suite has no grok binary, so runtime bootstrap behavior
(plugin installs, verify, flag paths) is only exercised manually via
GROK_HOME scratch runs. A full E2E job costs minutes per push.

## Decision
Add `.github/workflows/e2e.yml`: installs grok stable via the official
installer, then runs the full scratch bootstrap with `--verify` plus the
`--require-keys` failure path and the `--restrictive` mode, asserting exit
codes and key invariants. Triggers: push to main AND `workflow_dispatch`
(manual). Not part of the fast ci.yml suite, so quick fixes are not slowed,
but every release commit runs it.

## Consequences
Every release gets a real runtime gate; pushes stay fast. The installer
URL (`https://x.ai/cli/install.sh`) gets continuously validated by the
workflow itself.

## Alternatives Considered
- Inline blocking job in ci.yml (rejected — slows every push).
- No CI E2E (rejected — runtime regression would be invisible).
