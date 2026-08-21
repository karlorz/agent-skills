# SDD Setup F2 Report: Isolation-Default & Landing-Opt-In

## Summary

Updated `/dev-loop setup` (`setup-dev-loop`) so its interview flow, recommended options, and emitted configuration blocks conform to the isolation-default and landing-opt-in design.

## Key Changes

1. **Test Contract (`scripts/test-dev-loop-release-tooling.sh`)**:
   - Replaced the single legacy F2 merge authority assert with comprehensive checks:
     - Heading: `**Section F2 — Isolation and merge landing.**`
     - Isolation recommended option: `Isolate (recommended)`
     - Landing recommended option: `PR from feature branch (recommended)`
     - Default YAML emission: `allow_local_merge: false`
     - Default YAML emission: `worktree_policy:` with `enabled: true`
     - Local-merge option: `Attended local-merge menu`
     - Name distinction: `auto_merge` is GitHub and `allow_local_merge` is local finishing
     - Not-contains assertion for deprecated phrase: `direct push on the release branch, PR on feature branches`

2. **Skill Definition (`skills/dev-loop/skills/setup-dev-loop/SKILL.md`)**:
   - **Section F2 Rewrite**:
     - Retitled to **Section F2 — Isolation and merge landing.**
     - Explainer distinguishing isolation from landing and clarifying `auto_merge` (GitHub) vs `allow_local_merge` (local finishing).
     - **Question 1 (Isolation)**: Proposes `Isolate (recommended)` (`worktree_policy.enabled: true`) vs `Work in place` (`worktree_policy.enabled: false`). Emits default `worktree_policy: { enabled: true }`.
     - **Question 2 (Landing)**: Proposes `PR from feature branch (recommended)` (`strategy: repo-policy`, `allow_local_merge: false`, `auto_merge: false`), `Attended local-merge menu` (`strategy: repo-policy`, `allow_local_merge: true`, `auto_merge: false`), `PR required`, and `PR with approved auto-merge`.
     - Retained default `merge_policy` YAML emission block and clarified parameter update rules.
   - **Section 3 (Confirm and write)**:
     - Updated section listing to include "isolation and merge landing".
   - **Section 5 (Done)**:
     - Updated bullet to reflect emission of both `worktree_policy` and `merge_policy`, noting isolation is default on and landing is default PR unless the local-merge menu is chosen.

## Test Verification

- `scripts/test-dev-loop-release-tooling.sh`: Verified RED on initial test updates, then GREEN after SKILL.md updates (all 66 release tooling assertions and unit checks passing).
- `scripts/test-plugin-metadata.sh`: All 4 checks passing (0 failed).
