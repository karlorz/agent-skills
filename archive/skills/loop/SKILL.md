---
name: loop
description: Schedule recurring Codex prompts as fresh background runs using user-scope scheduler backends. Use when the user wants cron-like repeated checks, reminders, status polling, or periodic command execution outside the active TUI session. Do not use this for same-session continuation.
allowed-tools:
  - Bash
---

# Loop Scheduler

Use this skill for a separate scheduler lane. Each execution starts a fresh
`codex exec` run from an OS scheduler. It does not re-enter the currently open
interactive Codex TUI session.

It is not a same-session continuation tool, and it should never install or
modify Stop hooks.

If the user asks for "Claude Code `/loop` but in the same live session", be
explicit: Codex does not expose that primitive here. Do not pretend this skill
provides same-session scheduled-task behavior.

## What this skill is for

Use `$loop` or `/loop` when the user wants:

- a recurring check such as `check the deploy every 10m`
- a periodic slash-like workflow such as `/standup` or `/babysit-prs`
- a scheduler-style task list with add/list/remove/run/logs/status controls
- background repetition that can survive after the current interactive turn ends

Do not use this skill when the user wants:

- the same live TUI session or same conversation to be resumed later
- immediate same-turn continuation
- "keep working until done"
- a completion promise loop

Those cases are not handled by this skill.

## User-scope install

Install the skill bundle into `~/.codex/skills/loop` with:

```bash
bash scripts/install-user-scope.sh
```

Optional flags:

- `--codex-home /absolute/path/to/.codex`
- `--mode copy|symlink`

This installs the skill bundle only. It does not register any scheduled jobs
and does not touch Stop hooks.

## Current scope

The implementation is now user-scope and backend-aware:

- default state root: `~/.codex/loop-scheduler/`
- persistent registry: `~/.codex/loop-scheduler/jobs.json`
- launcher scripts: `~/.codex/loop-scheduler/launchers/`
- logs: `~/.codex/loop-scheduler/logs/`
- registry writes are serialized with a filesystem lock under the state dir
- scheduled execution launches fresh agent sessions instead of resuming the
  live interactive turn
- this is an OS-scheduler approximation, not a Codex-native session scheduler
- default command template targets Codex, but the runner is overridable with
  `LOOP_COMMAND_TEMPLATE` for other agent CLIs
- supported backends:
  - macOS: `launchd`
  - Linux: `cron`
  - Windows-compatible shells: Task Scheduler via `schtasks`
- safe validation path: use `--dry-run` and `LOOP_*` env overrides
- automated checks: `test-parse-request.sh`, `test-scheduler.sh`,
  `test-install-user-scope.sh`

## User surface

Shorthand schedule mode:

```text
$loop 5m check the deploy
$loop /standup 1
$loop check the deploy every 20m
/loop 5m check the deploy
```

These examples create scheduled jobs outside the current interactive session.
They do not keep the same TUI conversation alive.

Management mode:

```text
$loop list
$loop remove loop-1742562000-a1b2c3
$loop run loop-1742562000-a1b2c3
$loop logs loop-1742562000-a1b2c3
$loop status
```

Parser helper:

```bash
python3 scripts/parse-request.py --request "RAW REQUEST" --pretty
```

## Procedure

1. Resolve the current workspace path first.
2. Parse the request first with:

```bash
python3 scripts/parse-request.py --request "RAW REQUEST"
```

3. Read the JSON fields:
   - `action`
   - `interval`
   - `prompt`
   - `job_id`
   - `run_now`
   - `dry_run`
4. Route by `action`:
   - `add` -> `schedule-add.sh`
   - `list` -> `schedule-list.sh`
   - `remove` -> `schedule-remove.sh`
   - `run` -> `schedule-run.sh`
   - `logs` -> `schedule-logs.sh`
   - `status` -> `schedule-status.sh`
5. For `add`, trust the parser output instead of re-deriving the interval by hand.
   The parser currently supports:
   - leading interval tokens such as `5m /babysit-prs`
   - trailing `every ...` clauses such as `check the deploy every 20m`
   - word units such as `every 5 minutes`
   - `/loop` and `$loop` prefixes
   - default interval fallback to `10m`
   - management commands such as `list`, `status`, `remove <job-id>`, `run <job-id>`, and `logs <job-id>`
   - modifier extraction for `dry-run` and `do not run now`
6. Prefer `--dry-run` when validating or when working in a temp environment.
   It previews the generated job metadata without mutating scheduler state.

## Required commands

Add a recurring job:

```bash
bash scripts/schedule-add.sh \
  --workspace "/absolute/path/to/workspace" \
  --interval "10m" \
  --prompt "check the deploy"
```

Recommended parse-and-add flow:

```bash
PARSED="$(python3 scripts/parse-request.py --request "check the deploy every 20m")"
INTERVAL="$(jq -r '.interval' <<<"$PARSED")"
PROMPT="$(jq -r '.prompt' <<<"$PARSED")"
RUN_NOW="$(jq -r '.run_now' <<<"$PARSED")"
DRY_RUN="$(jq -r '.dry_run' <<<"$PARSED")"

CMD=(bash scripts/schedule-add.sh --workspace "/absolute/path/to/workspace" --interval "$INTERVAL" --prompt "$PROMPT")
if [[ "$RUN_NOW" == "false" ]]; then
  CMD+=(--no-run-now)
fi
if [[ "$DRY_RUN" == "true" ]]; then
  CMD+=(--dry-run)
fi
"${CMD[@]}"
```

Management:

```bash
bash scripts/schedule-list.sh
bash scripts/schedule-remove.sh --job-id "loop-..."
bash scripts/schedule-run.sh --job-id "loop-..."
bash scripts/schedule-logs.sh --job-id "loop-..."
bash scripts/schedule-status.sh
```

## Environment overrides

The scripts support these overrides for testing and isolation:

- `LOOP_STATE_DIR`
- `LOOP_LOG_DIR`
- `LOOP_LAUNCHERS_DIR`
- `LOOP_PLIST_DIR`
- `LOOP_JOBS_FILE`
- `LOOP_BACKEND`
- `LOOP_COMMAND_TEMPLATE`
- `LOOP_AGENT_BIN`
- `LOOP_AGENT_EXEC_ARGS`
- `LOOP_CODEX_BIN`
- `LOOP_CODEX_EXEC_ARGS`
- `LOOP_DISPATCH_INTERVAL_SECONDS`
- `LOOP_LOCK_TIMEOUT_SECONDS`
- `LOOP_LOCK_STALE_SECONDS`

These are especially useful for dry-run tests in a temp directory.

## Notes

- Scheduled jobs create fresh Codex executions. They do not resume the same live
  interactive turn.
- `$loop` is a scheduler surface, not a Stop-hook continuation surface.
- same-session continuation is currently not published here as a shared skill;
  do not promise it through `$loop`
- if the user asks for same-session looping, be explicit that `$loop` is not
  equivalent to Claude's session-scoped scheduled tasks
- cmux autopilot also uses Stop hooks, so `loop` must stay separate from that
  channel.
- Registry writes are lock-protected so concurrent add/run/remove flows do not
  clobber `jobs.json`.
- Per-job run locks prevent overlapping scheduled executions for the same job.
- Parser coverage is deterministic only for the supported shorthand and command
  patterns above. If a request is highly conversational, parse it with
  `parse-request.py` first and inspect the JSON before scheduling anything live.
- Keep `$loop` separate from repo-local autopilot and other Stop-hook designs.
