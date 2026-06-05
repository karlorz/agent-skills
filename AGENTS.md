# Agent Setup

If `.claude/dev-loop.config.md` is missing, copy
`.claude/dev-loop.config.example.md` to `.claude/dev-loop.config.md`.
Adjust only local paths such as `vault` unless the project policy changes.

This repo works main-first:

- Work on `main` by default.
- Run `bash scripts/test-dev-loop-release-tooling.sh` and `bash scripts/test-dev-loop-preflight-inventory.sh`.
- Push directly to `origin/main` after local verification.
- Create a PR only if direct push conflicts, `main` moved, permissions fail, or branch protection blocks the push.
- Tag releases only after main CI passes.

The ignored `.claude/dev-loop.config.md` is the local instantiated config.
Durable setup-policy changes belong in `.claude/dev-loop.config.example.md`.
