---
description: "[DEV / Phase 1-2] Run one pass of the dev-loop-next skill (generic engine, reads .claude/dev-loop.config.md). Pass 'high' for aggressive mode. Phase 3 cutover will rename this to /dev-loop and archive the legacy command."
---

Invoke the `dev-loop-next` skill (this plugin) with `$ARGUMENTS` passed
through.

The skill is a generic single-pass PRD + skillwiki dev cycle. At
REFRESH it reads `./.claude/dev-loop.config.md` (relative to CWD) for
project specifics, falling back to CLAUDE.md introspection then repo
autodiscover.

Recognized args:
- `high` — aggressive mode (priority gates removed, top-5 research, never-idle)
- (no args) — normal mode

Project routing:

- `/dev-loop` (legacy, user-scope) → loads memory file `~/.claude/projects/.../memory/dev-loop-prompt.md` (active production path until Phase 3)
- `/dev-loop-next:dev-loop-next` or `/dev-loop-next` (this command, plugin-scoped) → invokes the generic skill (Phase 2/3 testing affordance)

After Phase 3 cutover:
- Plugin is renamed to `dev-loop`
- This command becomes `/dev-loop:dev-loop` (or `/dev-loop` flattened)
- Legacy user-scope `/dev-loop` is archived (never deleted)

Rules:
- ONE cycle only — do not iterate internally.
- Never `/clear`. `/compact` only at the documented threshold.
- If config is missing critical fields, prompt the user; do not invent values.
- Honor archive-never-delete: any file retirement goes to a sibling
  `_archive/YYYY-MM-DD/` directory with a README note, not `rm`.
