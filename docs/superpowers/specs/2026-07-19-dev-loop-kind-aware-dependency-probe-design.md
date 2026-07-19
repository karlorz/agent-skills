# Dev-loop Kind-aware Dependency Probe Design

## Context

`dev-loop-status` performs a read-only dependency preview from
`skills/dev-loop/dependencies.yaml`. Its current resolver treats every reference
like a skill: it searches fixed skill directories and recursively looks only for
`SKILL.md`. That produces false missing-optional results for installed agents.

Two observed false negatives demonstrate the defect:

- `dev-loop:research-worker` is shipped in `agents/research.md`, where YAML
  frontmatter declares `name: research-worker`; the filename intentionally does
  not match the registered agent name.
- `playwright-cli:browser-worker` is shipped in `agents/browser-worker.md` and
  exists in the installed Codex plugin cache, but the resolver never searches
  `agents/*.md`.

The canonical `doctor-worker` contract already distinguishes dependency kinds
and requires agent-name matching through frontmatter. Status mode should produce
the same installation classification without spawning a worker or writing state.

## Objective

Make the read-only status dependency probe resolve skills and agents according to
their declared `kind`, eliminating false missing-agent results while preserving
fail-closed reporting for genuinely unavailable dependencies.

## Scope

In scope:

- Parse `kind` and `ref` together from required and optional dependency entries.
- Preserve the current skill discovery behavior.
- Add agent discovery in repository and Claude/Codex installation locations.
- Match agents by exact filename or YAML-frontmatter `name`.
- Cover self-agents, external cached agents, and true missing agents with tests.
- Keep status probing deterministic, bounded, read-only, and portable.

Out of scope:

- Installing missing dependencies.
- Changing dependency requirements or optionality.
- Resolving MCP servers such as `claude-mem` beyond existing behavior.
- Adding unavailable capabilities such as `codex:codex-rescue`.
- Modifying the canonical doctor-worker contract.
- Repairing unrelated SkillWiki content lint findings.

## Considered Approaches

### 1. Kind-aware resolver aligned with doctor-worker — selected

Parse each manifest entry as `{kind, ref}` and route it to a skill or agent
resolver. Agent discovery checks exact names and frontmatter names. This keeps the
manifest semantic, follows the existing doctor-worker contract, and works across
source repositories plus Claude and Codex caches.

### 2. Add filenames to `dependencies.yaml`

This would require entries such as `file: research.md`. It is initially smaller
but duplicates packaging details in the dependency manifest and allows registered
agent names and filenames to drift independently. Rejected.

### 3. Query an installed-plugin runtime registry

Using `codex plugin list` or a Claude-specific equivalent would couple status to a
platform CLI, make results dependent on command availability, and still require
source-tree fallback logic. Rejected.

## Design

### Manifest parsing

The status helper will retain its lightweight parser but associate each `ref`
with the nearest preceding `kind` in the same YAML list item. Required and
optional sections continue to be classified independently.

Unknown or unsupported kinds remain missing rather than being optimistically
treated as present. This preserves fail-closed dependency reporting.

### Skill discovery

Skill entries retain the existing discovery rules:

- User skill directories under `~/.claude/skills` and `~/.agents/skills`.
- Claude and Codex plugin caches containing a matching `SKILL.md`.

The change must not regress currently detected required SkillWiki or optional
Superpowers skills.

### Agent discovery

Agent entries are searched in this order:

1. For `self: true` dev-loop entries, the repository's
   `skills/dev-loop/agents/*.md` files.
2. User agents under `~/.claude/agents/<name>.md`.
3. Claude plugin cache paths matching `<plugin>/*/agents/*.md`.
4. Codex plugin cache paths matching `<plugin>/*/agents/*.md`.

Each candidate is present when either:

- Its basename without `.md` equals the requested agent name; or
- Its leading YAML frontmatter contains `name: <requested-name>`.

Only Markdown files directly under an `agents` directory are candidates. The
probe must not treat arbitrary Markdown pages containing the name as agents.

### Result classification

Existing classification remains unchanged:

- Any missing required dependency: `broken`.
- Required dependencies present and at least one optional missing: `degraded`.
- All dependencies present: `healthy`.

After the fix, installed `dev-loop:research-worker` and
`playwright-cli:browser-worker` must not appear in `missing_optional`.
Genuinely unavailable optional references remain visible and continue to use
their documented fallbacks.

### Error handling and portability

- Missing directories are skipped without error.
- Unreadable or malformed agent files do not abort the probe; they simply do not
  match by frontmatter.
- Discovery performs filesystem reads only and executes no installation or
  mutation commands.
- Both legacy/root and nested-only plugin layouts remain supported where already
  applicable.

## Testing Strategy

Development follows red-green-refactor:

1. Create a fake repository containing `agents/research.md` with
   `name: research-worker` and a `self: true` dependency. Verify it is detected
   despite the filename mismatch.
2. Create a fake Codex plugin cache containing
   `playwright-cli/<version>/agents/browser-worker.md`. Verify the external agent
   is detected.
3. Include a nonexistent agent and verify it remains in `missing_optional` and
   keeps overall dependency status degraded.
4. Run the new test before production changes and confirm it fails because the
   existing resolver only searches `SKILL.md`.
5. Implement the minimal kind-aware resolver and confirm the test turns green.

Regression verification:

- `bash scripts/test-dev-loop-status.sh`
- `bash scripts/test-dev-loop-release-tooling.sh`
- `bash scripts/test-dev-loop-preflight-inventory.sh`
- Live `dev-loop-status --no-write` against this repository.

## Release and Completion

The code diff must pass the required `simplify:simplify` review. Following local
verification, commit and push directly to `origin/main`, wait for CI on the exact
commit, bump the stable patch version, rerun all required suites, push the release
commit, wait for its exact CI, then create and verify the stable tag. Refresh the
installed Codex plugin and confirm live status no longer reports installed agents
as missing.

The repository is complete when it is clean and synchronized, the remote tag
resolves to the green release commit, and only genuinely absent optional
dependencies remain in the live status report.
