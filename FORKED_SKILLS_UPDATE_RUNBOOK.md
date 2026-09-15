# Forked Skill Update Runbook

Use this runbook to review and update the locally packaged `grill-me`,
`playwright-cli`, and `simplify` skills without losing their Claude, Codex, or
Cursor marketplace adaptations.

The central rule is: **an upstream update is a semantic rebase, not a directory
copy**. Resolve and record an immutable upstream artifact, compare it with the
local adaptation, choose changes deliberately, preserve local overlays, and
then synchronize every package manifest and marketplace entry.

## Scope

This runbook covers:

- upstream provenance and freshness checks;
- safe source acquisition and comparison;
- license and redistribution review;
- canonical local files and adaptation boundaries;
- Claude, Codex, and Cursor plugin metadata;
- package-specific and repository-wide validation;
- the repository's main-first commit, push, CI, and tag flow.

It does not authorize automatic copying of upstream files, executing downloaded
binaries, changing licenses without review, npm/package publication, legal
release approval, or tagging a release before main CI passes. It does document
the repository-authorized post-CI Git tag flow.

## Repository invariants

Keep these invariants throughout every update:

1. Work on `main` unless direct push becomes impossible.
2. Do not edit installed plugin caches. Edit this repository and let the
   marketplace installation flow refresh caches later.
3. Keep one canonical nested skill surface. Do not recreate historical root
   `SKILL.md` mirrors; Grok and other loaders may register both copies and
   produce duplicate commands.
4. Keep package versions independent from upstream versions. For example,
   local `playwright-cli` plugin `1.3.6` and upstream `@playwright/cli` `0.1.20`
   are separate version streams.
5. Treat root `.claude-plugin/marketplace.json` as required Codex discovery
   metadata. A `.codex-plugin/plugin.json` alone does not make a package
   discoverable to `codex plugin list`.
6. Do not overwrite local overlays merely because upstream reorganized a skill.
7. Store raw comparison output, downloaded metadata, scratch notes, and update
   ledgers under `.superpowers/sdd/<work-id>/`. That path is local and ignored.
   Keep only curated implementation, tests, changelogs, and this runbook in the
   repository.
8. Do not write raw update transcripts or handoff reports into the SkillWiki
   vault. Use the managed SkillWiki workflow only when separately capturing a
   curated decision or reusable lesson.

## Upstream registry

The baseline column records externally verified state on **2026-09-16**. It is
evidence for the current local lineage, not a substitute for resolving the
latest immutable source during a future update.

| Local package | Primary authority | Verified baseline | License evidence | Local lineage and boundary |
|---|---|---|---|---|
| `grill-me` | [`mattpocock/skills`](https://github.com/mattpocock/skills), paths `skills/productivity/grill-me/` and `skills/productivity/grilling/` | `959a8e9f1edc3adbe2f7e3054bb6fbefa6696260` on `main` | Repository root `LICENSE`, MIT | Local package preserves an older sequential, one-question-at-a-time interview and adds Claude/Codex/Antigravity tool selection plus unattended-session behavior. Current upstream uses a thin `grill-me` wrapper and a round/frontier-based `grilling` implementation, so it is not a drop-in replacement. |
| `playwright-cli` | [`microsoft/playwright-cli`](https://github.com/microsoft/playwright-cli), especially `skills/playwright-cli/`; npm package [`@playwright/cli`](https://registry.npmjs.org/@playwright%2fcli) | tag `v0.1.20`, commit `12228454ed024c9ac89abd59df3b706ed9135fd9`, npm `0.1.20` | Repository `LICENSE` and `package.json`, Apache-2.0 | The Microsoft skill and reference docs are the upstream surface. Attach-first Chrome, global-profile behavior, `chrome-debug`, cmux ownership handling, setup scripts, config, tests, and `browser-worker` are local overlays. |
| `simplify` | Anthropic's versioned [`@anthropic-ai/claude-code`](https://registry.npmjs.org/@anthropic-ai%2fclaude-code) wrapper/native npm artifacts are the strongest behavioral artifacts. [`Piebald-AI/claude-code-system-prompts`](https://github.com/Piebald-AI/claude-code-system-prompts) is a readable secondary extraction/reference. | Local behavior names Claude Code `2.1.199`. That npm version remains fetchable. Piebald tag `v2.1.199` points to commit `1c1bf5957a0e38697c78157da1de02adf9daaa18`, but its simplify file says the prompt was introduced at `ccVersion: 2.1.154`. | Anthropic package: `SEE LICENSE IN README.md` / Anthropic legal agreements and all-rights-reserved notice. Piebald repository: MIT. | The local skill is an independently packaged, expanded adaptation of the four-angle workflow. Neither Piebald's MIT license nor npm availability should be treated as permission to redistribute newly extracted Anthropic text verbatim. |

### Verified baseline references

These immutable or versioned references support the baseline above:

- `grill-me`:
  [`mattpocock/skills@959a8e9`](https://github.com/mattpocock/skills/commit/959a8e9f1edc3adbe2f7e3054bb6fbefa6696260),
  pinned
  [`grill-me/SKILL.md`](https://raw.githubusercontent.com/mattpocock/skills/959a8e9f1edc3adbe2f7e3054bb6fbefa6696260/skills/productivity/grill-me/SKILL.md),
  pinned
  [`grilling/SKILL.md`](https://raw.githubusercontent.com/mattpocock/skills/959a8e9f1edc3adbe2f7e3054bb6fbefa6696260/skills/productivity/grilling/SKILL.md),
  and pinned
  [`LICENSE`](https://raw.githubusercontent.com/mattpocock/skills/959a8e9f1edc3adbe2f7e3054bb6fbefa6696260/LICENSE).
- `playwright-cli`:
  [`microsoft/playwright-cli@1222845`](https://github.com/microsoft/playwright-cli/commit/12228454ed024c9ac89abd59df3b706ed9135fd9),
  release
  [`v0.1.20`](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.20),
  pinned
  [`SKILL.md`](https://raw.githubusercontent.com/microsoft/playwright-cli/12228454ed024c9ac89abd59df3b706ed9135fd9/skills/playwright-cli/SKILL.md),
  and versioned
  [npm registry metadata](https://registry.npmjs.org/@playwright%2fcli/0.1.20).
  Registry integrity for `@playwright/cli@0.1.20` was
  `sha512-kEL+73IwNVFmUjGn0rmpBStZ8jju8MmmWBMXmVMesBzoZ8YW2b/Nv7aCOYLBrCbYzc7RvWZCbVj88+wOCg8yyw==`.
- `simplify`:
  versioned
  [`@anthropic-ai/claude-code@2.1.199` registry metadata](https://registry.npmjs.org/@anthropic-ai%2fclaude-code/2.1.199),
  the platform artifact used by the prior local extraction,
  [`@anthropic-ai/claude-code-darwin-arm64@2.1.199`](https://registry.npmjs.org/@anthropic-ai%2fclaude-code-darwin-arm64/2.1.199),
  and Piebald's tagged
  [`v2.1.199` simplify reference](https://raw.githubusercontent.com/Piebald-AI/claude-code-system-prompts/v2.1.199/system-prompts/agent-prompt-simplify-slash-command.md).
  The official wrapper integrity was
  `sha512-iQzR49drod55y9NiJHTWt7vSSO85LDvMymEzpO+RTDar+TCsNbE2d2+dj1O57D2rWVA5z0Qhqv0j3K0LvY1exA==`;
  the Darwin ARM64 artifact integrity was
  `sha512-i3xy/5XCgV+fQmgMQHDkqLp5JuP0/WGpAXxXirQOprcnkXlY/UreKq51AZHxxFDL3VMBYoDVQXIdtTsfPGiUoA==`.

Always query the registry or Git remote again during an update. These links
prove the recorded baseline; they do not mean it remains the newest release.

### Source authority order

Use this order when evidence disagrees:

1. An immutable artifact published by the owning project: a Git commit, signed
   tag, release, or versioned npm tarball with registry integrity.
2. Files in the owning project's repository at that immutable revision.
3. Owning-project release notes and package metadata.
4. A maintained extraction or mirror such as Piebald, clearly labeled as a
   secondary reference.
5. Local git history and research notes, used to explain local intent rather
   than current upstream truth.

Never use a mutable `main` URL, an installed cache, a search-result excerpt, or
an unversioned package as the only provenance record.

## End-to-end update procedure

### 1. Create an update work area

Choose a work ID such as `2026-09-16-playwright-cli-upstream-review` and keep
raw evidence in its ignored SDD directory:

```bash
WORK_ID=2026-09-16-playwright-cli-upstream-review
WORK_ROOT=".superpowers/sdd/$WORK_ID"
mkdir -p "$WORK_ROOT/upstream" "$WORK_ROOT/output"
```

Confirm repository state before fetching external material:

```bash
git branch --show-current
git status --short
git fetch origin main --tags
git rev-parse HEAD
git rev-parse origin/main
```

Bootstrap the ignored local dev-loop config in a fresh checkout:

```bash
if test ! -f .claude/dev-loop.config.md; then
  cp .claude/dev-loop.config.example.md .claude/dev-loop.config.md
fi

rg -n 'vault: auto' .claude/dev-loop.config.md
```

Expected starting state:

- branch is `main`;
- existing user changes, if any, are understood and preserved;
- `HEAD` equals `origin/main`, or `git pull --ff-only origin main` can update it;
- `.claude/dev-loop.config.md` exists and retains
  `knowledge_backends.skillwiki.vault: auto`.

Do not reset, clean, or discard an existing dirty worktree. If unrelated changes
overlap the package being updated, stop and coordinate ownership first.

### 2. Resolve and pin upstream identity

Record all of the following before comparing content:

- owning organization and repository or npm package name;
- mutable channel checked, such as `main` or `latest`;
- resolved commit SHA, tag, package version, tarball URL, and integrity value;
- access date;
- upstream license path and SPDX/license text;
- exact source paths compared;
- the previous upstream baseline, when known.

For a GitHub upstream, resolve the current branch without trusting a web page:

```bash
UPSTREAM_REPO=https://github.com/OWNER/REPOSITORY.git
UPSTREAM_BRANCH=main
UPSTREAM_SHA="$(git ls-remote "$UPSTREAM_REPO" "refs/heads/$UPSTREAM_BRANCH" | awk '{print $1}')"
test -n "$UPSTREAM_SHA"
printf '%s\n' "$UPSTREAM_SHA"
```

Fetch that exact object into a disposable checkout under the ignored work area:

```bash
UPSTREAM_CHECKOUT="$WORK_ROOT/upstream/repository"
git init "$UPSTREAM_CHECKOUT"
git -C "$UPSTREAM_CHECKOUT" remote add origin "$UPSTREAM_REPO"
git -C "$UPSTREAM_CHECKOUT" fetch --depth=1 origin "$UPSTREAM_SHA"
git -C "$UPSTREAM_CHECKOUT" checkout --detach "$UPSTREAM_SHA"
git -C "$UPSTREAM_CHECKOUT" show --no-patch --format=fuller HEAD
```

For npm, inspect a specific version rather than installing `latest`:

```bash
PACKAGE_SPEC='@scope/package@1.2.3'
npm view --json "$PACKAGE_SPEC" name version license repository engines dist
npm pack --ignore-scripts --dry-run --json "$PACKAGE_SPEC"
```

`npm view` and `npm pack --ignore-scripts` are preferred here because provenance
review should not execute lifecycle scripts. Do not use `npm install`, `npx`,
`bunx`, or an extracted native binary merely to inspect a package. Bun may read
the same registry, but it is a client, not the source authority; record the npm
registry artifact identity.

### 3. Capture the previous local intent

Before editing, read the complete canonical local skill and its relevant
history:

```bash
git log --follow --oneline -- "skills/PACKAGE/skills/SKILL_NAME/SKILL.md"
git log --stat -- "skills/PACKAGE"
git tag --list 'PACKAGE-*' --sort=-version:refname
```

Also read:

- every package manifest;
- the root marketplace entry;
- package changelog, when present;
- package-specific tests;
- files explicitly identified as local overlays below.

Write the local invariants into the update ledger before diffing. This avoids
mistaking an intentional adaptation for stale code.

### 4. Compare semantics before copying files

Use `git diff --no-index` or `diff -u` to generate review material, but do not
pipe the result over the local files:

```bash
set +e
git diff --no-index -- \
  "$UPSTREAM_CHECKOUT/path/to/upstream/SKILL.md" \
  "skills/PACKAGE/path/to/local/SKILL.md" \
  > "$WORK_ROOT/output/skill.diff"
DIFF_STATUS=$?
set -e
test "$DIFF_STATUS" -le 1
```

Classify each upstream change:

| Decision | Meaning | Action |
|---|---|---|
| Accept | Correct and compatible with the local package | Adapt it into the canonical local file. |
| Adapt | Valuable, but upstream assumes different tools, packaging, or runtime behavior | Re-express it using this repository's Claude/Codex/Cursor contracts. |
| Reject | Conflicts with an intentional local invariant or is outside package scope | Leave local behavior unchanged and record why. |
| Defer | Requires a separate design, license decision, or runtime change | Create a follow-up only after the current update is complete. |

For prose skills, review workflow changes, trigger policy, tool names,
delegation rules, attended/unattended behavior, error handling, and output
contracts—not only line-level wording.

### 5. Pass the license and provenance gate

Before copying any changed upstream text or file, answer these questions in the
ledger:

1. What license governs the exact upstream artifact?
2. Does the local package include the required notice or attribution?
3. Does the local manifest's `license` describe the whole redistributed package
   accurately, or only original local additions?
4. Is the intended change a semantic reimplementation, a modified copy, or a
   verbatim copy?
5. Does a proprietary or compiled artifact impose terms beyond an open-source
   mirror's license?

Block publication when these answers are unclear. Do not “fix” a mismatch by
changing manifest text without reviewing the actual component licenses and
notice obligations.

Known gates:

- `grill-me`: upstream is MIT; preserve the applicable copyright and permission
  notice when copying substantial upstream material.
- `playwright-cli`: Microsoft upstream is Apache-2.0 while current local plugin
  manifests say MIT. Before importing new or changed Microsoft files, decide
  how Apache-2.0 attribution/notice and local package licensing will be
  represented. The current manifest value alone does not resolve that question.
- `simplify`: Anthropic's npm package is not an open-source prompt repository.
  By default, compare behavior and write a local adaptation; do not publish
  newly extracted prompt text verbatim. Treat Piebald as secondary evidence,
  not as proof that Anthropic material may be redistributed under MIT.

This gate is a maintenance control, not legal advice. Escalate ambiguous
redistribution questions for legal review.

### 6. Edit only canonical source and overlay files

Current canonical skill paths are:

```text
skills/grill-me/skills/grill-me/SKILL.md
skills/grill-me/skills/grilling/SKILL.md
skills/playwright-cli/skills/playwright-cli/SKILL.md
skills/simplify/skills/simplify/SKILL.md
```

Do not create these historical duplicate layouts:

```text
skills/grill-me/SKILL.md
skills/grill-me/grilling/SKILL.md
skills/playwright-cli/SKILL.md
skills/simplify/SKILL.md
```

When a description changes, keep it as routing metadata: target at most 180
characters, never exceed the CI limit of 220 characters, and avoid duplicating
another skill's canonical description.

### 7. Choose the local version bump

Use the local plugin's semantic version, not the upstream package version:

- patch: provenance-only clarification, compatible wording, test, metadata, or
  narrowly compatible upstream correction;
- minor: meaningful compatible behavior or command-surface expansion;
- major: trigger, invocation, workflow, output, or compatibility change that
  can break existing users.

Record the old local version, new local version, and reason in the ledger.

### 8. Synchronize package and marketplace metadata

Update every applicable version-bearing file in the same commit.

| Package | Package manifests | Root marketplace | Other release metadata |
|---|---|---|---|
| `grill-me` | `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | `.claude-plugin/marketplace.json` | `skills/grill-me/CHANGELOG.md` |
| `playwright-cli` | `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json` | `.claude-plugin/marketplace.json`; verify `.cursor-plugin/marketplace.json` remains correct even though its current entry has no version field | package tests and any user-facing minimum `@playwright/cli` version |
| `simplify` | `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | `.claude-plugin/marketplace.json` | `agents/openai.yaml` only if its interface text changed |

Preserve `"skills": "./skills/"` in package manifests. Do not point Claude at
the package root and do not add a second mirrored `SKILL.md`.

Validate JSON immediately after editing:

```bash
jq empty .claude-plugin/marketplace.json
jq empty .cursor-plugin/marketplace.json
find skills/grill-me skills/playwright-cli skills/simplify \
  -path '*/plugin.json' -type f -print0 \
  | xargs -0 -n1 jq empty
```

Check the synchronized version values explicitly:

```bash
jq -r '.plugins[] | select(.name == "grill-me" or .name == "playwright-cli" or .name == "simplify") | [.name, .version] | @tsv' \
  .claude-plugin/marketplace.json

find skills/grill-me skills/playwright-cli skills/simplify \
  -path '*/plugin.json' -type f -print0 \
  | xargs -0 -n1 jq -r '[.name, .version] | @tsv'
```

### 9. Review the complete diff

Run these before tests:

```bash
git status --short
git diff --check
git diff --stat
git diff -- FORKED_SKILLS_UPDATE_RUNBOOK.md skills/PACKAGE .claude-plugin/marketplace.json .cursor-plugin/marketplace.json
```

Confirm that:

- no installed cache, ignored runtime output, downloaded tarball, or extracted
  binary is staged;
- local overlays remain intact;
- license decisions are reflected consistently;
- package and marketplace versions agree;
- descriptions remain within the routing budget;
- Markdown links and local relative paths resolve;
- generated or copied text does not contain stale upstream version claims.

### 10. Run validation

Run the package-specific checks first so failures are easy to localize.

For `playwright-cli` changes:

```bash
bash skills/playwright-cli/scripts/test-setup-playwright-cli.sh
```

For `grill-me` and `simplify`, the release-tooling suite currently contains the
important layout, inventory, description, and simplify-contract assertions.
Add a focused package test when an update introduces behavior that the shared
suite cannot verify.

Then run the repository-required checks from `AGENTS.md` plus the matching CI
description-budget checks:

```bash
bash scripts/test-dev-loop-release-tooling.sh
bash scripts/test-plugin-metadata.sh
bash scripts/test-cursor-claude-plugin-exam.sh
bash scripts/test-cursor-github-marketplace-repin.sh
bash scripts/test-dev-loop-preflight-inventory.sh
python3 scripts/test-skill-description-budget.py
python3 scripts/lint-skill-descriptions.py --layout agent-skills --max-total-chars 4800
```

The final two commands mirror CI's skill-description checks: descriptions target
180 characters, fail individually above 220 characters, must be unique at their
canonical surface, and must fit the current 4,800-character total catalog
budget.

Do not declare the update complete when a required test was skipped. Record the
exact failing command and output under `.superpowers/sdd/<work-id>/output/`, fix
in-scope failures, and rerun the failed test plus any tests whose inputs changed.

### 11. Commit, push, CI, and tag

After all local validation passes:

```bash
git status --short
git diff --check
git add FORKED_SKILLS_UPDATE_RUNBOOK.md skills/PACKAGE .claude-plugin/marketplace.json
```

Include `.cursor-plugin/marketplace.json` when it changed. Review the staged diff:

```bash
git diff --cached --check
git diff --cached --stat
git diff --cached
```

Use a package-scoped commit such as:

```bash
git commit -m "feat(playwright-cli): rebase Microsoft skill surface"
```

Refresh main immediately before pushing:

```bash
git fetch origin main
git rev-parse HEAD
git rev-parse origin/main
```

If `origin/main` moved, reconcile without discarding local work and rerun
affected tests. Otherwise push directly:

```bash
git push origin main
```

Create a PR only when direct push conflicts, permissions fail, main moved in a
way that cannot be safely reconciled, or branch protection blocks the push.

Wait for main CI to pass before creating a package tag. Then tag the exact CI
commit using the existing `<package>-<version>` convention and push that tag.
Do not tag a locally tested commit whose main CI has not passed.

## Package procedure: `grill-me`

### Authoritative source

```text
Repository: https://github.com/mattpocock/skills.git
Upstream files:
  skills/productivity/grill-me/SKILL.md
  skills/productivity/grill-me/agents/openai.yaml
  skills/productivity/grilling/SKILL.md
  skills/productivity/grilling/agents/openai.yaml
  skills/productivity/README.md
  LICENSE
```

Resolve the current immutable SHA:

```bash
GRILL_REPO=https://github.com/mattpocock/skills.git
GRILL_SHA="$(git ls-remote "$GRILL_REPO" refs/heads/main | awk '{print $1}')"
test -n "$GRILL_SHA"
printf '%s\n' "$GRILL_SHA"
```

Fetch the exact revision using the common Git procedure, then compare both
upstream skill names with both local skill names.

### Local behavior to preserve deliberately

- both `grill-me` and `grilling` are packaged for direct resolution;
- Claude Code, Codex, and Antigravity question-tool guidance;
- attended main-session execution;
- explicit behavior for `/goal`, `codex exec`, scheduled, and unattended runs;
- codebase facts are explored rather than asked of the user;
- nested-only `./skills/` package layout.

### Known upstream divergence

At the verified 2026-09-16 baseline, upstream `grill-me` is a thin wrapper that
invokes `grilling`, while upstream `grilling` asks a whole decision-tree frontier
in rounds and permits subagents to research environment facts. The local skill
uses sequential one-question-at-a-time interviewing and prohibits delegation.

Treat any adoption of the upstream round/frontier model as a behavior change,
not a routine sync. Decide explicitly whether the local cross-platform contract
should remain sequential, become round-based, or expose the two behaviors under
different skill names.

### Version and validation checklist

- update both canonical `SKILL.md` files when shared behavior changes;
- update both Claude and Codex manifests;
- update the root Claude marketplace version;
- add a dated entry to `skills/grill-me/CHANGELOG.md`;
- preserve `skills: "./skills/"`;
- run the complete repository-required and CI description-budget checks.

## Package procedure: `playwright-cli`

### Authoritative source

```text
Repository: https://github.com/microsoft/playwright-cli.git
Npm package: @playwright/cli
Upstream skill: skills/playwright-cli/SKILL.md
Upstream references: skills/playwright-cli/references/*.md
License: LICENSE and package.json, Apache-2.0
```

Resolve both the Git and npm identities:

```bash
PLAYWRIGHT_REPO=https://github.com/microsoft/playwright-cli.git
PLAYWRIGHT_SHA="$(git ls-remote "$PLAYWRIGHT_REPO" refs/heads/main | awk '{print $1}')"
test -n "$PLAYWRIGHT_SHA"
printf '%s\n' "$PLAYWRIGHT_SHA"

npm view @playwright/cli dist-tags time --json
PLAYWRIGHT_VERSION=0.1.20
PLAYWRIGHT_SPEC="@playwright/cli@$PLAYWRIGHT_VERSION"
npm view "$PLAYWRIGHT_SPEC" version license repository engines dist --json
npm pack --ignore-scripts --dry-run --json "$PLAYWRIGHT_SPEC"
```

Prefer a release tag that resolves to the same commit as the chosen npm
version. Record both identities and any mismatch.

### Upstream-derived local surface

Review these against Microsoft's `skills/playwright-cli/` tree:

```text
skills/playwright-cli/skills/playwright-cli/SKILL.md
skills/playwright-cli/references/element-attributes.md
skills/playwright-cli/references/playwright-tests.md
skills/playwright-cli/references/request-mocking.md
skills/playwright-cli/references/running-code.md
skills/playwright-cli/references/session-management.md
skills/playwright-cli/references/storage-state.md
skills/playwright-cli/references/test-generation.md
skills/playwright-cli/references/tracing.md
skills/playwright-cli/references/video-recording.md
```

Do not assume all local references share one upstream version. At the verified
2026-09-16 review, six local references matched upstream `v0.1.20`, while
`session-management.md` and `video-recording.md` matched `v0.1.19`, and
`tracing.md` matched `v0.1.18`. Upstream `v0.1.20` also added
`references/pr-attachments.md`, which is not currently packaged locally.

Create a per-file comparison table in the update ledger with upstream blob or
content hash, local hash, selected decision, and reason.

### Local overlays: do not replace from Microsoft upstream

```text
skills/playwright-cli/.claude-plugin/plugin.json
skills/playwright-cli/.codex-plugin/plugin.json
skills/playwright-cli/.cursor-plugin/plugin.json
skills/playwright-cli/.playwright/cli.config.json
skills/playwright-cli/agents/browser-worker.md
skills/playwright-cli/references/chrome-debug.md
skills/playwright-cli/references/spec-driven-testing.md
skills/playwright-cli/scripts/cdp-load-unpacked.py
skills/playwright-cli/scripts/chrome-debug.sh
skills/playwright-cli/scripts/setup-playwright-cli.sh
skills/playwright-cli/scripts/test-chrome-debug-cmux-host.sh
skills/playwright-cli/scripts/test-chrome-debug-load-unpacked.sh
skills/playwright-cli/scripts/test-setup-playwright-cli.sh
skills/playwright-cli/skills/playwright-cli/agents/openai.yaml
```

Preserve these behavioral invariants unless the update explicitly redesigns
them:

- attach-first use of an existing debugger;
- default-user global Chrome profile behavior;
- safe handling of unmanaged launchers and configs;
- `owned_by_cmux` attach-only behavior and refusal to restart cmux-owned Chrome;
- Linux/LXC/headless support;
- unpacked-extension persistence;
- one bundled launcher source of truth;
- browser-worker integration with dev-loop.

### Updating the Microsoft section safely

1. Diff the complete upstream skill against the local skill.
2. Separate Microsoft command/reference changes from the local preamble and
   runtime policy.
3. Check whether new commands require a higher `MIN_CLI_VERSION` in
   `scripts/setup-playwright-cli.sh`.
4. If the minimum changes, update every user-facing `@playwright/cli` minimum
   claim and setup test together.
5. Review added/deleted upstream references. Add a reference only if it is
   linked from the local skill or intentionally retained as packaged guidance.
6. Run all setup/launcher tests before the repository-wide suite.
7. Resolve the Apache-2.0-versus-local-MIT license representation before
   publishing copied upstream changes.

### Version and validation checklist

- keep the local plugin version separate from npm `@playwright/cli`;
- synchronize Claude, Codex, and Cursor manifests;
- synchronize the root Claude marketplace version;
- verify the Cursor marketplace entry and KEEP/repin integration;
- run `bash skills/playwright-cli/scripts/test-setup-playwright-cli.sh`;
- run the complete repository-required and CI description-budget checks.

## Package procedure: `simplify`

### Authoritative and secondary sources

The behavioral authority is the exact Anthropic npm artifact whose version is
being reviewed. The public Piebald repository is useful for readable structure,
history, and cross-checking, but it is not Anthropic-authored source.

```text
Official wrapper: @anthropic-ai/claude-code@VERSION
Official native artifacts: @anthropic-ai/claude-code-<platform>@VERSION
Secondary repository: https://github.com/Piebald-AI/claude-code-system-prompts.git
Secondary file: system-prompts/agent-prompt-simplify-slash-command.md
```

Inspect official versioned metadata without installing or executing it:

```bash
CLAUDE_CODE_VERSION=2.1.199
CLAUDE_CODE_SPEC="@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION"
npm view --json "$CLAUDE_CODE_SPEC" \
  name version license engines scripts optionalDependencies dist
npm pack --ignore-scripts --dry-run --json "$CLAUDE_CODE_SPEC"
```

If a native artifact must be inventoried, select the exact platform package
listed in `optionalDependencies`, use `npm pack --ignore-scripts`, verify the
registry `dist.integrity`, and inspect its archive listing. Do not execute the
binary, its installer, or extracted JavaScript during a routine provenance
check. Any deeper compiled-artifact extraction should be a separately reviewed,
versioned, reproducible process with an explicit legal decision.

Inspect the secondary reference at a matching immutable tag or commit:

```bash
PIEBALD_REPO=https://github.com/Piebald-AI/claude-code-system-prompts.git
PIEBALD_REF=v2.1.199
PIEBALD_SHA="$(git ls-remote "$PIEBALD_REPO" "refs/tags/$PIEBALD_REF^{}" | awk '{print $1}')"

if test -z "$PIEBALD_SHA"; then
  PIEBALD_SHA="$(git ls-remote "$PIEBALD_REPO" "refs/tags/$PIEBALD_REF" | awk '{print $1}')"
fi

test -n "$PIEBALD_SHA"
printf '%s\n' "$PIEBALD_SHA"
```

Record the file's embedded `ccVersion` separately from the repository tag. They
may differ: the tag says which extraction release contains the file; the
embedded version may say when that prompt shape was introduced.

### Local behavior to preserve deliberately

- current-diff targeting with upstream/main/HEAD fallbacks;
- four independent review angles: Reuse, Simplification, Efficiency, Altitude;
- concrete-cost findings rather than vague style advice;
- deduplication before applying fixes;
- behavior-preservation and narrow-scope guardrails;
- platform fallback when parallel agents are unavailable;
- validation and concise reporting after fixes.

### Update decision rules

1. First determine whether a newer Claude Code version actually changed the
   simplify workflow. A higher package version alone is not an update reason.
2. Compare workflow structure and meaning, not internal variable names or
   compiled implementation details.
3. Re-express accepted behavior in repository-native language and tools.
4. Do not claim an exact Claude Code version match unless the chosen immutable
   artifact supports that claim.
5. Do not copy proprietary Anthropic text merely because a third-party
   extraction is published under MIT.
6. Update `skills/dev-loop/agents/simplify-worker.md` and its tests if the
   canonical four-angle contract changes; that worker resolves this packaged
   skill as its source of truth.

### Version and validation checklist

- update the canonical nested skill only;
- synchronize Claude and Codex manifests;
- synchronize the root Claude marketplace version;
- update `agents/openai.yaml` only when interface text changes;
- verify `scripts/test-dev-loop-release-tooling.sh` still asserts the intended
  simplify contract;
- run the complete repository-required and CI description-budget checks.

## Update ledger template

Copy this template to `.superpowers/sdd/<work-id>/upstream-ledger.md` for each
maintenance run. Do not commit the filled raw ledger.

```markdown
# Upstream update ledger: <package>

## Identity

- Work ID:
- Operator:
- Access date:
- Local package:
- Local version before:
- Proposed local version after:
- Local starting commit:
- Upstream owner/repository or package:
- Mutable channel checked:
- Resolved commit SHA/tag/package version:
- Tarball/archive URL:
- Registry integrity or archive hash:
- Previous recorded upstream baseline:

## Source files

| Upstream file/artifact | Immutable ref or hash | Local file | Local hash | Decision | Reason |
|---|---|---|---|---|---|
| | | | | Accept / Adapt / Reject / Defer | |

## Local invariants

- Invariant:
- Invariant:
- Invariant:

## Semantic changes

| Upstream change | User-visible effect | Decision | Local implementation |
|---|---|---|---|
| | | | |

## License and provenance gate

- Exact upstream license/terms:
- License source path or URL:
- Copyright/notice requirement:
- Local manifest license assessment:
- Verbatim, modified-copy, or semantic-reimplementation classification:
- Proprietary/compiled-source considerations:
- Decision owner and outcome:
- Publication blocked? Yes / No

## Packaging

- Canonical files changed:
- Claude manifest version:
- Codex manifest version:
- Cursor manifest version, if applicable:
- Root Claude marketplace version:
- Root Cursor marketplace reviewed:
- Changelog entry:
- Release tag planned:

## Validation

| Command | Result | Output record |
|---|---|---|
| `git diff --check` | | |
| package-specific tests | | |
| `bash scripts/test-dev-loop-release-tooling.sh` | | |
| `bash scripts/test-plugin-metadata.sh` | | |
| `bash scripts/test-cursor-claude-plugin-exam.sh` | | |
| `bash scripts/test-cursor-github-marketplace-repin.sh` | | |
| `bash scripts/test-dev-loop-preflight-inventory.sh` | | |
| `python3 scripts/test-skill-description-budget.py` | | |
| `python3 scripts/lint-skill-descriptions.py --layout agent-skills --max-total-chars 4800` | | |

## Release outcome

- Commit:
- Direct push or PR reason:
- Main CI URL/result:
- Tag and tag commit:
- Installed-channel refresh checked:
- Deferred follow-up:
```

## Fast review checklist

Use this abbreviated checklist only after understanding the full runbook:

- [ ] Start from current `main`; preserve unrelated work.
- [ ] Create ignored `.superpowers/sdd/<work-id>/` evidence directory.
- [ ] Resolve immutable upstream SHA/tag/package version and integrity.
- [ ] Record exact source paths and license evidence.
- [ ] Read canonical local files, history, manifests, tests, and overlays.
- [ ] Classify every meaningful upstream change: accept, adapt, reject, defer.
- [ ] Pass the package-specific license/provenance gate.
- [ ] Edit canonical nested sources only.
- [ ] Preserve local cross-platform and runtime overlays.
- [ ] Choose a local semantic-version bump independently of upstream version.
- [ ] Synchronize all applicable manifests and root marketplace metadata.
- [ ] Update changelog or interface metadata where applicable.
- [ ] Run JSON, diff, package-specific, repository-required, and both CI description-budget checks.
- [ ] Review the staged diff; exclude caches, binaries, tarballs, and raw output.
- [ ] Push directly to `origin/main` unless repository policy forces a PR.
- [ ] Wait for main CI before creating or pushing a release tag.
