# deep-research-dev

**EXPERIMENTAL prerelease dev-lane fork** of the production `deep-research`
skill (base v2.4.3), built for the deep-research eval matrix. **Not for production
use.** It is published through the `karlorz-agent-skills` marketplace for
controlled evaluation, but it is not a production replacement for
`deep-research`.

## What differs from production

- **Unattended-first invocation policy**: agent-spawned / headless / non-TTY /
  `--unattended` runs never ask questions, auto-process with documented
  assumptions, and default to **stdout / ephemeral** output unless
  `--vault` / `--save` is passed explicitly.
- **Cheap grafts only** (no builtin-style Verify phase): untrusted-data framing
  on agent prompts, ≤4-question plan, claim caps (≤6/question, ≤24 total) with
  `source_type`, `**Status: Verified|Partial**` header + `## Coverage and
  uncertainty` section, deterministic findings fallback.
- New flags `--unattended`, `--depth fast|default|thorough`, and the
  interactive-only `--reuse-s-template` (see Report presentation below) on top
  of the 2.4.3 flag set (`--ephemeral`, `--save`, `--vault`, `--no-refine`, …).

## Report presentation (output contract)

D composes reports from a **bundled general template**
(`references/report-presentation-template.md`): a language-adaptive numbered
topical narrative with sequential **plain ASCII ordinal** H2 heading
prefixes (`## 1. <title>`, `## 2. <title>`, …) in **every report language**
— only narrative title text localizes; ordinal prefixes never localize.
The four fixed audit headings (`## Freshness & Verification Status`,
`## Verification Methods`, `## Sources`, `## Coverage and uncertainty`)
stay unnumbered and exact. By default D performs no S report search or copy
— the bundled template is always the base.

- `## Sources` is an **immutable source ledger** of retained evidence plus
  material conflicts/degradations — not an exhaustive dump of unused search
  results. Every retained external third-party claim carries its exact URL;
  local evidence is explicitly identified as a local record, never a
  fabricated URL. Rows are stable: no trimming, deletion, renumbering, or
  concealment of material conflicts.
- `--reuse-s-template` is an explicit interactive opt-in: it may reuse only a
  relevant accessible S outline's section order/categories — **structure
  only**. It cannot copy S facts, citations, URLs, sources, or conclusions.
  If a usable S outline is unavailable or inapplicable, D falls back to its
  bundled template. The flag works only in an otherwise interactive attended
  invocation: it is disabled under `--unattended` and other
  unattended/headless/smoke modes (the invocation logic treats `--ephemeral`
  as unattended too), which always use the bundled template.
- **Status semantics:** a **topic-inherent unknown** is a requested fact that
  retained primary evidence explicitly leaves undecided. It is reported in
  Coverage and uncertainty but **does not by itself require `Partial`**.
  `Partial` remains mandatory for actual evidence gaps, including unsupported
  retained claims, missing answer-critical verification, unresolved material
  conflicts, or a required source route failed without a substitute.
- This is an output-contract change: the static tests verify the written
  instructions, but demonstrating model adherence requires a new live D
  report. The supplied finance D report predates this contract and was not
  retroactively improved.

Full behavior lives in `skills/deep-research-dev/SKILL.md`; version history in
`CHANGELOG.md`.

## Install

With the `karlorz-agent-skills` marketplace configured, install the published
experimental prerelease through the supported host installer:

```bash
codex plugin add deep-research-dev@karlorz-agent-skills --json
claude plugin install deep-research-dev@karlorz-agent-skills
```

For local development only, Grok can also install the checked-out path:

```bash
grok plugin install /path/to/agent-skills/skills/deep-research-dev --trust
```

Slash form: `/deep-research-dev:deep-research-dev`. On Codex, use the
marketplace install command above, then start a new session so the released
plugin instructions load. See `references/codex-tools.md` for platform mapping.

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
