---
name: autopilot
description: Set up, inspect, or refresh the simple repo-local Codex autopilot bundle built around `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks/autopilot-stop.sh`, `.codex/hooks/session-start.sh`, and `.codex/skills/autopilot_reset/SKILL.md`. Use when asked to mirror the first-release `trends/.codex` design, debug repo-local Codex autopilot hooks, or keep the legacy `.claude` bundle clearly secondary.
---

# Simple Codex Autopilot

Use this skill for the simple repo-local Codex autopilot design.

## Choose the right tool

- If the user wants Codex to keep working on the current bounded task in the same session, use `$ralph-loop` instead.
- Use `$autopilot` when the user wants repo-local Codex hook wiring, unattended continuation, or the first-release `.codex` bundle refreshed.
- Treat Claude Code built-in loop features as the better default for Claude. Only use the bundled `.claude` files for explicit legacy compatibility work.

## Canonical baseline

Use `/Users/karlchow/Desktop/code/trends/.codex` as the canonical simple bundle. Mirror this layout:

- `.codex/config.toml`
- `.codex/hooks.json`
- `.codex/hooks/autopilot-stop.sh`
- `.codex/hooks/session-start.sh`
- `.codex/skills/autopilot_reset/SKILL.md`

The corresponding shared scripts live here:

- `/Users/karlchow/Desktop/code/trends/scripts/hooks/cmux-autopilot-stop-core.sh`
- `/Users/karlchow/Desktop/code/trends/scripts/hooks/cmux-session-start-core.sh`
- `/Users/karlchow/Desktop/code/trends/scripts/autopilot-reset.sh`

## Design rules

- Keep `.codex/config.toml` minimal:

```toml
[features]
codex_hooks = true
```

- Keep `.codex/hooks.json` repo-local. `SessionStart` should call `.codex/hooks/session-start.sh` and `Stop` should call `.codex/hooks/autopilot-stop.sh`.
- Keep both hook scripts as thin environment shims that resolve the repo root and `exec` the shared scripts in `scripts/hooks/`.
- Gate continuation with `CMUX_AUTOPILOT_ENABLED` so ordinary Codex sessions do not autopilot accidentally.
- Keep `autopilot_reset` minimal. It should call `AUTOPILOT_PROVIDER=codex bash "$ROOT"/scripts/autopilot-reset.sh <mode>` and should not duplicate control logic.
- Do not move the default Codex lane to managed `~/.codex/hooks.json` unless the user explicitly asks for a user-level setup.

## Procedure

1. Determine whether the user wants same-session continuation or repo-local autopilot wiring. If it is same-session continuation, switch to `$ralph-loop`.
2. For repo-local autopilot, read the five `.codex` files from the `trends` baseline before editing anything else.
3. Ensure the target repo already has the shared scripts under `scripts/hooks/` plus `scripts/autopilot-reset.sh`, or add the equivalent first.
4. Mirror the `trends` file shape and keep any edits as small as possible.
5. When the user mentions `/Users/karlchow/Desktop/code/cmux/.codex/hooks/autopilot-stop.sh`, treat that repo as a consumer of the same simple pattern, not a reason to reintroduce home-hook complexity.
6. Only use the local `templates/` or `scripts/install_repo_local_autopilot.py` when the user explicitly asks for the legacy Claude repo-local installer.

## Verification

Inspect the wired repo-local files:

```text
.codex/config.toml
.codex/hooks.json
.codex/hooks/autopilot-stop.sh
.codex/hooks/session-start.sh
.codex/skills/autopilot_reset/SKILL.md
```

Run the repo's smoke test when present:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
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
