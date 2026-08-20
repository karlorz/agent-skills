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
- **When not to use D**: for a single latest-version / one-URL fact or quick
  factual lookup, prefer `/grok-search` (or the grok-search MCP) instead of D.
  Use D when requiring a Status/ledger/Coverage report, multi-claim comparison,
  or vault persistence. If D is invoked anyway, it runs the full orchestrator
  without skipping.

## Report presentation (output contract)

D composes reports from a **bundled general template**
(`references/report-presentation-template.md`). Every report begins with an
exact status line, a localized H1 title, an evidence-cutoff/verification/scope
block, and a compact topic map. The narrative then uses sequential **plain
ASCII ordinal** H2 prefixes (`## 1. <title>`, `## 2. <title>`, …) in **every
report language** — only narrative title text localizes; ordinal prefixes never
localize. The four fixed audit headings (`## Freshness & Verification Status`,
`## Verification Methods`, `## Sources`, `## Coverage and uncertainty`) stay
unnumbered and exact. By default D performs no S report search or copy — the
bundled template is always the base.

- Keep layers concise: TL;DR has only decision-relevant facts; the narrative
  explains a fact once; dates live in one canonical timeline table; Mermaid is
  optional and visual-only; freshness is an audit; Coverage contains only
  classifications, gaps, degradations, and dropped items.
- `## Sources` is an **immutable source ledger** of retained evidence plus
  material conflicts/degradations — not unused search results. Every external
  row declares `direct-fetch` or `search-summary only`; the latter is repeated
  with its `[S<n>]` identifier in Coverage. The four linter-facing tokens
  `direct-fetch`, `search-summary only`, `local-record:`, and
  `retained-without-citation` remain literal English labels in every report
  language; only their surrounding explanation localizes. Local evidence uses
  `local-record:` and either lives under the ignored run artifact directory or
  includes a `sha256=<64-hex-content-hash>`. Rows are stable: no trimming,
  deletion, renumbering, or concealment of material conflicts. Each row is
  cited or explicitly `retained-without-citation`.
- `scripts/lint-report.py` deterministically validates a generated report's
  identity, heading order, ledger/citation mapping, source disclosure,
  local-record durability, cutoff, status/Coverage consistency, and prohibited
  model-narrated numeric tool counts. `smoke-ephemeral.sh` saves its `lint.json`
  alongside the raw output and records tool counts only in capture metadata.
- After lint, `scripts/repair-report-structure.py` may apply a structure-only
  repair (Status then H1, English role tokens, `local-record:` prefix) and the
  report is re-linted. Leftover errors are recorded; evidence and status are
  not rewritten.
- Daily usage is appended by `scripts/record-usage.py` to
  `~/.grok/deep-research-dev-usage/ledger.jsonl` (truncated query + hash).
  `scripts/review-usage.py` harvests that ledger plus smoke `meta.json` files
  into ignored `.superpowers/sdd/deep-research-dev-usage/reviews/`.
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
  conflicts, or a required source route failed without a substitute. In every
  report language, `Evidence gap` is the literal English classification label
  used by the deterministic linter; its explanatory text may localize.
- The fallback is structurally valid: it retains the status, H1, numbered
  Findings, audit headings, ledger, and an explicit evidence-gap Coverage
  entry rather than returning an isolated bullet list.

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

Before a checkout-local smoke, ensure `grok inspect --json` selects this
checkout's `skills/deep-research-dev/SKILL.md`; `grok plugin install "$PWD"
--trust` is the local-development install path. If another same-named plugin
wins discovery, the runner exits 3 rather than capturing the wrong version.

The script runs `grok -p "/deep-research-dev:deep-research-dev --ephemeral
--unattended <query> … ===REPORT===" -m "${MODEL:-flash-max}" --yolo
--cwd … --output-format plain` and writes `cell.md` (final report),
`cell.full.md` (full stream), `meta.json` (timestamps, process outcome, exact
observed tool counts, and fail-closed session provenance), `provenance.json`,
optional frozen `session-summary.json`, and `lint.json`. The model identity is
accepted only when one fresh decoded user-query record maps to the exact
headless prompt; its agent identity and summary hash are capture evidence, not
an eligibility filter. The runner requires a resolvable SkillWiki vault path:
install `skillwiki` or pass an existing absolute
`DEEP_RESEARCH_DEV_VAULT_ROOT` outside the artifact directory. Set
`DEEP_RESEARCH_DEV_EVIDENCE_CUTOFF=YYYY-MM-DD` to make the linter verify the
report's declared temporal cutoff against capture metadata. The runner always
performs fail-closed source selection before capture; for controlled local-plugin
runs, `DEEP_RESEARCH_DEV_PLUGIN_ROOT` optionally sets the expected absolute
plugin root. Capture refuses to run if another same-named plugin wins discovery.
Override model / cwd with `MODEL` / `SMOKE_CWD` env vars. Output defaults to the
ignored repository-local root
`.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs/` (override with
`DEEP_RESEARCH_DEV_ARTIFACT_ROOT`); after source selection succeeds, an explicit
`output-dir` inside the SkillWiki vault is rejected with exit 2 before anything
is written (`DEEP_RESEARCH_DEV_VAULT_ROOT` overrides the resolved vault root,
test-only).

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
