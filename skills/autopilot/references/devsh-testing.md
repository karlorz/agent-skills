# devsh Remote Validation

Use this checklist to validate the repo-local autopilot bundle inside a remote devsh sandbox.

## 1. Confirm a Claude model

```bash
devsh models
```

Pick an available Claude model such as `claude/sonnet-4.5`.

## 2. Make the bundle available in the sandbox

The installer is self-contained, but the sandbox still needs a copy of this skill directory before it can run the installer.

One workable pattern is to copy `skills/autopilot/` into the sandbox at a path such as `/root/agent-skills/skills/autopilot`, then run the installer from there.

## 3. Create a test task

Use one of the declared test repos:

- `karlorz/testing-repo-1`
- `karlorz/testing-repo-2`
- `karlorz/testing-repo-3`

Example:

```bash
devsh task create \
  --repo karlorz/testing-repo-1 \
  --agent claude/sonnet-4.5 \
  --json \
  "Copy the bundled autopilot skill into the sandbox if needed, run its repo-local installer against this repository, verify the installed files, and report the resulting settings.json hook entries."
```

## 4. Inspect task state

```bash
devsh task status <task-id> --json
devsh task runs <task-id> --json
```

If needed, attach to the run:

```bash
devsh task attach <task-run-id>
```

## 5. Verify repo-local behavior in the sandbox

Confirm the remote repo contains:

- `.claude/hooks/autopilot-keep-running.sh`
- `.claude/hooks/session-start.sh`
- `.claude/commands/autopilot_reset.md`
- `.claude/settings.json`

Then verify:

- `session-start.sh` writes `/tmp/claude-current-session-id`
- `autopilot-keep-running.sh` creates or updates `/tmp/claude-autopilot-turns-<session-id>`
- `/autopilot_reset stop` semantics create `/tmp/claude-autopilot-stop-<session-id>`
- the install works without relying on `~/.claude`

## 6. Clean up

When finished, stop the remote task if it is still running:

```bash
devsh task stop <task-id>
```
