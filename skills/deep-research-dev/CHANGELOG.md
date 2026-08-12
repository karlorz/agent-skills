# Changelog

All notable changes to this skill are documented in this file.

## [0.1.0-dev] - 2026-08-12

- Experimental dev-lane fork of deep-research 2.4.3. Package identity renamed to `deep-research-dev` (claude + codex plugin manifests, agent frontmatter, skill frontmatter, openai.yaml display name).
- Invocation modes: `unattended` (default for agent-spawned / headless / non-TTY / `--unattended` runs — never asks questions, auto-processes with documented assumptions) vs `interactive` (user slash in attended TUI — questions only for blocking ambiguity). Unattended defaults: stdout/ephemeral unless `--vault`/`--save`; depth `default`; vault lock/publish hard 120s timeout then fail-closed stdout. New flags `--unattended` and `--depth fast|default|thorough`. Eval matrix runs cells with `--ephemeral --unattended`.
- Cheap grafts only (no Verify phase, mirror of builtin discipline at ~zero latency): untrusted-data framing on every Phase 2/4 agent prompt template; Phase 1 plans ≤4 independent questions before triage fan-out; claim caps ≤6 per question and ≤24 total with per-claim `source_type` ∈ {primary, secondary, repository, other}; report header `**Status: Verified|Partial**` with partial triggers; closing `## Coverage and uncertainty` section; deterministic `## Findings` bullet-list fallback when synthesis output is empty/invalid — never an empty report.
- Report presentation: bundled adaptive numbered topical narrative (language-adaptive labels, no filler sections) with literal unnumbered `## Freshness & Verification Status` and `## Coverage and uncertainty` audit headings; `## Sources` is an immutable source ledger of retained evidence plus material conflicts/degradations — exact URLs for external evidence, explicit local records for local evidence, stable `[S<n>]` markers (no trimming, deletion, renumbering, or concealment). New `--reuse-s-template` flag: interactive-only, structure-only reuse of a relevant S outline's section order/categories (never S facts, citations, URLs, sources, or conclusions), falling back to the bundled template when unavailable/inapplicable; disabled under `--unattended`.

## [2.4.3] - 2026-08-10

- latest-by-default source triage, grok-search freshness, and Freshness & Verification Status reporting.
