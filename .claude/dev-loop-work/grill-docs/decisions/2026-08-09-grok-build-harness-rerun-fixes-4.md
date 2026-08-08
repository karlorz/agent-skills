---
title: "Keyless re-run over keyed config skips render unless --force-render"
status: accepted
date: 2026-08-09
---

# ADR-4: Keyless re-run over keyed config skips render unless --force-render

## Context

During the v0.2.0 field test, a re-run that supplied the hub/new keys but
missed the context7 key silently rewrote the live config, dropping the
context7 `--api-key` pair (env-only downgrade). The installer warned
generically ("config will be env-only") but nothing detected that the
existing config had injected keys, so the degradation happened by default.

## Decision

`render_config` gains a downgrade guard: when the existing config.toml
contains injected keys (any `api_key` line in `[model.*]` or an `--api-key`
argument in `mcp_servers`) and the run provides no key at all (no
`--hub-key`/`--new-key`/`--context7-key` and no `HARNESS_*` env), the render
is SKIPPED: the existing keyed config is left untouched, a specific warning
explains why, and `--force-render` overrides. A fresh host with no existing
config still renders env-only as before (keys genuinely unavailable).

## Consequences

- Upgrade re-runs can never accidentally degrade a working keyed config.
- The downgrade path requires an explicit, informed choice (`--force-render`)
  or a fresh host.
- `--no-config` remains available to skip config work entirely.

## Alternatives Considered

- Warn-only with a specific message: still degrades by default.
- Hard fail without `--force-render`: breaks unattended re-runs whose key env
  vars are temporarily missing.
