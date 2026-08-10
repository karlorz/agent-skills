# Handoff: grok-build-harness plugin dropped from [plugins].enabled on fresh-host installs

**Date:** 2026-08-10
**Branch:** `fix/grok-build-harness-plugin-enabled`
**PR:** https://github.com/karlorz/agent-skills/pull/8
**Status:** Open, mergeable, CI green

---

## F1: Problem statement

On fresh-host installs following the documented flow (`grok plugin install
grok-build-harness --trust` then `bash install.sh`), the harness plugin ends
up **installed-but-not-enabled**. The `/grok-build-init` skill does not load.

The plugin is present in `~/.grok/installed-plugins/` but absent from
`[plugins].enabled` in `config.toml`, so grok-build does not activate it.

---

## Root cause

`install.sh` builds `[plugins].enabled` from the `PLUGIN_SPECS` array (line
~125). That array drives **both** the plugin install loop **and** the
enabled list written to `config.toml` via `generate-config.py`. The array
listed 13 companion plugins but omitted `grok-build-harness` itself.

The `enabled` key is **template-owned** (ADR-3): `generate-config.py
--preserve` does not carry template-owned keys from the existing config.
So on every fresh-host render, the enabled list was written from `PLUGIN_SPECS`
alone — without the harness plugin — clobbering any prior entry.

**Why it was masked on existing hosts:** ADR-4's keyed-config downgrade guard
skips the config render entirely when an existing config has injected keys
(`api_key` lines) but the current run provides no keys. Most existing hosts
have keyed configs, so re-runs skip the render and the pre-existing
`grok-build-harness` entry in `enabled` survives. Fresh hosts have no
existing config, so the render always fires and always dropped the entry.

**Source-of-truth violation:** The `PLUGIN_SPECS` comment states *"one table
drives both the enabled list and the install loop, so the two can never drift
apart."* The harness was installed by the loop (via `grok plugin install
grok-build-harness --trust` before `install.sh` runs) but absent from the
enabled list — a drift the table was designed to prevent.

---

## Fix approach: A over B/C

### Approach A (chosen): Add grok-build-harness to PLUGIN_SPECS

One-line fix — add `grok-build-harness` as the first entry in `PLUGIN_SPECS`:

```diff
 PLUGIN_SPECS=(
+  "grok-build-harness|grok-build-harness|SKIP_NONE"
   "superpowers|superpowers@anthropics/claude-plugins-official|SKIP_NONE"
   ...
 )
```

The `install_plugin` loop's already-installed check (`[[ "$list" == *": $plugin ["* ]]`,
line ~271) handles the harness gracefully — it was always installed before `install.sh`
runs per the documented flow, so the loop logs "already installed, skipping"
and continues.

**Why this is correct:** it satisfies the file's own invariant. The enabled
list and install loop share one source of truth, so they can never drift.
The fix is one line, testable, and has no side effects.

### Approach B (rejected): Post-render `grok plugin enable grok-build-harness`

Add a `grok plugin enable grok-build-harness` call after config render.

**Why rejected:** it patches the symptom, not the root cause. `grok plugin
enable` re-serializes `config.toml` via `toml::to_string_pretty`, which
strips all comments from the file — destroying the template's documentation
headers. It also breaks the `--skip-plugins` / `--dry-run` / `--no-config`
contracts (the enable call needs a live grok binary and writes config
unconditionally). The two sources (PLUGIN_SPECS + the enable call) can
silently drift again.

### Approach C (rejected): Reorder render before installs

Move the `render_config` call before the plugin install loop.

**Why rejected:** does not fix the bug. The clobber happens at render time
regardless of ordering — `PLUGIN_SPECS` still omits the harness, so the
enabled list is still wrong. Reordering only changes *when* the wrong
config is written.

---

## Verification

All verification run on branch `fix/grok-build-harness-plugin-enabled`
(commit `cf92d25`):

| Check | Result |
|-------|--------|
| `test-grok-build-harness.sh` (46 assertions) | **46 passed, 0 failed** |
| `test-plugin-metadata.sh` (3 assertions) | **3 passed, 0 failed** |
| `test-dev-loop-preflight-inventory.sh` | **ok** |
| PR #8 CI (`Verify agent-skills`) | **pass** (run 31332118593) |
| PR mergeable status | **MERGEABLE / CLEAN** |

**Dry-run output** confirms 14 plugins (was 13), harness first:

```
grok-build-harness: plugins: grok-build-harness superpowers simplify deep-research dev-loop claude-md-management grill-me codebase-architecture hermes-cli skillwiki context7 vault-sync codex playwright-cli
```

**Config render** confirms `grok-build-harness` in `[plugins].enabled`:

```
enabled = ["grok-build-harness", "superpowers", "simplify", "deep-research", "dev-loop", "claude-md-management", "grill-me", "codebase-architecture", "hermes-cli", "skillwiki", "context7", "vault-sync", "codex", "playwright-cli"]
```

---

## Test gap

The existing test suite does **not** assert that `grok-build-harness`
appears in `[plugins].enabled`. The config-generation tests pass arbitrary
`--enabled` values (`"superpowers,dev-loop,skillwiki"`, `"superpowers"`,
`"a"`) — none include the harness name. The dry-run test checks for
`"superpowers simplify deep-research"` in the plugins line but not the
harness.

This is why the bug shipped: the test exercised the generation path but
never validated that the harness plugin itself lands in the enabled list.
A regression test is needed.

---

## Next steps for receiving agent

1. **Merge PR #8.** The branch is mergeable, CI is green, all local tests
   pass. Squash-merge to `main` is fine (single commit).

2. **Add a regression test** to `scripts/test-grok-build-harness.sh`. The
   test should render config with the install.sh-computed enabled list (or
   a representative subset that includes `grok-build-harness`) and assert
   the harness name appears in `[plugins].enabled`. Suggested location: after
   the existing "config generation: with keys" block (~line 72). Suggested
   assertion:

   ```bash
   # --- regression: harness plugin must be in [plugins].enabled ---------
   run_generate "$TEST_ROOT/harness-enabled.toml" --enabled "grok-build-harness,superpowers"
   assert_contains "harness plugin in enabled list" \
     "$(cat "$TEST_ROOT/harness-enabled.toml")" '"grok-build-harness"'
   ```

   Optionally, also add a dry-run assertion that the plugins line starts
   with `grok-build-harness`:

   ```bash
   assert_contains "dry-run: harness plugin listed first" \
     "$DRY_OUT" "plugins: grok-build-harness superpowers"
   ```

3. **Update the design doc** (`skills/grok-build-harness/docs/harness-design.md`):
   the "Companion plugin set" section says "13 enabled plugins" — this is
   now 14 (the harness itself was always enabled at runtime via the
   pre-install step, but was missing from the config template's enabled
   list). Update the count and add `grok-build-harness` to the
   `karlorz/agent-skills` row in the plugin table.

4. **Run the full test suite** after the regression test addition:
   ```bash
   bash scripts/test-grok-build-harness.sh
   bash scripts/test-plugin-metadata.sh
   bash scripts/test-dev-loop-preflight-inventory.sh
   ```

5. **Push directly to `main`** per the repo's main-first policy. Create a
   PR only if direct push fails.