---
title: "Live-host hygiene batch"
status: accepted
date: 2026-08-08
---

# ADR-6: Live-host hygiene batch

## Context
The reference host's `~/.grok` accumulated drift: three unknown
`[plugins]` keys warning on every inspect, two context7 plugin copies, nine
stale `config.toml.bak.*` files, and stale `[plugins].disabled` full-IDs
from a Claude-side scope.

## Decision
Apply four non-destructive cleanups:
1. Remove `plugins.ignore` / `server_skill_dirs` / `bundled_skill_dirs`
   (unknown no-ops).
2. Uninstall the direct-Git context7 copy (`context7-3b0946d1`); keep the
   marketplace-managed copy (`context7-27831ebe`).
3. Archive the nine `config.toml.bak.*` files to
   `~/.grok/backups/archive/` (recoverable, out of the way).
4. Drop the stale `disabled` full-IDs
   (`user/1be7e11b/hermes-cli`, `user/9528c5f4/host-backup-restore`).

## Consequences
Inspect warnings drop to zero; plugin state is unambiguous; no data is
destroyed. The template already excluded the unknown keys, so fresh hosts
were never affected.

## Alternatives Considered
- Deleting backups outright (rejected — keep recoverable).
- Keeping both context7 copies (rejected — redundant; config MCP shadows
  the plugin's anyway).
