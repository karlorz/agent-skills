---
name: autopilot
description: Set up, inspect, or refresh the generic managed Codex home-hook autopilot model built around `scripts/install-codex-home-hooks.sh`, managed `~/.codex/hooks.json`, `~/.codex/hooks/cmux-stop-dispatch.sh`, `~/.codex/hooks/managed-session-start.sh`, and optional repo-local overrides at `.codex/hooks/autopilot-stop.sh` and `.codex/hooks/session-start.sh`. Use when asked to make Codex autopilot work in any repo or arbitrary workspace, debug managed home-hook routing, refresh repo override shims, or keep the legacy `.claude` bundle clearly secondary.
---

# Managed Codex Autopilot

Use this skill for the managed Codex home-hook autopilot design with optional repo-local overrides.

## Choose the right tool

- If the user wants Codex to keep working on the current bounded task in the same session, do not route them to an archived shared same-session loop skill.
- Use `$autopilot` when the user wants managed Codex home hooks installed or refreshed, arbitrary-workspace autopilot support, or repo-local override shims inspected.
- Treat Claude Code built-in loop features as the better default for Claude. Only use the bundled `.claude` files for explicit legacy compatibility work.

## Canonical baseline

Use `/Users/karlchow/Desktop/code/cmux` as the canonical managed-home implementation. Prefer these files:

- `/Users/karlchow/Desktop/code/cmux/scripts/install-codex-home-hooks.sh`
- `/Users/karlchow/Desktop/code/cmux/.codex/hooks/cmux-stop-dispatch.sh`
- `/Users/karlchow/Desktop/code/cmux/.codex/hooks/managed-session-start.sh`
- `/Users/karlchow/Desktop/code/cmux/.codex/hooks/home-autopilot-stop.sh`
- `/Users/karlchow/Desktop/code/cmux/.codex/hooks/home-session-start.sh`
- `/Users/karlchow/Desktop/code/cmux/.codex/hooks/autopilot-stop.sh`
- `/Users/karlchow/Desktop/code/cmux/.codex/hooks/session-start.sh`
- `/Users/karlchow/Desktop/code/cmux/.codex/skills/autopilot_reset/SKILL.md`

The corresponding shared scripts live here:

- `/Users/karlchow/Desktop/code/cmux/scripts/hooks/cmux-autopilot-stop-core.sh`
- `/Users/karlchow/Desktop/code/cmux/scripts/hooks/cmux-session-start-core.sh`
- `/Users/karlchow/Desktop/code/cmux/scripts/autopilot-reset.sh`
- `/Users/karlchow/Desktop/code/cmux/scripts/agent-autopilot.sh`

## Design rules

- Keep the default Codex lane in managed `~/.codex/hooks.json`. `SessionStart` should call `~/.codex/hooks/managed-session-start.sh` and `Stop` should call `~/.codex/hooks/cmux-stop-dispatch.sh`.
- Keep the managed home entrypoints thin. They should route to workspace overrides first, then to managed home fallbacks, and only emit plain text or allow-stop when no hook exists.
- Keep `.codex/hooks/autopilot-stop.sh` and `.codex/hooks/session-start.sh` optional. Use them only when the workspace needs to override the managed home fallback.
- Keep home fallback wrappers thin. They should resolve the workspace root from recorded session workspace files or hook cwd, then `exec` the shared scripts in `scripts/hooks/`.
- Gate continuation with `CMUX_AUTOPILOT_ENABLED` or `CMUX_CODEX_HOOKS_ENABLED` so ordinary Codex sessions do not autopilot accidentally.
- Keep `autopilot_reset` minimal. It should call `AUTOPILOT_PROVIDER=codex bash "$ROOT"/scripts/autopilot-reset.sh <mode>` and should not duplicate control logic.
- Keep `autopilot_reset` default targeting on the latest recorded global Codex session. When multiple sessions may exist, direct the user to `status-all`.

## Procedure

1. Determine whether the user wants same-session continuation or managed home-hook autopilot. If it is same-session continuation only, keep working directly in the current session instead of routing to an archived shared skill.
2. Read the canonical `cmux` installer, managed entrypoints, home fallbacks, optional repo-local overrides, and shared core scripts before editing anything else.
3. Keep the managed home hooks and the generated sandbox hooks aligned. If you change installer behavior, also check the OpenAI environment bootstrap in `packages/shared/src/providers/openai/environment.ts`.
4. When a workspace needs custom routing, add or update only `.codex/hooks/autopilot-stop.sh` and `.codex/hooks/session-start.sh`. Do not require a full repo-local `.codex` bundle just to enable Codex autopilot.
5. For arbitrary workspaces with no `.codex` bundle, rely on the managed home fallback. SessionStart should still record the latest session ID and workspace-root tracking files, and Stop should still block through the home autopilot fallback when the cmux enable flags are set.
6. Only use the local `templates/` or `scripts/install_repo_local_autopilot.py` when the user explicitly asks for the legacy Claude repo-local installer.

## Verification

Inspect the managed home hooks plus any repo-local overrides:

```text
~/.codex/hooks.json
~/.codex/hooks/cmux-stop-dispatch.sh
~/.codex/hooks/managed-session-start.sh
~/.codex/hooks/autopilot-stop.sh
~/.codex/hooks/session-start.sh
.codex/hooks/autopilot-stop.sh
.codex/hooks/session-start.sh
.codex/skills/autopilot_reset/SKILL.md
```

Run the repo's smoke tests when present:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
bash "$ROOT"/scripts/test-codex-home-hooks-install.sh
bash "$ROOT"/scripts/test-codex-home-hooks-smoke.sh
bash "$ROOT"/.codex/hooks/test-cmux-stop-dispatch.sh
bash "$ROOT"/.codex/hooks/test-autopilot-stop.sh
```

Check reset control directly:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
AUTOPILOT_PROVIDER=codex bash "$ROOT"/scripts/autopilot-reset.sh status-all
```

## Legacy Claude bundle

Only when the user explicitly asks for Claude repo-local autopilot work, use the bundled legacy files in this skill folder:

- `templates/hooks/autopilot-keep-running.sh`
- `templates/hooks/session-start.sh`
- `templates/commands/autopilot_reset.md`
- `scripts/install_repo_local_autopilot.py`

Do not position those files as the default autopilot path for Codex.
