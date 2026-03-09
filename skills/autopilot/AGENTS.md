# Autopilot Skill Bundle

This folder is the source for the `autopilot` skill.

## Operating Rules

- The source-of-truth files for repo-local installs live inside this bundle under `templates/`.
- The installer entrypoint is `scripts/install_repo_local_autopilot.py`.
- Install into a target repository's local `.claude/` directory only. Do not install into `~/.claude/`.
- The installed hook commands must use repo-local paths: `"$CLAUDE_PROJECT_DIR"/.claude/...`.
- The installer must be idempotent: re-running it must not duplicate hook entries or re-add duplicate files.
- Preserve unrelated entries in the target repo's `.claude/settings.json`, including other hook commands and non-hook settings.
- Keep the autopilot Stop hook first in the Stop hook chain so downstream hooks can observe the blocked flag correctly.
- If the target settings file already defines `AUTOPILOT_KEEP_RUNNING_DISABLED` or `CLAUDE_AUTOPILOT_MAX_TURNS`, preserve the user's existing values.

## Installed Files

- `.claude/hooks/autopilot-keep-running.sh`
- `.claude/hooks/session-start.sh`
- `.claude/commands/autopilot_reset.md`
- `.claude/settings.json` patched in place

## Settings Merge Rules

- `SessionStart`: ensure one repo-local `session-start.sh` command exists; append a dedicated hook entry if missing.
- `Stop`: ensure one repo-local `autopilot-keep-running.sh` command exists and place it first.
- Remove duplicate autopilot hook commands before inserting the canonical repo-local entry.
- Preserve all unrelated hook groups and hook ordering outside the autopilot-specific insertion point.
- Set `$schema` only if missing.
- If the target `.claude/settings.json` contains invalid JSON, fail with a clear error instead of overwriting the file.

## Runtime Files

The installed hooks and reset command rely on these session-scoped files under `/tmp`:

- `/tmp/claude-current-session-id`
- `/tmp/claude-autopilot-turns-<session-id>`
- `/tmp/claude-autopilot-stop-<session-id>`
- `/tmp/claude-autopilot-blocked-<session-id>`
- `/tmp/claude-autopilot-completed-<session-id>`
