# Changelog

All notable changes to this skill are documented in this file.

## [0.1.0-beta.4] - 2026-08-17

- Added a host-local daily usage ledger (`scripts/record-usage.py`) and a
  harvest review (`scripts/review-usage.py`). Interactive and unattended runs
  append one JSONL record with a truncated query, query fingerprint, and lint
  outcome; smoke cells keep writing `meta.json`. Phase 6 requires duration-s,
  lint-json, and discovered plugin-version arguments. Reviews land under ignored
  `.superpowers/sdd/deep-research-dev-usage/reviews/`. The ledger is never a
  vault page.
- Added structure-only report repair (`scripts/repair-report-structure.py`)
  after lint: insert or move the H1, prefix English role tokens, and prefix
  `local-record:`. Smoke runner applies structure-only repair before final lint
  and defaults to matrix model pin `flash-max`. Status, claims, URLs,
  Coverage, and the `## 1. Findings` fallback are unchanged. A
  **topic-inherent unknown** still does not by itself require `Partial`.
  Leftover lint errors stay on the usage record.
- Report lint (P1): skip a leading closed YAML frontmatter document and ignore
  H2s after `## Coverage and uncertainty`, so published vault query pages can
  be re-linted without failing on `title:` / `## Related Notes`.

## [0.1.0-beta.3] - 2026-08-13

- Added deterministic generated-report validation for report identity, numbered
  narrative headings, ordered audit headings, source-ledger citations, source
  access disclosure, durable local records, temporal cutoffs, and status versus
  Coverage consistency. The smoke runner persists `lint.json` and derives tool
  counts from capture metadata rather than model prose.
- Added fail-closed capture-time session provenance for one unique decoded user
  query: multiline JSONL and `<user_query>` envelopes are supported, agent
  identity is recorded rather than filtered, and the matched summary is frozen
  with a SHA-256 hash.
- Replaced the former isolated `## 1. Findings` fallback with a structurally
  valid report fallback that preserves its status, H1, audit headings, ledger,
  and explicit evidence gap.
- Added mandatory fail-closed source-selection preflight for controlled
  local-plugin smokes; `DEEP_RESEARCH_DEV_PLUGIN_ROOT` is the optional root
  override. Capture refuses to run if another same-named plugin wins discovery.
  The one 2026-08-13 live smoke at
  `.superpowers/sdd/deep-research-dev-reliability-report-lint/live-validation-20260813`
  ran the older installed beta.2 plugin and is therefore retained as provenance
  and rejected lint evidence, not as beta.3 validation.
- Refined the report template with an H1 identity block, compact navigation,
  canonical timeline table, non-duplicative layer rules, explicit
  `direct-fetch` / `search-summary only` / `local-record:` disclosure, and a
  structurally valid fallback. A primary-source-supported **topic-inherent unknown**
  **does not by itself require `Partial`**.

## [0.1.0-beta.2] - 2026-08-13

- Corrected packaged Codex discovery guidance to use the marketplace installer
  and require a new session after installation. A topic-inherent unknown
  **does not by itself require `Partial`**; the `## 1. Findings` fallback
  remains available when synthesis is empty or invalid.

## [0.1.0-beta.1] - 2026-08-13

- First marketplace-supported experimental prerelease. The root marketplace,
  Claude manifest, and Codex manifest now ship synchronized package metadata;
  the plugin remains explicitly non-production.
- Clarified `Verified` versus `Partial`: a topic-inherent unknown retained from
  primary evidence is reportable and **does not by itself require `Partial`**;
  actual evidence gaps still require `Partial`. The deterministic fallback is
  `## 1. Findings` when synthesis output is empty or invalid.
- Published Codex marketplace discovery guidance and removed the obsolete
  personal-skills installation path from the packaged release documentation.
- Hardened local D-lane evaluation provenance to decode user JSONL, record the
  matched session summary, and reject command text that only shares a query
  prefix.

## [0.1.0-dev] - 2026-08-12

- Experimental dev-lane fork of deep-research 2.4.3. Package identity renamed to `deep-research-dev` (claude + codex plugin manifests, agent frontmatter, skill frontmatter, openai.yaml display name).
- Invocation modes: `unattended` (default for agent-spawned / headless / non-TTY / `--unattended` runs — never asks questions, auto-processes with documented assumptions) vs `interactive` (user slash in attended TUI — questions only for blocking ambiguity). Unattended defaults: stdout/ephemeral unless `--vault`/`--save`; depth `default`; vault lock/publish hard 120s timeout then fail-closed stdout. New flags `--unattended` and `--depth fast|default|thorough`. Eval matrix runs cells with `--ephemeral --unattended`.
- Cheap grafts only (no Verify phase, mirror of builtin discipline at ~zero latency): untrusted-data framing on every Phase 2/4 agent prompt template; Phase 1 plans ≤4 independent questions before triage fan-out; claim caps ≤6 per question and ≤24 total with per-claim `source_type` ∈ {primary, secondary, repository, other}; report header `**Status: Verified|Partial**` with partial triggers; closing `## Coverage and uncertainty` section; deterministic `## 1. Findings` bullet-list fallback when synthesis output is empty/invalid — never an empty report.
- Report presentation: bundled language-adaptive topical narrative with sequential plain ASCII ordinal H2 headings (`## 1.`, `## 2.`, …; only narrative title text localizes, never the numbering) and no filler sections, with literal unnumbered `## Freshness & Verification Status` and `## Coverage and uncertainty` audit headings; `## Sources` is an immutable source ledger of retained evidence plus material conflicts/degradations — exact URLs for external evidence, explicit local records for local evidence, stable `[S<n>]` markers (no trimming, deletion, renumbering, or concealment). New `--reuse-s-template` flag: interactive-only, structure-only reuse of a relevant S outline's section order/categories (never S facts, citations, URLs, sources, or conclusions), falling back to the bundled template when unavailable/inapplicable; disabled under `--unattended`.
- Status semantics: a **topic-inherent unknown** explicitly left undecided by retained primary evidence is reported in Coverage and uncertainty but **does not by itself require `Partial`**; actual evidence gaps still require `Partial`.

## [2.4.3] - 2026-08-10

- latest-by-default source triage, grok-search freshness, and Freshness & Verification Status reporting.
