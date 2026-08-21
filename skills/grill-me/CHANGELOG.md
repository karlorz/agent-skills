# Changelog

All notable changes to this skill are documented in this file.

## [1.0.1] - 2026-08-21

- Cache-bust Cursor import: keep `skills` at `./skills/` (nested `grill-me` + `grilling`) and bump so stale Claude caches that still declare `skills: "./"` get replaced. Cursor's one-level scan skipped the old cache.
- Add `cursor` keyword for marketplace discovery.

## [1.0.0] - 2026-08-10

- packages both skill names for direct invocation.
