# Changelog

All notable changes to this skill are documented in this file.

## [1.26.33] - 2026-08-21

- `/dev-loop setup` Section F2 now interviews isolation and landing separately. Recommended defaults: isolate on (`worktree_policy.enabled: true`) and PR from a feature branch (`allow_local_merge: false`). Offers an attended local-merge menu for owned repos. No longer recommends direct push on the release branch.

## [1.26.32] - 2026-08-21

- Attended local-merge (finishing menu option 1) is refused when `merge_policy.strategy` is `pull-request`; stay on the feature-branch PR route instead of checking out `release_branch`.

## [1.26.31] - 2026-08-21

- EXECUTE isolates into a git worktree by default (`worktree_policy.enabled` absent → true). MERGE landing stays PR+CI unless `merge_policy.allow_local_merge` is true; attended sessions then get the finishing menu (local merge, PR, keep). Status previews isolation and landing independently. Write-preflight allows post-merge push on the release branch only with `--landing-route local-merge-then-push`. Opt out of isolation with `worktree_policy.enabled: false`. `auto_merge` remains GitHub PR auto-merge.

## [1.26.30] - 2026-08-10

- bump-version.sh maintains CHANGELOG.md per skill instead of inserting v<semver>: markers into description fields. Descriptions simplified to stable 50-200 char text. Version markers migrated from descriptions to CHANGELOG.md files.

## [1.26.29] - 2026-08-10

- bump-version.sh maintains CHANGELOG.md and syncs manifest descriptions; version markers removed from description fields in favor of stable description text.

## [1.26.28] - 2026-08-10

- dependency diagnosis probes Grok plugin cache paths and reports installed_via; claimability lifecycle distinguishes planned/claimable/waiting; research ranking separates project-owned from vault-global findings; provenance audit clarifies repo-relative sources; operator post-release verification checklist with in_sync/stale_session/payload_drift/manifest_mismatch/workflow_delivery_mismatch/unknown_host verdicts.

## [1.26.27] - 2026-08-10

- config-lint verifies publish_via: ci-tag-trigger against actual GitHub workflow triggers; managed vault auto-commit in SAVE step 7 uses path-scoped git staging instead of broad git add -A, preserving unrelated dirty files.

## [1.26.25] - 2026-08-10

- adaptive native/guided/full workflow profiles with explicit-only full activation, fail-closed policy resolution, and provider-independent pipeline selection; preserves immutable plugin payload/version enforcement, exact host-aware cache diagnosis, platform-correct fresh-session recovery, deterministic write preflight, and typed verification dispatch.

## [1.26.24] - 2026-08-10

- planning and decision agents inherit the invoking parent model while research and mechanical workers remain on Sonnet.

## [1.26.22] - 2026-08-10

- schema-backed YAML config parsing replaces regex flatteners with a Python/PyYAML bridge, shared Node adapter, nested deep-merge, source-line provenance, and fail-closed diagnostics for status/lint/migrate.

## [1.26.21] - 2026-08-10

- status separates health from lifecycle state.

## [1.26.18] - 2026-08-10

- separate CI discovery and health from merge authority, with repo-policy merge strategy, explicit per-work-item auto-merge approval, and exact healthy-check enforcement.

## [1.26.17] - 2026-08-10

- preflight-inventory performance (lane short-circuits, skip validate on done, ready/active aliases, all-projects capture single-pass).

## [1.26.16] - 2026-08-10

- hide dev-loop companion helpers from user command surfaces; standardize /dev-loop and $dev-loop mode entrypoints.

## [1.26.15] - 2026-08-10

- sdd-execute-worker adapter for superpowers:subagent-driven-development EXECUTE step.

## [1.26.14] - 2026-08-10

- /dev-loop dashboard mode dispatch.
