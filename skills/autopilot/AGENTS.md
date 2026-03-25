# Autopilot Skill Bundle

This folder is the source for the `autopilot` skill.

## Operating Rules

- Treat the first-release repo-local Codex bundle in `/Users/karlchow/Desktop/code/trends/.codex` as the preferred simplicity baseline.
- Prefer these files when updating the skill or validating current behavior:
  - `/Users/karlchow/Desktop/code/trends/.codex/config.toml`
  - `/Users/karlchow/Desktop/code/trends/.codex/hooks.json`
  - `/Users/karlchow/Desktop/code/trends/.codex/hooks/autopilot-stop.sh`
  - `/Users/karlchow/Desktop/code/trends/.codex/hooks/session-start.sh`
  - `/Users/karlchow/Desktop/code/trends/.codex/skills/autopilot_reset/SKILL.md`
  - `/Users/karlchow/Desktop/code/trends/scripts/hooks/cmux-autopilot-stop-core.sh`
  - `/Users/karlchow/Desktop/code/trends/scripts/hooks/cmux-session-start-core.sh`
  - `/Users/karlchow/Desktop/code/trends/scripts/autopilot-reset.sh`
- Keep Codex autopilot repo-local and explicit: `.codex/config.toml` enables hooks, `.codex/hooks.json` wires repo-local shims, and `.codex/skills/autopilot_reset/SKILL.md` stays tiny.
- Keep hook shims thin. The real behavior lives in the shared repo scripts under `scripts/hooks/` and `scripts/autopilot-reset.sh`.
- Treat same-session continuation as a separate problem. For that, prefer `ralph-loop` instead of expanding autopilot.
- Treat Claude Code built-in loop surfaces as better defaults for Claude. Do not present the legacy `.claude` autopilot bundle as the preferred workflow unless the user explicitly asks for Claude compatibility work.
- Do not center the skill on managed `~/.codex/hooks.json` or a user-level installer unless the user explicitly asks for that path.
- Treat `templates/` and `scripts/install_repo_local_autopilot.py` in this bundle as legacy Claude `.claude` support only.

## Legacy Files

These bundled files still exist for explicit Claude compatibility work only:

- `templates/hooks/autopilot-keep-running.sh`
- `templates/hooks/session-start.sh`
- `templates/commands/autopilot_reset.md`
- `scripts/install_repo_local_autopilot.py`

Do not use or recommend those files for Codex autopilot unless the user explicitly asks for the legacy Claude repo-local bundle.
