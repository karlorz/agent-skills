# Changelog

All notable changes to this skill are documented in this file.

## [2.5.1] - 2026-08-29

- Shorten SKILL.md descriptions to the Codex catalog budget (180-character target, CI fail above 220).

## [2.5.0] - 2026-08-22

- Unattended and interactive execution modes: unattended default for model/agent auto-invocation, headless runs, and `--unattended`; stdout default for ephemeral automation; interactive mode asks only when ambiguity is blocking.
- Depth control: `--depth fast|default|thorough` across source plans.
- Capability-adaptive execution: runs selected source plans and refinement inline in parent context when child-agent spawning is unavailable.
- Answer-critical evidence discipline: pre-identifies required external evidence, enforces claim caps (<=6 per question, <=24 total), and classifies `source_type` (primary, secondary, repository, other).
- Structured report contract: deterministic status header (`**Status: Verified|Partial**`), localized H1 title, scope/cutoff identity block, sequential plain-ASCII numbered narrative H2s (`## 1. <title>`), and four literal audit headings (`## Freshness & Verification Status`, `## Verification Methods`, `## Sources`, `## Coverage and uncertainty`).
- Immutable source ledger with stable citations, direct-fetch vs search-summary disclosure, durable local records, and topic-inherent unknown vs Evidence gap classification in Coverage.
- Built-in report tooling: deterministic pre-synthesis fallback builder (`scripts/build-fallback-report.py`), report linter (`scripts/lint-report.py`), structure repairer (`scripts/repair-report-structure.py`), candidate selector (`scripts/select-report-candidate.py`), and YAML frontmatter / Related Notes lint support.
- Thin host adapter across Claude Code and OpenAI Codex CLI/App tool mappings and sandboxes.

## [2.4.3] - 2026-08-10

- latest-by-default source triage, grok-search freshness, and Freshness & Verification Status reporting.
