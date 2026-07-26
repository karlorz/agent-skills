---
name: claude-plan-status-review
description: Review and verify Claude plan statuses (active/follow_up/review_needed) under ~/.claude/plans by cross-checking GitHub PR state and the latest repository code, then update plan metadata and generate a prioritized status-review report. Use when active/follow_up plans may already be implemented, blocked, or obsolete and you want a recurring review loop.
---

# Claude Plan Status Review

## Quick start

1. Generate a status-review report:

   ```bash
   python3 scripts/status_review.py --out /Users/karlchow/.claude/plans/PLAN_STATUS_REVIEW.md
   ```

   Notes:
   - The report includes **Frontmatter Fixups (Copy-Paste)** for `review_needed` plans; tune with `--max-fixups`.
   - If you already wrote a scan snapshot (recommended for scheduled runs), reuse it: `--scan ~/.claude/plans/PLAN_SCAN.json`.
   - `claude-planctl` runs (scan/archive) can take a couple minutes with GitHub checks; avoid short timeouts.
   - `archive_candidate` is not the same as “eligible to archive” (check `eligibleForArchive` / `gate:*` reasons in the report).

   The report includes:
   - Plan title + any YAML frontmatter (`repo`, `status`, `pr`, `updated`, `owner`)
   - Any in-body `Status: ...` line (common in older plans)
   - Checkbox counts
   - Basic codebase verification: extracts referenced repo paths (e.g. `apps/...`) and checks if they exist on `origin/HEAD` for the local repo checkout (default `~/Desktop/code/<repo>`).
   - A full **Plan Index** section (not truncated) for keyword/topic search across all plans (title + plan path + a few extracted path tokens like `packages/<token>`).

2. Triage the report (oldest first) and update plans you touched:
   - Add/update frontmatter: `repo`, `status`, `pr`, `updated`, `owner`
   - Promote/demote: `active` ↔ `follow_up` as blockers change
   - Mark `implemented` only when you can point to merged code/PR

3. If items are implemented, hand off archiving to `claude-planctl` (dry-run first):

   ```bash
   claude-planctl archive --dry-run --cooldown-days 7 --min-score 85
   ```

## Workflow

### 1) Build a review queue

Use `claude-planctl scan` as the source of truth for classification and GitHub state:

```bash
claude-planctl scan --format table
```

Prioritize:
- Oldest `active` and `follow_up`
- Any `review_needed`
- Any plan where a linked PR is `closed`/`merged` but the plan is still `active`/`follow_up`

### 2) Verify against latest codebase

For each plan you review:
1. Identify repo + PR:
   - Prefer frontmatter `repo` / `pr`
   - Else use `claude-planctl` record fields (`repo`, `prNumber`, `prUrl`, `primaryPrSource`)
2. Validate GitHub state:
   - Prefer `claude-planctl` GitHub check results
   - When needed: `gh pr view <N> --repo <owner/repo>`
3. Validate against current code:
   - `cd` into the repo and `git fetch --all --prune`
   - Search for the plan’s key files/symbols (`rg`) to confirm whether work exists in `main`
4. Decide status:
   - `active`: still relevant + actionable now
   - `follow_up`: blocked/deferred; capture the blocker in the plan body
   - `implemented`: clearly done (usually merged PR/code on default branch)
   - `review_needed`: ambiguous; do not guess

### 3) Update plan metadata (gradual adoption)

If a plan already has YAML frontmatter, update/add fields:
- `repo: owner/repo`
- `status: active | follow_up | implemented`
- `pr: 123` (when known)
- `updated: YYYY-MM-DD`
- `owner: karlchow`

If frontmatter is missing, add it only when you are already editing the plan for a real review.

Template:

```yaml
---
repo: owner/repo
status: active | follow_up | implemented
pr: 123
updated: 2026-02-18
owner: karlchow
---
```

### 4) Archive implemented plans (conservative)

Defer to `claude-planctl` for archive moves (dry-run first, keep cooldown 7 days):

```bash
claude-planctl archive --dry-run --cooldown-days 7 --min-score 85
claude-planctl archive --apply --cooldown-days 7 --min-score 85
```

Tip: if `claude-planctl archive` says “No eligible archive candidates”, check the report for `gate:cooldown_not_met` and re-run after the cooldown window.

For archive gate logic and status signal definitions, consult:
- `/Users/karlchow/.codex/skills/claude-plan-ops/references/status-signals.md`
- `references/review-rubric.md`

## Outputs

- `scripts/status_review.py` writes a prioritized report to `PLAN_STATUS_REVIEW.md`.

Useful flags:
- `--max-items 10` to keep the report short
- `--max-fixups 10` to reduce copy-paste frontmatter suggestions
- `--limit 200` to reduce scan time
- `--index-max-keywords 3` to reduce Plan Index keyword noise per plan
- `--repo-dir owner/repo=/abs/path` to override local repo checkout paths
- `--no-github-check` to skip GitHub API checks (faster, but less accurate PR state)
- `--no-git-fetch` to skip `git fetch` (faster, less “latest-codebase” accurate)
