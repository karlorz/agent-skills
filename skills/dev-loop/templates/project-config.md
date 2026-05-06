---
name: Dev loop project config (template)
description: Copy this file to .claude/dev-loop.config.md in your project repo, then fill in the fields below. The dev-loop skill reads this at REFRESH and uses it for every step.
type: template
---

# Dev Loop — {project-name}

> **Edit this file when porting the dev-loop to a new project.**
> Every field here replaces a hardcoded value in the engine.
> Empty fields disable the corresponding step (e.g., empty `vault` skips
> wiki-* steps; empty `e2e_scripts` skips step 8; empty `publish_via`
> skips step 9).

## Identity

```yaml
slug: <project-slug>
vault: <vault-path>            # e.g., ~/wiki, or empty to skip vault steps
release_branch: <branch-name>  # e.g., main, dev, master
```

## Code layout

Used by introspection, research agent, and trivial-cycle scoping.

```yaml
cli_src: <glob-or-path>          # e.g., packages/cli/src/commands/, src/
cli_test: <glob-or-path>         # e.g., packages/cli/test/commands/
skills_glob: <glob-or-empty>     # e.g., packages/skills/*/SKILL.md, or empty
cli_entry_override: <command>    # e.g., npx tsx packages/cli/src/cli.ts, or empty
```

If `cli_entry_override` is set, the loop uses it instead of the
installed binary when the project's CLI is part of the work.

## E2E

Each script must exit 0 to pass. Counts are NOT part of the contract —
the engine never depends on a specific assertion count.

```yaml
e2e_scripts:
  - scripts/e2e-local.sh
  - scripts/e2e-remote.sh
  - scripts/e2e-plugin.sh
```

Set to empty list `[]` to skip step 8 entirely.

## Release

```yaml
bump_script: <path-or-empty>      # e.g., ./scripts/bump-version.sh
publish_via: <mode>                # ci-tag-trigger | local | none
manifests_count: <N>               # how many manifests bump_script touches (sanity check)
remote_hosts: [<host>, ...]        # e.g., [sg01], or [] if not applicable
```

`publish_via` modes:

| Mode | Behavior |
|------|----------|
| `ci-tag-trigger` | Bump → commit → push → tag → CI publishes. Verify tag landed on remote after push. |
| `local` | Project's local release script runs on dev host (caution: interactive auth breaks /loop idempotency). |
| `none` | Skip step 9. Loop exits after E2E. |

## Notes (optional)

Free-form project-specific gotchas, compatibility notes, paths to
canonical specs, etc. The engine reads this for context but does not
parse fields.

```yaml
notes:
  canonical_spec: <path-to-spec>
  compat: <free-form>
  conventions: <free-form>
```

---

## Worked example (commented — do not activate)

<!--
slug: llm-wiki
vault: ~/wiki
release_branch: dev

cli_src: packages/cli/src/commands/
cli_test: packages/cli/test/commands/
skills_glob: packages/skills/*/SKILL.md
cli_entry_override: npx tsx packages/cli/src/cli.ts

e2e_scripts:
  - scripts/e2e-local.sh
  - scripts/e2e-remote.sh
  - scripts/e2e-plugin.sh

bump_script: ./scripts/bump-version.sh
publish_via: ci-tag-trigger
manifests_count: 6
remote_hosts: [sg01]

notes:
  canonical_spec: ~/wiki/projects/llm-wiki/history/specs/2026-05-02-llm-wiki-skill-design.md
  hermes_compat: ~/.skillwiki/.env primary, ~/.hermes/.env fallback
  conventions: 14 SKILL.md files; CLI commands paired with test files
-->
