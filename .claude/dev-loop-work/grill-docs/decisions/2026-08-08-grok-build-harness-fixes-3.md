---
title: "Key handling: warn always + --require-keys"
status: accepted
date: 2026-08-08
---

# ADR-3: Key handling: warn always + --require-keys

## Context
install.sh prompts for the two gateway keys and the context7 key on a TTY;
in headless runs a missing key silently produced an env-only config whose
model aliases cannot resolve.

## Decision
- Always print an explicit warning listing which keys are missing and that
  the config will be env-only — including when the user declines at an
  interactive prompt.
- Add `--require-keys`: hard-fail when the hub or new gateway key is
  missing. The context7 key stays optional (it only feeds the MCP).
- Document the env-var fallbacks (HARNESS_HUB_KEY / HARNESS_NEW_KEY /
  HARNESS_CONTEXT7_KEY) in the warning.

## Consequences
Headless bootstraps can no longer produce a silently broken harness;
automation can demand keys; interactive declines are still permitted with
full disclosure.

## Alternatives Considered
- Fail by default in non-interactive mode (rejected — too strict for
  env-only workflows).
- Requiring all three keys under --require-keys (rejected — context7 is
  optional by nature).
