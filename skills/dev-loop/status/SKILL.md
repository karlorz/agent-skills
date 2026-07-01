---
name: status
description: >
  Companion prompt for dev-loop read-only status mode. Explains what the next
  cycle would do without vault/git/PR/release writes. Invoked via /dev-loop
  status or /dev-loop doctor [high] [--json] [--preview-mode …]. Works when
  knowledge_layer is none; does not spawn REFRESH doctor-worker.
---

# Dev-Loop Status Mode

Operator observability for a complex orchestration skill: **preview only**, no writes.

## Invocation

Parent `dev-loop` sets `MODE = status` when args contain `status` or `doctor` (alias).
`doctor` here is **not** REFRESH `doctor-worker` — status reads
`~/.claude/dev-loop/last-doctor.json` when present.

```
/dev-loop status
/dev-loop status high
/dev-loop doctor
/dev-loop status --json
/dev-loop status --preview-mode investigate
/dev-loop status --preview-mode investigate --orchestration goal
```

## Pipeline

1. **REFRESH (read-only subset)** — config, `BACKEND_CAPS`, vault path, caps previews.
2. **PROBE** — `node skills/dev-loop/scripts/dev-loop-status.js` (see flags below).
3. **REPORT** — `dev-loop-status.v1` JSON + Markdown under `.claude/dev-loop/status/`
   (gitignored). Use `--no-write` for stdout-only.
4. **EXIT** — before WORK, SPEC, PLAN, EXECUTE, REVIEW, MERGE, SAVE, PUSH, DEPLOY.

Optional isolation: `dev-loop:status-worker` per `agents/status-worker.md`.

## CLI flags (helper)

| Flag | Purpose |
|------|---------|
| `--repo <path>` | Project repo (required) |
| `--format markdown\|json\|both` | Output (default both) |
| `--no-write` | No files under `.claude/dev-loop/status/` |
| `--intensity normal\|high` | Idle / deep-research preview |
| `--preview-mode core\|prep\|investigate\|status` | Simulated next mode |
| `--orchestration attended\|goal` | Unattended `/goal` readiness simulation |
| `--vault <path>` | Vault override |
| `--project <slug>` | Slug override |

## HUD / statusline

Read-only one-liner for ccstatusline, tmux, or shell polls (newest `*-status.json` under
`.claude/dev-loop/status/`, or `--probe` to refresh without writing files):

```bash
node skills/dev-loop/scripts/dev-loop-status-hud.js --repo .
node skills/dev-loop/scripts/dev-loop-status-hud.js --repo . --format json
node skills/dev-loop/scripts/dev-loop-status-hud.js --repo . --probe --project <slug>
```

Doctor compact HUD (separate): `~/.claude/dev-loop/last-doctor.json` from REFRESH doctor-worker.

## Related read-only helpers

- **Config lint:** `/dev-loop config-lint` → `dev-loop-config-lint.js`
- **Config migrate:** `dev-loop-config-migrate.js --repo .` (vault alias advisor)
- **One work item:** `dev-loop-why-skipped.js --project <slug> --work <folder>`

## Hard deny-list

No work-item creation, spec/plan edits, retros, `git commit`/`push`, PRs, deploy,
`bump_script`, tags, or vault SAVE/MERGE. Classify errors as `blocked`, `degraded`, or
`info` — do not swallow.

Full controller contract: parent `skills/dev-loop/SKILL.md` § Status pipeline.