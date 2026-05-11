# Autopilot Skill Bundle

This folder is the source for the `autopilot` skill.

## Operating Rules

- Treat the managed Codex home-hook implementation in `/Users/karlchow/Desktop/code/cmux` as the preferred baseline.
- Prefer these files when updating the skill or validating current behavior:
  - `/Users/karlchow/Desktop/code/cmux/scripts/install-codex-home-hooks.sh`
  - `/Users/karlchow/Desktop/code/cmux/.codex/hooks/cmux-stop-dispatch.sh`
  - `/Users/karlchow/Desktop/code/cmux/.codex/hooks/managed-session-start.sh`
  - `/Users/karlchow/Desktop/code/cmux/.codex/hooks/home-autopilot-stop.sh`
  - `/Users/karlchow/Desktop/code/cmux/.codex/hooks/home-session-start.sh`
  - `/Users/karlchow/Desktop/code/cmux/.codex/hooks/autopilot-stop.sh`
  - `/Users/karlchow/Desktop/code/cmux/.codex/hooks/session-start.sh`
  - `/Users/karlchow/Desktop/code/cmux/.codex/skills/autopilot_reset/SKILL.md`
  - `/Users/karlchow/Desktop/code/cmux/scripts/hooks/cmux-autopilot-stop-core.sh`
  - `/Users/karlchow/Desktop/code/cmux/scripts/hooks/cmux-session-start-core.sh`
  - `/Users/karlchow/Desktop/code/cmux/scripts/autopilot-reset.sh`
  - `/Users/karlchow/Desktop/code/cmux/scripts/agent-autopilot.sh`
- Keep Codex autopilot managed at `~/.codex` by default. Treat `.codex/hooks/autopilot-stop.sh` and `.codex/hooks/session-start.sh` as optional repo-local overrides, not mandatory setup files.
- Keep hook shims thin. The real behavior lives in the shared repo scripts under `scripts/hooks/` and `scripts/autopilot-reset.sh`.
- Treat same-session continuation as a separate problem. Do not point users to an archived shared same-session loop skill or expand autopilot into a generic shared same-session loop.
- Treat Claude Code built-in loop surfaces as better defaults for Claude. Do not present the legacy `.claude` autopilot bundle as the preferred workflow unless the user explicitly asks for Claude compatibility work.
- Treat `templates/` and `scripts/install_repo_local_autopilot.py` in this bundle as legacy Claude `.claude` support only.

## Legacy Files

These bundled files still exist for explicit Claude compatibility work only:

- `templates/hooks/autopilot-keep-running.sh`
- `templates/hooks/session-start.sh`
- `templates/commands/autopilot_reset.md`
- `scripts/install_repo_local_autopilot.py`

Do not use or recommend those files for Codex autopilot unless the user explicitly asks for the legacy Claude repo-local bundle.
