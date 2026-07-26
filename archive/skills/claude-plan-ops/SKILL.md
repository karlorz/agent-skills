---
name: claude-plan-ops
description: Manage Claude plan files under ~/.claude/plans across repositories with consistent scan/index/archive/restore workflows. Use when a user asks to triage, archive implemented plans, track follow-up plans, regenerate plan dashboards, or maintain plan hygiene over time.
---

# Claude PlanOps

Use `claude-planctl` as the source of truth for plan classification and archive operations.

## Runbook

1. Run `claude-planctl scan --format table` to classify plans.
2. Run `claude-planctl index` to regenerate `~/.claude/plans/PLAN_DASHBOARD.md` (includes plan titles for keyword search).
3. Run `claude-planctl archive --dry-run` to preview archive moves.
4. Review archive candidates and safety gates.
5. Run `claude-planctl archive --apply` only after review.
6. Run `claude-planctl restore --id <manifest-id>` to undo an archive move.

## Automation Snapshot (Optional)

If you run PlanOps + Status Review on a schedule, write a single scan snapshot and reuse it to keep reports consistent:

```bash
claude-planctl scan --format json --limit 500 --repo-scope-file ~/.claude/plans/planctl.json > ~/.claude/plans/PLAN_SCAN.json
```

## Dashboard Search

- Search `PLAN_DASHBOARD.md` by topic keyword to find the related plan file (titles are indexed).
- Example: `rg -n "cmux-devbox" ~/.claude/plans/PLAN_DASHBOARD.md`

## Safety Rules

- Keep `--cooldown-days` at `7` unless explicitly changed by user.
- Keep `--min-score` at `85` unless explicitly changed by user.
- Keep GitHub verification enabled by default.
- Keep fuzzy PR matching review-only. Do not use fuzzy candidates as archive authority.
- Distinguish reference mentions from primary PRs:
  - Reference cues like `after PR #N`, `PR #N fixed`, `follow-up to PR #N` are not deterministic primary matches.
  - Primary cues like `Fix #N` or `this plan is PR #N` are deterministic candidates.
- Review `primaryPrSource`, `referencedPrs`, and `semanticDecision` before archive apply.
- Do not apply archive moves in unattended workflows unless the user explicitly requests it.
- Treat `review_needed` as manual triage items; do not force archive.

## Repo Scope Config

Use `~/.claude/plans/planctl.json`:

```json
{
  "repo_scope": ["karlorz/cmux", "ptdevhk/trends"],
  "fuzzy": {
    "enabled": true,
    "range_per_repo": 200,
    "threshold": 0.72,
    "max_candidates_per_plan": 3
  }
}
```

- `repo_scope` controls deterministic PR-number inference and fuzzy corpus search scope.
- CLI override: `--repo-scope owner/repo,owner/repo`
- Config path override: `--repo-scope-file /path/to/planctl.json`

## Fuzzy Tuning

- Enable/disable: `--fuzzy-match` / `--no-fuzzy-match`
- Corpus size per repo: `--fuzzy-range 200`
- Candidate cutoff: `--fuzzy-threshold 0.72`
- Candidates shown: `--fuzzy-max-candidates 3`

Fuzzy candidates are advisory links for review; deterministic repo+PR remains authoritative.

Semantic override policy:

- Allowed only when deterministic source is not authoritative (`frontmatter`, `url`, `explicit_text` are protected).
- Gate (all required):
  - `planCoverage >= 0.90`
  - `bodyDice >= 0.65`
  - `confidence >= 0.60`
  - `coverageMargin >= 0.20`
  - candidate is in scoped repos and PR data is valid
- If applied, `primaryPrSource=semantic_override`.
- Archive is still conservative: semantic-primary plans must pass all normal archive gates and merged-PR checks.

## Metadata Adoption

For new or edited plan files, suggest optional frontmatter:

```yaml
---
repo: owner/repo
status: active | follow_up | implemented | archived
pr: 123
updated: 2026-02-07
owner: karlchow
---
```

Use gradual adoption. Do not require metadata retroactively for all files.

## Commands

```bash
claude-planctl scan --format table
claude-planctl scan --format json --limit 200
claude-planctl scan --repo-scope karlorz/cmux,ptdevhk/trends --fuzzy-threshold 0.75
claude-planctl index
claude-planctl archive --dry-run
claude-planctl archive --apply
claude-planctl restore --id <manifest-id>
```

## References

Use `/Users/karlchow/.codex/skills/claude-plan-ops/references/status-signals.md` for signal definitions and gate logic.
