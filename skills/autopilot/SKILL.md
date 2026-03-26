---
name: autopilot
description: Install, inspect, or refresh the bundled managed Codex home-hook autopilot flow. Use when asked to make Codex autopilot work in any repo or arbitrary workspace, run the bundled `scripts/install-codex-home-hooks.sh` installer, verify `~/.codex/hooks.json` plus `~/.codex/hooks/*.sh`, debug optional repo-local `.codex/hooks/autopilot-stop.sh` and `.codex/hooks/session-start.sh` overrides, or keep the legacy `.claude` bundle clearly secondary.
---

# Managed Codex Autopilot

Use this skill for the bundled managed Codex home-hook autopilot design with optional repo-local overrides.

## Choose the right tool

- If the user wants Codex to keep working on the current bounded task in the same session, do not route them to an archived shared same-session loop skill.
- Use `$autopilot` when the user wants managed Codex home hooks installed or refreshed, arbitrary-workspace autopilot support, or repo-local override shims inspected.
- Treat Claude Code built-in loop features as the better default for Claude. Only use the bundled `.claude` files for explicit legacy compatibility work.

## Bundled resources

- `scripts/install-codex-home-hooks.sh`
- `scripts/test-codex-home-hooks-install.sh`
- `scripts/test-codex-home-hooks-smoke.sh`
- `assets/codex-home/hooks/`
- `assets/codex-home/lib/`
- `assets/codex-home/skills/autopilot_reset/SKILL.md`

The installer copies those bundled assets into `~/.codex` so the managed home hooks remain self-contained after installation.

## Design rules

- Keep the default Codex lane in managed `~/.codex/hooks.json`. `SessionStart` should call `~/.codex/hooks/managed-session-start.sh` and `Stop` should call `~/.codex/hooks/cmux-stop-dispatch.sh`.
- Keep the managed home entrypoints thin. They should route to workspace overrides first, then to managed home fallbacks, and only emit plain text or allow-stop when no hook exists.
- Install the shared Codex autopilot support scripts into `~/.codex/autopilot/` so the managed home hooks do not depend on a checkout outside the installed skill bundle.
- Keep `.codex/hooks/autopilot-stop.sh` and `.codex/hooks/session-start.sh` optional. Use them only when the workspace needs to override the managed home fallback.
- Keep home fallback wrappers thin. They should resolve the workspace root from recorded session workspace files or hook cwd, then `exec` the shared scripts in `~/.codex/autopilot/hooks/`.
- Gate continuation with `CMUX_AUTOPILOT_ENABLED` or `CMUX_CODEX_HOOKS_ENABLED` so ordinary Codex sessions do not autopilot accidentally.
- Keep `autopilot_reset` minimal. It should call `AUTOPILOT_PROVIDER=codex bash "${CODEX_HOME:-$HOME/.codex}/autopilot/autopilot-reset.sh" <mode>` and should not duplicate control logic.
- Keep `autopilot_reset` default targeting on the latest recorded global Codex session. When multiple sessions may exist, direct the user to `status-all`.

## Procedure

1. Determine whether the user wants same-session continuation or managed home-hook autopilot. If it is same-session continuation only, keep working directly in the current session instead of routing to an archived shared skill.
2. Run the bundled installer from the installed skill directory.
   The `skills` CLI installs this bundle under `.agents/skills/autopilot` for both project and global scope, so the usual path is:
   `.agents/skills/autopilot/scripts/install-codex-home-hooks.sh`
   If the bundle was copied somewhere else manually, run the same installer from that installed skill folder instead.
3. Inspect the installed managed files in `~/.codex/hooks/`, `~/.codex/autopilot/`, and `~/.codex/skills/autopilot_reset/`.
4. When a workspace needs custom routing, add or update only `.codex/hooks/autopilot-stop.sh` and `.codex/hooks/session-start.sh`. Do not require a full repo-local `.codex` bundle just to enable Codex autopilot.
5. For arbitrary workspaces with no `.codex` bundle, rely on the managed home fallback. SessionStart should still record the latest session ID and workspace-root tracking files, and Stop should still block through the home autopilot fallback when the cmux enable flags are set.
6. Run the bundled smoke tests after installer changes.
7. Only use the local `templates/` or `scripts/install_repo_local_autopilot.py` when the user explicitly asks for the legacy Claude repo-local installer.

## Verification

Inspect the managed home hooks, bundled support files, and any repo-local overrides:

```text
~/.codex/hooks.json
~/.codex/hooks/cmux-stop-dispatch.sh
~/.codex/hooks/managed-session-start.sh
~/.codex/hooks/autopilot-stop.sh
~/.codex/hooks/session-start.sh
~/.codex/autopilot/autopilot-reset.sh
~/.codex/autopilot/hooks/cmux-autopilot-stop-core.sh
~/.codex/autopilot/hooks/cmux-session-start-core.sh
~/.codex/skills/autopilot_reset/SKILL.md
.codex/hooks/autopilot-stop.sh
.codex/hooks/session-start.sh
```

Run the bundled smoke tests:

```bash
SKILL_DIR=".agents/skills/autopilot"
bash "$SKILL_DIR"/scripts/test-codex-home-hooks-install.sh
bash "$SKILL_DIR"/scripts/test-codex-home-hooks-smoke.sh
```

Check reset control directly:

```bash
AUTOPILOT_PROVIDER=codex bash "${CODEX_HOME:-$HOME/.codex}/autopilot/autopilot-reset.sh" status-all
```

## Legacy Claude bundle

Only when the user explicitly asks for Claude repo-local autopilot work, use the bundled legacy files in this skill folder:

- `templates/hooks/autopilot-keep-running.sh`
- `templates/hooks/session-start.sh`
- `templates/commands/autopilot_reset.md`
- `scripts/install_repo_local_autopilot.py`

Do not position those files as the default autopilot path for Codex.
