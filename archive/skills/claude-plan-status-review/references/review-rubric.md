# Plan Status Review Rubric

Use this rubric when verifying `active` / `follow_up` plans against the latest repo state.

## Prioritization

1. `review_needed` (always manual triage)
2. Oldest `active`
3. Oldest `follow_up`
4. Any plan whose linked PR is `MERGED` or `CLOSED` but the plan status has not been updated

## Verification checklist (per plan)

1. **Find the authoritative repo/PR**
   - Prefer YAML frontmatter (`repo`, `pr`) when present.
   - Else use `claude-planctl scan` record fields (`repo`, `prNumber`, `prUrl`, `primaryPrSource`).
   - Treat `primaryPrSource=semantic_override` as usable but verify `github.state` is `MERGED`.

2. **Confirm GitHub state**
   - Prefer `claude-planctl` GitHub check output.
   - If needed: `gh pr view <N> --repo <owner/repo>`.

3. **Confirm code reality**
   - Ensure local repo is current: `git fetch --all --prune`.
   - Search for the plan’s key files/symbols and verify they exist on the default branch.
   - If the plan describes a UI/behavior, validate through the smallest repro you can (or update plan with what remains).

4. **Choose the right status**
   - `active`: actionable now; work still missing.
   - `follow_up`: blocked/deferred; write the blocker explicitly.
   - `implemented`: done (ideally evidenced by merged code/PR).
   - `review_needed`: ambiguous; do not guess.

5. **Update metadata (gradual adoption)**
   - If frontmatter exists, update `status` and `updated`.
   - If frontmatter is missing, add it only when you are already editing the plan for a real review.

## Safe defaults

- Do not archive solely from fuzzy matches.
- Do not auto-change `review_needed` without manual inspection.
- Treat `archive_candidate` as “ready soon”; archive only when `eligibleForArchive=true` and no blocking `gate:*` reasons remain (commonly `gate:cooldown_not_met`).
- Use `claude-planctl archive --dry-run --cooldown-days 7 --min-score 85` before any archive apply.
