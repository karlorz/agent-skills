---
name: harness-doctor
description: Audit Claude, Grok, Codex, and Cursor harnesses for unused skills, cold plugins, duplicates, and context cost. Use when /harness-doctor, unused skills, or plugin recency.
---

# harness-doctor

Read-only audit. Do not disable, uninstall, delete, edit settings, or widen permissions.

## Run

From this plugin (repo checkout or installed copy):

```bash
python3 scripts/harness-doctor.py --harness all
python3 scripts/harness-doctor.py --harness claude|grok|codex|cursor
python3 scripts/harness-doctor.py --harness all --json --days 30 --limit 50
```

Installed path is next to this skill: `../../scripts/harness-doctor.py`. `--home` is for fixtures only.

## Modes

- `/harness-doctor` or `/harness-doctor all`: every detected harness.
- `/harness-doctor claude|grok|codex|cursor`: one harness.
- Print the human report unless the user asked for JSON.

## Rules

- Missing signals are `UNKNOWN`, never a guessed zero.
- Passive components (theme/output/monitor/LSP/obsidian) are not cold from zero.
- Maintenance tools (`cursor-github-marketplace-repin`, `grok-build-harness`, `host-backup-restore`) are `rare_keep`.
- Fewer than 20 sessions or under 7 days: no retirement verdict.
- Do not launch Grok `/learn`. If the collector exists, say it is the qualitative follow-up.
- Never print secrets, prompt bodies, account ids, or token-bearing URLs.
- Every disable/delete note is reversible and needs a separate attended step.

## After the report

Stop. Do not apply cleanup unless the user explicitly asks in a later turn.
