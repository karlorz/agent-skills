---
title: "Verify asserts pin aliases via grok models"
status: accepted
date: 2026-08-08
---

# ADR-4: Verify asserts pin aliases via grok models

## Context
The harness economy rests on `[subagents.models]` pins resolving to the
sonnet/haiku/flash aliases. If those aliases fail to register (broken BYOK
gateway, missing keys), every scout and pin silently resolves to nothing.

## Decision
`--verify` runs `grok models` against the target GROK_HOME and asserts the
three load-bearing names — `sonnet`, `haiku`, `deepseek-v4-flash` — appear
in the available-models list. Missing names are reported and fail the
verification (non-zero exit). The model count is also printed.

## Consequences
A broken gateway is caught at bootstrap time instead of at first session.
The check needs the grok binary, so it runs only when plugin steps run
(gated on --skip-plugins), consistent with the existing plugin checks.

## Alternatives Considered
- Asserting only sonnet (rejected — haiku/default aliases matter too).
- Display-only (rejected — the point is a hard gate).
