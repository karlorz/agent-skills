# dev-loop-next plugin source archive

## 2026-05-07/commands-dev-loop-next.md

Archived during Phase 2.5 layout correction.

Original location: `skills/dev-loop-next/commands/dev-loop-next.md`
Plugin version when archived: v0.2.0 → v0.2.1

Reason: Claude Code auto-derives a slash command from a skill's `name:`
field when the skill ships via a plugin. The dedicated commands/ entry
was redundant — it would either conflict with the auto-derived
`/dev-loop-next` or be silently ignored. Sibling plugins (simplify,
loop, deep-research, autopilot, obsidian-gh-knowledge) all use the
auto-derive pattern; dev-loop-next now matches.

`argument-hint:` was added to SKILL.md frontmatter so users see the
expected arg shape (mirroring simplify's pattern).

Safe to delete only after the user explicitly confirms.
