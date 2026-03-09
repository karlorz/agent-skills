---
name: autopilot
description: Install a repo-local Claude autopilot bundle into the current repository or an explicitly provided target repository. Use when asked to set up repo-local autopilot hooks, install autopilot into `.claude/`, or reset a repo's local autopilot workflow.
---

# Repo-local Autopilot

Install the Claude autopilot bundle into a target repository's local `.claude/` directory.

## What this installs

Running the installer writes these repo-local files into the target repository:

- `.claude/hooks/autopilot-keep-running.sh`
- `.claude/hooks/session-start.sh`
- `.claude/commands/autopilot_reset.md`
- `.claude/settings.json` patched to wire the repo-local hooks

The install is repo-local by design. It does not depend on `~/.claude/` and should not install or update global Claude settings.

## Default target

If you do not pass a target path, the installer uses the current working directory.

## Explicit target repo

Use `--target-repo /absolute/or/relative/path` to install into another repository.

## Installer entrypoint

Resolve the installer path in this order:

```bash
if [ -f "skills/autopilot/scripts/install_repo_local_autopilot.py" ]; then
  INSTALLER_PATH="skills/autopilot/scripts/install_repo_local_autopilot.py"
elif [ -f "agent-skills/skills/autopilot/scripts/install_repo_local_autopilot.py" ]; then
  INSTALLER_PATH="agent-skills/skills/autopilot/scripts/install_repo_local_autopilot.py"
elif [ -f "scripts/install_repo_local_autopilot.py" ]; then
  INSTALLER_PATH="scripts/install_repo_local_autopilot.py"
else
  INSTALLER_PATH="$HOME/.agents/skills/autopilot/scripts/install_repo_local_autopilot.py"
fi
```

Install into the current repo:

```bash
python3 "$INSTALLER_PATH"
```

Install into another repo:

```bash
python3 "$INSTALLER_PATH" --target-repo /path/to/repo
```

## Installed settings behavior

The installer safely updates `.claude/settings.json` to:

- append a repo-local `SessionStart` hook pointing to `"$CLAUDE_PROJECT_DIR"/.claude/hooks/session-start.sh`
- prepend a repo-local `Stop` hook pointing to `"$CLAUDE_PROJECT_DIR"/.claude/hooks/autopilot-keep-running.sh`
- preserve unrelated hooks such as `bun-check.sh` and `codex-review.sh`
- avoid duplicate autopilot entries on re-run
- set default env values only when missing:
  - `AUTOPILOT_KEEP_RUNNING_DISABLED=0`
  - `CLAUDE_AUTOPILOT_MAX_TURNS=20`

## Reset and stop controls

After installation, use the repo-local command:

- `/autopilot_reset` to reset the current session turn counter
- `/autopilot_reset stop` to stop autopilot on the next turn
- `/autopilot_reset status` to inspect the current session
- `/autopilot_reset status-all` to inspect all tracked sessions

That reset control is installed into the target repo as `.claude/commands/autopilot_reset.md`.

## Validation checklist

After install, verify:

1. The repo contains the installed `.claude/hooks/` and `.claude/commands/` files.
2. `.claude/settings.json` points to repo-local hook paths.
3. Re-running the installer does not duplicate hook entries.
4. The hook scripts are executable.
5. Unrelated existing hooks remain intact.
6. Autopilot runtime files appear under `/tmp/claude-autopilot-*` when the hooks run.
7. Invalid target `.claude/settings.json` files fail with a clear error instead of being overwritten.

See `references/devsh-testing.md` for a remote sandbox validation workflow.
