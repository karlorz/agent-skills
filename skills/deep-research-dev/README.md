# deep-research-dev

**EXPERIMENTAL dev-lane fork** of the production `deep-research` skill (base
v2.4.3), built for the deep-research eval matrix. **Not for production use.**
This plugin is **not listed on the marketplace** — there is deliberately no
entry in the root `.claude-plugin/marketplace.json`; install it by path only.

## What differs from production

- **Unattended-first invocation policy**: agent-spawned / headless / non-TTY /
  `--unattended` runs never ask questions, auto-process with documented
  assumptions, and default to **stdout / ephemeral** output unless
  `--vault` / `--save` is passed explicitly.
- **Cheap grafts only** (no builtin-style Verify phase): untrusted-data framing
  on agent prompts, ≤4-question plan, claim caps (≤6/question, ≤24 total) with
  `source_type`, `**Status: Verified|Partial**` header + `## Coverage and
  uncertainty` section, deterministic findings fallback.
- New flags `--unattended` and `--depth fast|default|thorough` on top of the
  2.4.3 flag set (`--ephemeral`, `--save`, `--vault`, `--no-refine`, …).

Full behavior lives in `skills/deep-research-dev/SKILL.md`; version history in
`CHANGELOG.md`.

## Install (local only)

```bash
grok plugin install /path/to/agent-skills/skills/deep-research-dev --trust
```

Slash form: `/deep-research-dev:deep-research-dev`. On Codex, discovery is via
`~/.agents/skills/` (see `references/codex-tools.md`).

## Eval / smoke

The eval matrix drives cells with `--ephemeral --unattended` so a run completes
end-to-end with zero questions. One-off headless smoke from the plugin root:

```bash
bash scripts/smoke-ephemeral.sh "skillwiki CLI latest version" [output-dir]
```

The script runs `grok -p "/deep-research-dev:deep-research-dev --ephemeral
--unattended <query> … ===REPORT===" -m "${MODEL:-deepseek-v4-flash}" --yolo
--cwd … --output-format plain` and writes `cell.md` (final report),
`cell.full.md` (full stream), and `meta.json` (duration_s, exit_code, model,
cwd, timestamps) beside the cell. Override model / cwd with `MODEL` /
`SMOKE_CWD` env vars. Output defaults to the ignored repository-local root
`.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs/` (override with
`DEEP_RESEARCH_DEV_ARTIFACT_ROOT`); an explicit `output-dir` inside the
SkillWiki vault is rejected with exit 2 before anything is written
(`DEEP_RESEARCH_DEV_VAULT_ROOT` overrides the resolved vault root, test-only).

## Docs

- Execution artifacts are local-only: `.superpowers/sdd/deep-research-dev-eval-matrix/`.
  The linked vault work item contains only the curated suite, rubric, matrix,
  policy, and lessons; it does not store raw cells or SDD handoffs.
- Wiki work item (vault-relative):
  `projects/agent-skills/work/2026-08-11-deep-research-dev-eval-matrix/` —
  `invocation-and-smoke-harness-policy.md`, `time-vs-accuracy-and-graft-intent.md`,
  `smoke-notes.md`.

## License

MIT
