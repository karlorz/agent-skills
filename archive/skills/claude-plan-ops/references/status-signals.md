# Status Signals

## Strong Implemented Signals

- `status: implemented|merged|deployed|done|completed`
- `merged to main`
- `implemented and deployed`
- `fix has been merged`

## Pending Signals

- `next steps`
- `follow up`
- `blocked`
- `todo`
- `pending`
- `in progress`
- `to be implemented`
- Any unchecked checklist item `- [ ]`

## Conflict Signals

- `needs deployment`
- `verification in progress`
- `needs revert`

## GitHub Verification

When both repo and PR are known:

```bash
gh pr view <pr> --repo <owner/repo> --json state,mergedAt
```

Interpretation:

- `mergedAt` present: merged
- state `OPEN`: not archiveable
- state `CLOSED` with no `mergedAt`: not archiveable

## Scoped Repo Inference

When a plan contains `PR #N` but no repo:

1. Iterate scoped repos from `planctl.json` (`repo_scope`).
2. Query each repo:
   `gh pr view <pr> --repo <owner/repo> --json number,state,mergedAt,url,title`
3. Outcomes:
   - One match: repo is inferred (`repo_source=inferred_scope`)
   - Multiple matches: keep `review_needed` (`pr_ambiguous_across_scope`)
   - No match: keep `review_needed` (`pr_not_found_in_scope`)

This inference is deterministic and can participate in normal archive gates.

## PR Mention Role Classification

PR number mentions (`PR #N`) are classified using local context (±80 chars):

- Primary candidates:
  - line starts with `Fix #N` or `PR #N`
  - phrases like `this plan is PR #N`
- Reference candidates:
  - `PR #N fixed`
  - `after PR #N`
  - `based on PR #N`
  - `similar to PR #N`
  - `follow-up to PR #N`
  - `already fixed in PR #N`
  - `previous PR #N`
  - `related PR #N`

Reference-only mentions are not used as deterministic primary PR assignment.

## Fuzzy PR Review Matching

Fuzzy matching uses scoped repos and compares plan text with:

- PR title
- PR body
- PR commit messages

Scoring:

- `coarseScore = 0.60*titleScore + 0.40*bodyScore`
- `confidence = 0.45*titleScore + 0.35*bodyScore + 0.20*commitScore`

Threshold:

- default `0.72`
- candidates below threshold are hidden

Interpretation bands:

- `>= 0.82`: strong
- `0.72-0.81`: medium
- `< 0.72`: suppressed by default

Fuzzy candidates are advisory only and must never be used as auto-archive authority.

## Semantic Override (Strict)

When deterministic primary PR is unresolved or scope-inferred, semantic matching may override to a better PR candidate only if all gates pass:

- `planCoverage >= 0.90`
- `bodyDice >= 0.65`
- `confidence >= 0.60`
- `planCoverage margin >= 0.20` vs second candidate (if any)
- candidate repo is inside configured scope
- candidate PR payload is valid

Decision matrix:

- Gate pass + deterministic source protected (`frontmatter`, `url`, `explicit_text`): no override.
- Gate pass + deterministic source weak/unresolved: apply override (`primaryPrSource=semantic_override`).
- Any gate fail: keep deterministic result and surface diagnostics.

Archive safety for semantic-primary:

- semantic override must be applied and gate must pass
- PR must be merged (GitHub check)
- all normal archive gates still pass (score/cooldown/no pending/no conflicts/no unchecked)

## Final Status Buckets

- `archive_candidate`
- `follow_up`
- `active`
- `review_needed`

## Archive Gates

A file is archiveable only when all are true:

1. `status == archive_candidate`
2. `score >= min_score` (default `85`)
3. `age_days >= cooldown_days` (default `7`)
4. no unchecked checklist
5. no pending markers
6. no conflict markers
7. if PR and repo are present with GitHub checks enabled, PR must be merged

Fuzzy-only candidates do not satisfy archive gates.
