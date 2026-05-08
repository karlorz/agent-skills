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
>
> Set `knowledge_layer: none` to run the loop without a vault or wiki —
> all knowledge steps use git-based alternatives.
>
> The knowledge layer is pluggable. Steps branch on **capabilities**, not
> backend names — adding a new backend means declaring which capabilities
> it supports in the `knowledge_backends` registry.

## Identity

```yaml
slug: <project-slug>
vault: <vault-path>            # e.g., ~/wiki, or empty to skip vault steps
release_branch: <branch-name>  # e.g., main, dev, master
```

## Knowledge layer

Controls how the loop captures, queries, and maintains project knowledge.
The `knowledge_layer` field names the primary backend; its capabilities
are resolved at REFRESH into `BACKEND_CAPS`. Steps check capability
membership instead of the backend name directly.

When `knowledge_layer: none`, the loop uses git-based alternatives
for work items, retros, distillation, and lint. No vault is required.

```yaml
knowledge_layer: skillwiki       # skillwiki | none
```

### Knowledge backends registry (optional)

Override backend-specific config or add future backends. If absent,
defaults are derived from `knowledge_layer` + `vault`.

```yaml
knowledge_backends:
  skillwiki:
    vault: ~/wiki
    cli_entry: skillwiki         # or npx tsx packages/cli/src/cli.ts for local dev
  none:
    work_dir: .claude/dev-loop-work/
```

**Capabilities by backend:**

| Capability | skillwiki | none | (future) |
|---|---|---|---|
| `query_vault` | yes | no | varies |
| `create_work_item` | proj-work | local mkdir | varies |
| `save_retro` | vault log.md | local retro.md | varies |
| `crystallize` | wiki-crystallize | write insights.md | varies |
| `distill` | proj-distill | grep retros → compound.md | varies |
| `lint_vault` | wiki-lint | project lint (if available) | varies |
| `audit_vault` | wiki-audit | verify work-item structure | varies |
| `drift_check` | skillwiki drift | check unpushed + stale branches | varies |

Vault type directories are **discovered from SCHEMA.md** at REFRESH time,
not hardcoded here. The REFRESH step parses the `## Layers` section of
`{vault}/SCHEMA.md` to extract the list of typed-knowledge subdirectories
(e.g., `entities/`, `concepts/`, `comparisons/`, `queries/`, `meta/`).
If SCHEMA.md doesn't exist or can't be parsed, the REFRESH step falls back
to listing directories in the vault root that contain `.md` files.

When `query_vault` not in BACKEND_CAPS, `vault` is ignored — the loop uses
git history and local work items instead of a vault.

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
deploy_script: <path-or-empty>     # e.g., bash apps/hub/deploy/update-msi1.sh, or empty
manifests_count: <N>               # how many manifests bump_script touches (sanity check)
remote_hosts: [<host>, ...]        # e.g., [sg01], or [] if not applicable
```

`publish_via` modes:

| Mode | Behavior |
|------|----------|
| `ci-tag-trigger` | Bump → commit → push → tag → CI publishes. Verify tag landed on remote after push. |
| `local` | Project's local release script runs on dev host (caution: interactive auth breaks /loop idempotency). |
| `none` | Skip step 10 (PUSH). Deploy may still run if `remote_hosts` or `deploy_script` is set. |

`deploy_script` is the command line to execute for step 9 (DEPLOY).
It should be idempotent and handle its own rollback on failure.
Leave empty to skip DEPLOY entirely.

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

knowledge_layer: skillwiki

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
