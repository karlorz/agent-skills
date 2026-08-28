---
name: ranked-audit
user-invocable: false
description: >
  Use when /dev-loop ranked-audit performs an unattended, read-only audit of
  ranked project work and prepares evidence for later office-hours reconciliation.
---

# Dev-Loop Ranked Audit

Run a bounded cross-project lifecycle audit without changing repositories or
work-item status. The scan may publish one managed evidence report; it must not
apply lifecycle corrections.

## Hard Rules

1. Treat repositories and work items as read-only evidence sources.
2. Do NOT change work-item lifecycle status, checkboxes, evidence, plans, logs,
   project indexes, branches, tags, releases, or deployments.
3. Do not prompt. Ranked audit must run under interactive, `/goal`, scheduled,
   or satellite contexts with the same mechanical behavior.
4. Bound the scan with `--top <n>`; default to 20.
5. Use repository evidence only through the host-aware `project-repos.yaml`
   resolver. Never borrow one current checkout as evidence for every project.
6. Publish only the audit report through SkillWiki's managed publisher. If the
   publisher is unavailable, leave the draft outside the vault and report the
   blocked publication.

## Inputs

```text
/dev-loop ranked-audit
/dev-loop ranked-audit --top 20
```

Resolve:

- `<vault>` through the configured SkillWiki backend or `skillwiki path`.
- `<project-repos>` from
  `projects/llm-wiki/architecture/project-repos.yaml`, with the selected
  project's architecture fallback when the coordinator file is absent.
- `<host-id>` from SkillWiki fleet context or the configured host identity.
- `<repo-user>` from the runtime user.

## Scan

Run the deterministic helper from the dev-loop plugin root:

```bash
node scripts/ranked-audit.js \
  --vault <vault> \
  --top <n> \
  --project-repos <project-repos> \
  --host-id <host-id> \
  --repo-user <repo-user>
```

The helper reuses `preflight-inventory.js`, preserves its priority/status
ordering, resolves repository evidence per selected project, and emits:

- `delivered-close-candidate`
- `active-code-work`
- `verification-only`
- `human-gated`
- `stale-or-superseded`
- `unverifiable`

When signals overlap, classification precedence is `verification-only`,
`human-gated`, `delivered-close-candidate`, `unverifiable`,
`stale-or-superseded`, then `active-code-work`.

Require `read_only: true` and `writes_executed: false`. Stop if either field is
missing or false.

## Evidence Report

Create a complete typed-page draft outside the vault. Target:

```text
meta/YYYY-MM-DD-ranked-audit-top-<n>.md
```

Include:

- command inputs, host identity, and repository-resolution degradations;
- the ranked candidate table with project, lifecycle status, priority,
  classification, reasons, evidence files, and matching commits;
- counts by classification;
- explicit confirmation that no work-item or repository mutation ran;
- the attended continuation command:
  `/dev-loop office-hours <audit-report> --reconcile`.

Publish through `skillwiki page publish`: dry-run, review the state-bound token,
then write with the same draft and token. Do not edit root `index.md` or
`log.md` directly.

## Exit

Print the report path and classification counts. If no candidate needs human
reconciliation, say so and do not recommend office-hours merely to create work.
