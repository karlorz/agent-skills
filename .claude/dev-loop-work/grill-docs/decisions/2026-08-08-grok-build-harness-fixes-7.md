---
title: "web_search setting kept and documented"
status: accepted
date: 2026-08-08
---

# ADR-7: web_search setting kept and documented

## Context
The reference config carries `[models] web_search = "no-such-model"` —
undocumented, looks deliberate (disables the web-search model) but could
be a leftover experiment.

## Decision
Keep the setting on the host and in the template, and document it: add a
comment in `config.toml.template` and a line in `docs/harness-design.md`
explaining it intentionally disables the web-search model.

## Consequences
No behavior change; the quirk stops being a mystery on every fresh host.

## Alternatives Considered
- Removing the key (rejected — changes search behavior without evidence
  that was wanted).
- Leaving undocumented (rejected — this round exists because of such
  silent quirks).
