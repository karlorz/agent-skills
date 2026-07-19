# Dev Loop Status — {{project_slug}}

## Summary

- Health state: {{health_state}}
- Lifecycle state: {{lifecycle_state}}
- Next action: {{lifecycle_next_action}}
- Reason: {{reason}}
- Read-only: true (no writes executed)

`overall.state` and `overall.next_action` remain compatibility projections of
the independent health and lifecycle fields.

## Mode Parse

- Requested mode: status
- Intensity: {{intensity}}
- Preview mode: {{preview_mode}}

## Config Resolution

- Config: {{config_path}}
- release_branch: {{release_branch}}
- BACKEND_CAPS: {{backend_caps}}

## Dependency / Environment Health

- dep_status: {{dep_status}}
- effective_dep_status: {{effective_dep_status}}
- relevant_missing_optional: {{relevant_missing_optional}}
- health reasons: {{health_reasons}}
- compact_count: {{compact_count}}
- skill cache: {{skill_cache_state}}

## Claimable Work Preview

{{claimable_section}}

## What `/dev-loop` Would Do Next

- Would pick: {{would_pick}}
- Pipeline: {{pipeline_steps}}
- Merge route: {{merge_strategy}} — {{merge_route_reason}}
- Auto-merge eligible: {{auto_merge_eligible}}
- Failed auto-merge gates: {{auto_merge_failed_gates}}

## Blockers

{{blockers_section}}

## Recommendations

{{recommendations_section}}
