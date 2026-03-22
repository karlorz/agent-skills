---
name: loop
description: Schedule recurring Codex prompts or slash-like tasks using OS scheduler backends. Use when the user wants a Claude-like /loop behavior in Codex for repeated checks, reminders, status polling, or periodic command execution. Keep this separate from ralph-loop, which is immediate stop-hook continuation rather than time-based scheduling.
allowed-tools:
  - Bash
---

# Loop Scheduler

Use this skill for a separate Codex scheduler lane. It is not a replacement for
`$ralph-loop`.

## What this skill is for

Use `$loop` when the user wants:

- a recurring check such as `check the deploy every 10m`
- a periodic slash-like workflow such as `/standup` or `/babysit-prs`
- a scheduler-style task list with add/list/remove/run/logs/status controls

Do not use this skill when the user wants:

- immediate same-turn continuation
- "keep working until done"
- a completion promise loop

Those cases belong to `$ralph-loop`.

## Current scope

The current implementation is intentionally narrow:

- current backend: macOS `launchd`
- persistent registry: `~/.codex/loop-scheduler/jobs.json`
- registry writes are serialized with a filesystem lock under the state dir
- logs: `~/.codex/loop-scheduler/logs/`
- execution model: launches fresh `codex exec` runs
- safe validation path: use `--dry-run` and `LOOP_*` env overrides
- `--dry-run` is preview-only and does not write jobs, plists, or `launchd`
  registrations
- automated checks: `test-parse-request.sh` and `test-scheduler.sh`

Linux `crontab` and Windows Task Scheduler are design follow-ups, not current
implementation.

## User surface

Shorthand schedule mode:

```text
$loop 5m check the deploy
$loop check the deploy every 20m
$loop /standup 1
```

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
- `LOOP_PLIST_DIR`
- `LOOP_JOBS_FILE`
- `LOOP_CODEX_BIN`
- `LOOP_CODEX_EXEC_ARGS`
- `LOOP_LOCK_TIMEOUT_SECONDS`
- `LOOP_LOCK_STALE_SECONDS`

These are especially useful for dry-run tests in a temp directory.

## Notes

- Scheduled jobs create fresh Codex executions. They do not resume the same live
  interactive turn.
- Registry writes are lock-protected so concurrent add/run/remove flows do not
  clobber `jobs.json`.
- Parser coverage is deterministic only for the supported shorthand and command
  patterns above. If a request is highly conversational, parse it with
  `parse-request.py` first and inspect the JSON before scheduling anything live.
- The skill does not install itself into `~/.codex/skills`; any live mount is a
  manual symlink choice.
- Keep `$loop` and `$ralph-loop` conceptually separate in docs and behavior.
