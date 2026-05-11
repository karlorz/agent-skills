---
name: autopilot_reset
description: Use when the user asks for `$autopilot_reset` to inspect, stop, reset, or debug the latest recorded global Codex autopilot session from Codex. Uses the bundled managed-home reset script behind the scenes.
args: "[status|status-all|stop|reset|all|debug-on|debug-off]"
---

# Autopilot Reset

Use this skill when the user asks for `$autopilot_reset` or wants autopilot status/control from Codex.

## Defaults

- Target: the latest recorded global Codex autopilot session
- Default mode: `reset`

## Supported modes

- `status`
- `status-all`
- `stop`
- `reset`
- `all`
- `debug-on`
- `debug-off`

## Workflow

1. Parse the requested mode.
2. If no mode is provided, use `reset`.
3. Run the bundled managed-home script:

```bash
AUTOPILOT_PROVIDER=codex bash "${CODEX_HOME:-$HOME/.codex}/autopilot/autopilot-reset.sh" <mode>
```

4. Report the script output directly and concisely.

## Examples

```bash
$autopilot_reset
$autopilot_reset status
$autopilot_reset stop
$autopilot_reset debug-on
$autopilot_reset status-all
```

## Notes

- Do not expose or ask for a `--provider` argument when using this skill. It is Codex-only.
- When multiple Codex autopilot sessions may exist, start with `status-all` before using `stop` or `reset`.
- Claude slash commands and Codex skills are different surfaces. If you need Claude autopilot control, use the shared script directly or Claude's `/autopilot_reset` command.
- The implementation lives in `~/.codex/autopilot/autopilot-reset.sh` after installation. Do not duplicate the control logic inside the skill.
