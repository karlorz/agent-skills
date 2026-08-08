---
title: "Security: documentation + --restrictive flag"
status: accepted
date: 2026-08-08
---

# ADR-8: Security: documentation + --restrictive flag

## Context
The template ships `[ui] permission_mode = "always-approve"` to every
fresh host, and `grok mcp list` prints the context7 key in plaintext.
Always-approve is right for a personal host but wrong for shared ones.

## Decision
- Document both exposures in `docs/harness-design.md` (security section)
  and the SKILL.md troubleshooting.
- Add `--restrictive` to install.sh: renders `permission_mode = "plan"`
  instead of `"always-approve"` via a new `__PERMISSION_MODE__` template
  token (generate-config.py gains a `--permission-mode` argument, default
  `"always-approve"`).

## Consequences
Fresh hosts get a one-flag choice between the permissive personal posture
and a conservative one. No behavior change for default installs.

## Alternatives Considered
- Docs only (rejected — no real option for shared hosts).
- Full key-file/env-only mode (deferred — stronger posture, more surface;
  tracked for a future round).
