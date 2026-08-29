# Agent Setup

If `.claude/dev-loop.config.md` is missing, copy
`.claude/dev-loop.config.example.md` to `.claude/dev-loop.config.md`.
Keep SkillWiki resolution portable: use
`knowledge_backends.skillwiki.vault: auto` so dev-loop resolves the vault with
`skillwiki path`. Hardcode an absolute vault path only for a deliberately
machine-pinned workspace.

Skill `description` fields are routing metadata for every skill we author, not marketplace-specific copy. Follow [[concepts/codex-skill-catalog-budget]]: 180-character target, CI fail above 220, unique-canonical total cap. Plugins stay installed so the agent can select them; disabling plugins is opt-in.

This repo works main-first:

- Work on `main` by default.
- Run `bash scripts/test-dev-loop-release-tooling.sh`, `bash scripts/test-plugin-metadata.sh`, `bash scripts/test-cursor-claude-plugin-exam.sh`, `bash scripts/test-cursor-github-marketplace-repin.sh`, and `bash scripts/test-dev-loop-preflight-inventory.sh`.
- Push directly to `origin/main` after local verification.
- Create a PR only if direct push conflicts, `main` moved, permissions fail, or branch protection blocks the push.
- Tag releases only after main CI passes.

## Artifact routing

- Keep versioned implementation and test **source** in this repository.
- Keep SDD task briefs, implementer reports, review packages, progress ledgers,
  raw test output, smoke transcripts, run metadata, and scorer scratch under
  `.superpowers/sdd/<work-id>/`; this path is local and ignored.
- The SkillWiki vault stores only curated, shareable knowledge and project
  process: decisions, normalized score tables, reusable lessons, and approved
  specifications. Never place raw run output or SDD handoff/report files under
  `projects/**/work/**`.
- Before any vault mutation, use the SkillWiki managed workflow and respect
  existing managed-write locks and unmerged state.

Marketplace gotcha:

- `codex plugin list` reads the root `.claude-plugin/marketplace.json`; a
  `skills/<plugin>` directory with `.codex-plugin/plugin.json` is not
  discoverable unless the root marketplace has a matching entry.
- `scripts/test-dev-loop-release-tooling.sh` enforces this inventory contract.

The ignored `.claude/dev-loop.config.md` is the local instantiated config.
Durable setup-policy changes belong in `.claude/dev-loop.config.example.md`.
