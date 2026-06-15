# Agent Setup

If `.claude/dev-loop.config.md` is missing, copy
`.claude/dev-loop.config.example.md` to `.claude/dev-loop.config.md`.
Keep SkillWiki resolution portable: use
`knowledge_backends.skillwiki.vault: auto` so dev-loop resolves the vault with
`skillwiki path`. Hardcode an absolute vault path only for a deliberately
machine-pinned workspace.

This repo works main-first:

- Work on `main` by default.
- Run `bash scripts/test-dev-loop-release-tooling.sh` and `bash scripts/test-dev-loop-preflight-inventory.sh`.
- Push directly to `origin/main` after local verification.
- Create a PR only if direct push conflicts, `main` moved, permissions fail, or branch protection blocks the push.
- Tag releases only after main CI passes.

Marketplace gotcha:

- `codex plugin list` reads the root `.claude-plugin/marketplace.json`; a
  `skills/<plugin>` directory with `.codex-plugin/plugin.json` is not
  discoverable unless the root marketplace has a matching entry.
- `scripts/test-dev-loop-release-tooling.sh` enforces this inventory contract.

The ignored `.claude/dev-loop.config.md` is the local instantiated config.
Durable setup-policy changes belong in `.claude/dev-loop.config.example.md`.
