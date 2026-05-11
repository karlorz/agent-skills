# devsh Remote Validation

Use this checklist to validate the bundled Codex home-hook autopilot skill inside a remote devsh sandbox.

## 1. Install the skill in the sandbox

From the remote workspace root:

```bash
npx skills add https://github.com/karlorz/agent-skills/tree/main/skills/autopilot \
  --skill autopilot \
  -a codex \
  -y
```

That should create `.agents/skills/autopilot/`.

## 2. Run the bundled installer

```bash
bash .agents/skills/autopilot/scripts/install-codex-home-hooks.sh
```

## 3. Inspect the installed managed files

Verify these paths exist in the sandbox:

- `~/.codex/hooks.json`
- `~/.codex/hooks/`
- `~/.codex/autopilot/`
- `~/.codex/skills/autopilot_reset/SKILL.md`

## 4. Run the bundled tests

```bash
bash .agents/skills/autopilot/scripts/test-codex-home-hooks-install.sh
bash .agents/skills/autopilot/scripts/test-codex-home-hooks-smoke.sh
```

## 5. Verify runtime behavior

Confirm:

- `managed-session-start.sh` records `/tmp/codex-current-session-id`
- `managed-session-start.sh` records `/tmp/codex-current-workspace-root`
- `cmux-stop-dispatch.sh` falls back to the managed home autopilot hook when no repo-local override exists
- the stop hook creates `/tmp/codex-autopilot-turns-<session-id>`
- `AUTOPILOT_PROVIDER=codex bash ~/.codex/autopilot/autopilot-reset.sh status-all` reports the recorded session state

## 6. Clean up

If you only needed an isolated smoke test, remove the temporary sandbox workspace after validation.
