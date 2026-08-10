# grok-build-harness Plugin-Enabled Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the one-line PLUGIN_SPECS fix (PR #8), add a regression test that asserts `grok-build-harness` appears in `[plugins].enabled`, and update the design doc's plugin count from 13 to 14.

**Architecture:** The fix itself is already committed on branch `fix/grok-build-harness-plugin-enabled` (commit `cf92d25`). This plan covers merging it to `main`, then adding the regression test and design-doc update directly on `main` per the repo's main-first policy.

**Tech Stack:** Bash test framework (`scripts/test-grok-build-harness.sh`), Python `generate-config.py`, Markdown design doc.

## Global Constraints

- Repo follows main-first: push directly to `origin/main` after local verification. Create a PR only if direct push fails.
- All changes must pass: `bash scripts/test-grok-build-harness.sh`, `bash scripts/test-plugin-metadata.sh`, `bash scripts/test-dev-loop-preflight-inventory.sh`.
- No local Docker for testing (user preference). Use temp dirs and scratch GROK_HOME trees.
- The fix branch `fix/grok-build-harness-plugin-enabled` is PR #8, already mergeable with green CI.

---

### Task 1: Merge PR #8 to main

**Files:**
- No file changes — merge operation only

**Interfaces:**
- Consumes: PR #8 (`fix/grok-build-harness-plugin-enabled` → `main`, commit `cf92d25`)
- Produces: `main` branch contains the one-line PLUGIN_SPECS fix

- [ ] **Step 1: Ensure local main is current**

```bash
git checkout main
git pull origin main
```

Expected: `main` is up to date with `origin/main`.

- [ ] **Step 2: Merge the fix branch (includes fix + handoff doc)**

The fix branch contains two commits: the one-line fix (`cf92d25`) and the
handoff document (`782b959`). Both are squash-merged into a single commit
on main.

```bash
git merge --squash fix/grok-build-harness-plugin-enabled
git commit -m "fix(grok-build-harness): include harness plugin in PLUGIN_SPECS

The installer renders config.toml from PLUGIN_SPECS, which listed only
the 13 companion plugins - not grok-build-harness itself. On fresh-host
installs, the config render overwrites [plugins].enabled and drops the
harness plugin, causing it to be installed-but-not-enabled.

This was masked on existing hosts because --preserve kept the entry, but
hit reliably on fresh hosts following the documented flow (marketplace
install harness first, then run install.sh).

Fix: add grok-build-harness as the first entry in PLUGIN_SPECS so the
enabled list and install loop stay in sync (the file's own invariant:
\"one table drives both the enabled list and the install loop, so the two
can never drift apart\").

Verified: dry-run shows 14 plugins (was 13); generate-config.py render
includes grok-build-harness in [plugins].enabled.

Also adds handoff document at
projects/agent-skills/work/2026-08-10-grok-build-harness-plugin-enabled-handoff/handoff.md
documenting root cause, fix approach (A over B/C), verification, and
next steps."
```

Expected: clean squash-merge, single commit on `main` containing both the
one-line fix and the handoff document.

- [ ] **Step 3: Run the harness test suite to confirm the fix landed**

```bash
bash scripts/test-grok-build-harness.sh 2>&1 | tail -5
```

Expected: `=== Results: 46 passed, 0 failed ===`

- [ ] **Step 4: Push to origin/main**

```bash
git push origin main
```

Expected: push succeeds. If it fails (branch moved, permissions), fall back to PR: `gh pr merge 8 --squash`.

- [ ] **Step 5: Confirm CI is green on main**

```bash
gh run list --branch main --limit 1 --json status,conclusion,name
```

Expected: `conclusion: "success"` for `Verify agent-skills`.

---

### Task 2: Add regression test for harness plugin in enabled list

**Files:**
- Modify: `scripts/test-grok-build-harness.sh:72` (insert after the "with keys" config-generation block)
- Test: the same file (self-contained assertions)

**Interfaces:**
- Consumes: `run_generate` helper function (defined at line ~56 of the test file), `assert_contains` helper (line ~35)
- Produces: Two new assertions that fail if `grok-build-harness` is ever dropped from the enabled list or the dry-run plugins line

- [ ] **Step 1: Write the failing test (config-generation assertion)**

Insert after line 72 (the `assert_contains "with-keys: enabled list substituted"` block), before the `# --- config generation: env-only ---` comment at line 74:

```bash
# --- regression: harness plugin must be in [plugins].enabled ---------
run_generate "$TEST_ROOT/harness-enabled.toml" --enabled "grok-build-harness,superpowers"
assert_contains "harness plugin in enabled list" \
  "$(cat "$TEST_ROOT/harness-enabled.toml")" '"grok-build-harness"'
```

- [ ] **Step 2: Write the failing test (dry-run plugins-line assertion)**

Find the dry-run section (line ~157, the `DRY_OUT=` assignment). After the existing dry-run assertions (after `assert_eq "dry-run: writes nothing"` at line ~163), add:

```bash
assert_contains "dry-run: harness plugin listed first" \
  "$DRY_OUT" "plugins: grok-build-harness superpowers"
```

- [ ] **Step 3: Run the test suite to verify both new assertions pass**

```bash
bash scripts/test-grok-build-harness.sh 2>&1 | tail -10
```

Expected: `=== Results: 48 passed, 0 failed ===` (46 existing + 2 new).

If any test fails, inspect the output, fix the assertion, and re-run.

- [ ] **Step 4: Commit**

```bash
git add scripts/test-grok-build-harness.sh
git commit -m "test: regression test for harness plugin in [plugins].enabled

Asserts grok-build-harness appears in the rendered [plugins].enabled
list and is listed first in the dry-run plugins line. Closes the test
gap that allowed the PLUGIN_SPECS omission to ship undetected."
```

---

### Task 3: Update design doc plugin count

**Files:**
- Modify: `skills/grok-build-harness/docs/harness-design.md:80-95` (the "Companion plugin set" section)

**Interfaces:**
- Consumes: the fix from Task 1 (14 plugins in PLUGIN_SPECS)
- Produces: design doc accurately reflects 14 enabled plugins including the harness

- [ ] **Step 1: Update the plugin count and table**

In `skills/grok-build-harness/docs/harness-design.md`, find the "Companion plugin set" section (line ~80). Change:

```
The 13 enabled plugins and their originating marketplaces (verified from
`~/.grok/installed-plugins/registry.json`, 2026-08-08):

| Marketplace | Plugins |
|---|---|
| `karlorz/agent-skills` | simplify, deep-research, dev-loop, claude-md-management, playwright-cli, grill-me, hermes-cli, codebase-architecture |
```

to:

```
The 14 enabled plugins and their originating marketplaces (verified from
`~/.grok/installed-plugins/registry.json`, 2026-08-08):

| Marketplace | Plugins |
|---|---|
| `karlorz/agent-skills` | grok-build-harness, simplify, deep-research, dev-loop, claude-md-management, playwright-cli, grill-me, hermes-cli, codebase-architecture |
```

- [ ] **Step 2: Run the metadata tests to confirm no inventory drift**

```bash
bash scripts/test-plugin-metadata.sh 2>&1 | tail -5
bash scripts/test-dev-loop-preflight-inventory.sh 2>&1 | tail -5
```

Expected: `3 passed, 0 failed` and `test-dev-loop-preflight-inventory: ok`.

- [ ] **Step 3: Commit**

```bash
git add skills/grok-build-harness/docs/harness-design.md
git commit -m "docs: update companion plugin count to 14 (includes harness)

The grok-build-harness plugin itself is the first entry in PLUGIN_SPECS
and appears in [plugins].enabled. The design doc previously counted only
the 13 companion plugins, omitting the harness itself."
```

---

### Task 4: Push to main and verify full suite

**Files:**
- No file changes — push and final verification only

**Interfaces:**
- Consumes: commits from Tasks 2 and 3 on local `main`
- Produces: all changes on `origin/main` with green CI

- [ ] **Step 1: Run the full test suite locally**

```bash
bash scripts/test-grok-build-harness.sh 2>&1 | tail -5
bash scripts/test-plugin-metadata.sh 2>&1 | tail -5
bash scripts/test-dev-loop-preflight-inventory.sh 2>&1 | tail -5
```

Expected: `48 passed, 0 failed`, `3 passed, 0 failed`, `ok`.

- [ ] **Step 2: Push to origin/main**

```bash
git push origin main
```

Expected: push succeeds. If it fails, create a PR with `gh pr create --base main`.

- [ ] **Step 3: Confirm CI is green**

```bash
gh run list --branch main --limit 1 --json status,conclusion,name
```

Expected: `conclusion: "success"` for `Verify agent-skills`.