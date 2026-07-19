# Dev Loop — agent-skills Example

Copy this file to `.claude/dev-loop.config.md` in a new workspace. Keep
SkillWiki portable with `knowledge_backends.skillwiki.vault: auto`; hardcode an
absolute vault path only when a workspace is intentionally pinned to one host.
The real config file is ignored so each workspace can keep local settings
without committing them.

## Identity

```yaml
slug: agent-skills
release_branch: main
```

## Workflow Policy

```yaml
# Advisory for agents and humans. The current dev-loop engine primarily
# consumes release_branch: main; on release_branch it commits and pushes
# directly.
branch_policy:
  default_work_branch: main
  direct_push_to_release_branch: true
  pr_fallback: push_conflict_or_protection_only
  branch_protection_required: false
```

## PRD Layer

```yaml
prd_layer: superpowers
prd_pipeline: full
prd_disciplines:
  - skill: superpowers:systematic-debugging
    when: failure
    mode: reactive
```

## Knowledge Layer

```yaml
knowledge_layer: skillwiki
knowledge_backends:
  skillwiki:
    vault: auto
    cli_entry: skillwiki
```

## Interview

```yaml
interview:
  setup:
    skill: setup-dev-loop
  work_item:
    # Native interview is the implied fallback when no upgrade is installed.
    trigger: auto
    goal_override: never
```

## Code Layout

```yaml
cli_src: skills/*/SKILL.md
skills_glob: skills/*/SKILL.md
cli_entry_override:
```

## Verification

```yaml
e2e_scripts:
  - "bash scripts/test-dev-loop-release-tooling.sh"
  - "bash scripts/test-dev-loop-preflight-inventory.sh"
  - "bash scripts/test-dev-loop-status.sh"
  - "bash scripts/test-dev-loop-config-lint.sh"
  - "bash scripts/test-dev-loop-why-skipped.sh"
```

## CI

```yaml
ci_configured: true
ci_workflow: .github/workflows/ci.yml
ci_discovery: explicit
required_checks:
  - "Verify agent-skills"
branch_protection: false
```

## Merge Policy

```yaml
# CI discovery reports check health; it does not grant merge authority.
merge_policy:
  strategy: repo-policy
  auto_merge: false
  merge_method: squash
  require_work_item_approval: true
```

## Release

```yaml
bump_script: ./scripts/bump-version.sh
publish_via: ci-tag-trigger
manifests_count: 4
remote_hosts: []
release_policy:
  auto_bump: false
  channel: stable
  trigger_globs:
    - "skills/**"
    - ".claude-plugin/marketplace.json"
    - "scripts/bump-version.sh"
  skip_globs:
    - ".github/**"
    - ".claude/**"
    - "archive/**"
  tag_format: "{skill}-{version}"
  verify_after_push: true
```

## Preflight

```yaml
preflight:
  enabled: true
  default_limit: 5
  default_lanes: [work, captures, hygiene]
  require_approved_spec_and_plan: true
  unattended_not_ready_behavior: skip
  defaults:
    release_policy: "Work on main; create PR only when direct push conflicts or is blocked."
```

## Vault Sync

```yaml
vault_sync:
  peer_aware: true
  presync_skill: auto-detect
  fallback: direct_git_push
```

## Notes

```yaml
notes:
  conventions: "6 skills; version bump touches SKILL.md, marketplace.json, Claude plugin.json, and optional Codex plugin.json."
  merge_readiness: "Local tests pass, then push main. PR is fallback only."
  release_readiness: "After main CI passes, tag using {skill}-{version}; CI tag trigger publishes."
```
