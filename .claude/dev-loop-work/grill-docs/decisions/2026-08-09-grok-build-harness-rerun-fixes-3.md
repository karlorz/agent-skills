---
title: "Config re-render preserves host-set keys via whitelist"
status: accepted
date: 2026-08-09
---

# ADR-3: Config re-render preserves host-set keys via whitelist

## Context

Field-test re-run of v0.2.0 rewrote the host config.toml from the template,
wiping the host's deliberate `[plugins].disabled = ["host-backup-restore"]`
(and `paths`). The existing preserve mechanism only covered
`marketplace.sources` (added in v0.2.0 for the Linux CLI-sources churn).
Any host-set key outside the template is silently dropped on re-run, which
can re-enable deliberately disabled plugins.

## Decision

Generalize preservation in `generate-config.py` to a whitelist rule: after
rendering, parse the existing config and append any top-level keys and
`[plugins]` sub-keys (e.g. `disabled`, `paths`) that the rendered output does
NOT emit. Template-owned keys keep winning by design (the template is the
source of truth for the harness); everything else the host set survives.

## Consequences

- `disabled = ["host-backup-restore"]` survives re-runs; no surprise
  re-enabling of host plugins.
- Future host tweaks (custom model sections, overrides) are preserved
  automatically.
- The mechanism replaces the special-case `--preserve-sources` logic with a
  single preserve step (marketplace sources become just another preserved
  key).

## Alternatives Considered

- Preserve only `disabled` + `paths`: tight scope but future host tweaks are
  still dropped.
- Warn-only: keeps render simple but re-runs keep degrading host state.
