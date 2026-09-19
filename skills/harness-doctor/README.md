# harness-doctor

Read-only audit of Claude, Grok, Codex, and Cursor harnesses. It reports unused
skills, cold plugins, exact duplicate always-loaded files, hook cost, and
context budget. It never disables plugins, deletes files, or widens permissions.

## Install

```bash
claude plugin install harness-doctor@karlorz-agent-skills
codex plugin add harness-doctor@karlorz-agent-skills --json
```

Cursor: install `harness-doctor` from the `karlorz-agent-skills` user marketplace.
This plugin is opt-in and is not part of the grok-build-harness companion set.

## Run

```bash
python3 scripts/harness-doctor.py --harness all
python3 scripts/harness-doctor.py --harness claude --json --days 30 --limit 50
```

`--home` is for isolated fixtures. Live audits use the real home directory and
still write nothing.

Grok `/learn` is the qualitative unused-skill follow-up. This skill does not
launch it.

## License

MIT
