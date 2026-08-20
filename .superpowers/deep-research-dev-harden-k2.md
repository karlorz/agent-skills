---
title: "Plan: D capture-validity harden + S/D K=2 on flash-max"
name: deep-research-dev-harden-k2-plan
status: planned
created: 2026-08-20
updated: 2026-08-20
---

# Plan

Work item:
`projects/agent-skills/work/2026-08-20-deep-research-dev-harden-k2/`

Redirect:

- spec → vault work-item `spec.md`
- plan → this file

Do not edit production `skills/deep-research/`. Do not merge D into S. Do not
fold 2026-08-12 `deepseek-v4-flash` cells into the new median.

Repo for D code: `karlorz/agent-skills`, path
`skills/deep-research-dev/`. The current checkout branch
`docs/cursor-plugin-chain-and-exam` is **wrong** for this cycle — start a
D-related branch from the D tip (`171968a` or current `main` that contains
beta.4).

## Current gaps (disk, not wiki)

Smoke already records duration, `--lint-json`, and `plugin_version` from
`plugin.json` (`skills/deep-research-dev/scripts/smoke-ephemeral.sh`). Live
Phase 6 does not:

- SKILL.md Phase 6 says “lint result, and duration **if known**” — agents omit
  `--duration-s`, pass `--lint-ok false` with empty `lint_errors`, and skip
  `--plugin-version` (or leak SkillWiki `0.10.49`).
- `record-usage.py` accepts `--lint-ok false` with no `--lint-json` and stores
  `lint_errors: []` (`lint_fields()`).
- `smoke-ephemeral.sh` lints the extracted cell and **does not** run
  `repair-report-structure.py`.
- Default `MODEL` in smoke and `S_LANE_MODEL` in the ignored S runner is still
  `deepseek-v4-flash`.
- Two D installs exist; `grok inspect` currently selects marketplace
  `deep-research-dev-37ccfa64`, not the checkout.

## Task 1 — Branch and one plugin winner (C1)

1. In `agent-skills`, create branch
   `feat/deep-research-dev-harden-k2-flash-max` from the commit that has
   `0.1.0-beta.4` (`171968a` / current main), **not** from
   `docs/cursor-plugin-chain-and-exam`.
2. After Tasks 2–4 land, install the checkout as the only D plugin:
   - `grok plugin install "$PWD/skills/deep-research-dev" --trust`
   - Uninstall or disable the extra copy (`deep-research-dev-5eb04b3c` and/or
     marketplace `37ccfa64`) until `grok inspect --json` returns **exactly
     one** skill named `deep-research-dev` whose `source.path` is under that
     checkout.
3. Fail closed: if inspect still shows two paths, do not start Task 6 or 7.

## Task 2 — Phase 6 usage contract (C2, C3, C4)

Files:

- `skills/deep-research-dev/skills/deep-research-dev/SKILL.md` (Phase 6)
- `skills/deep-research-dev/agents/deep-research-dev.md` (same paragraph)
- `skills/deep-research-dev/scripts/record-usage.py`
- `skills/deep-research-dev/scripts/test-record-usage.py`

Changes:

1. Replace “duration if known” / “lint result” with a **required argv**:
   - `--duration-s` (number; agent records wall clock from skill start)
   - `--lint-json <path>` (the `lint-report.py` JSON, after repair/re-lint)
   - `--plugin-version` read from the discovered plugin
     `.claude-plugin/plugin.json` `version` field (must be `0.1.0-beta.4`
     this cycle). Never `skillwiki --version`.
2. `record-usage.py`: if `lint_ok` is false and `lint_errors` is empty, exit 2.
   `--lint-ok false` without `--lint-json` is invalid. Keep `--lint-json` as
   the source of errors when present.
3. Update `test-record-usage.py`:
   - `--lint-ok false` alone → exit 2, no ledger row.
   - `--lint-json` with `ok: false` still writes errors (existing case).
   - Add a case that `--plugin-version` and `--duration-s` round-trip.

Do not change ledger schema. Do not write the ledger into a vault.

## Task 3 — Smoke: flash-max default + lint → repair → re-lint (C5 path)

File: `skills/deep-research-dev/scripts/smoke-ephemeral.sh`

1. Default `MODEL` from `deepseek-v4-flash` to `flash-max`. Keep env override.
2. After the first `lint-report.py` pass, if lint reports identity / English
   role / `local-record:` prefix errors, run
   `repair-report-structure.py` on `cell.md`, then re-lint. Keep the **final**
   `lint.json` on the cell. Optionally write `lint.before.json`. Repair must
   not change Status, claims, URLs, or Coverage (existing ADR 0001).
3. Continue passing `--duration-s`, `--lint-json`, `--plugin-version` into
   `record-usage.py` (already present).
4. README smoke section: document `MODEL=flash-max` (or default).

Update `scripts/test-smoke-ephemeral.sh` only where it asserts the default
model string or needs a repair fixture. Do not weaken fail-closed plugin
selection (exit 3).

## Task 4 — Glossary, ADR, changelog note (C6)

On the D branch only:

1. Append the four terms from the spec to
   `skills/deep-research-dev/CONTEXT.md`
   (Wiki corpus comparison, Historical cell, Matrix model pin,
   Capture-validity harden). Keep `Promotion` unchanged.
2. Add `skills/deep-research-dev/docs/adr/0002-matrix-pin-flash-max.md`
   using the spec’s ADR paragraph.
3. CHANGELOG under `0.1.0-beta.4` (no marketplace bump unless execute
   decides otherwise): Phase 6 required duration/lint-json/version; smoke
   default pin `flash-max`; smoke applies structure-only repair before
   final lint.

Keep production `skills/deep-research/` and version `2.4.3` untouched.

## Task 5 — Tests

From plugin root `skills/deep-research-dev/`:

```
python3 scripts/test-record-usage.py
python3 scripts/test-repair-report-structure.py
python3 scripts/test-lint-report.py
python3 scripts/test-research-contract.py
bash scripts/test-smoke-ephemeral.sh
```

All must pass before any live grok recapture.

## Task 6 — Hstech recapture (C5)

Reuse the **exact** 2026-08-13 query string from
`.superpowers/sdd/deep-research-dev-reliability-report-lint/live-validation-20260813/`
(`cell.full.md` / headless prompt). Do not paraphrase.

```
MODEL=flash-max \
DEEP_RESEARCH_DEV_PLUGIN_ROOT=<checkout skills/deep-research-dev> \
DEEP_RESEARCH_DEV_EVIDENCE_CUTOFF=2026-08-12 \
bash skills/deep-research-dev/scripts/smoke-ephemeral.sh \
  "<exact query>" \
  <repo>/.superpowers/sdd/deep-research-dev-reliability-report-lint/live-validation-flash-max-k2/
```

Pass only if:

- inspect path is the checkout (Task 1)
- `meta.json` has numeric `duration_s`, `actual_model`, `plugin_version`
  `0.1.0-beta.4`
- final `lint.json` has no Status-then-H1, missing
  `direct-fetch`/`search-summary only`, or missing `local-record:` prefix
  errors

Leftover errors that repair is forbidden to touch are allowed and must stay
on the usage record. Do not rewrite Status/claims/URLs/Coverage.

## Task 7 — S/D K=2 recapture (12 cells)

Locked queries (verbatim from
`projects/agent-skills/work/2026-08-11-deep-research-dev-eval-matrix/suite.yaml`):

- **q1** freshness: latest stable skillwiki CLI + last two releases
- **q2** local: Grok Build builtin `/deep-research` Plan/Research/Verify/Report
- **q3** multi-claim: Claude Code plugins vs Grok Build plugins (packaging,
  install, slash naming)

Pin: parent `-m flash-max`. Record observed `actual_model` in every
`meta.json`. Do not use host default `grok-4.6` or `kimi-k3`.

Lanes:

| Lane | Slash | Runner |
|------|-------|--------|
| **D** | `/deep-research-dev:deep-research-dev --ephemeral --unattended` | `skills/deep-research-dev/scripts/smoke-ephemeral.sh` |
| **S** | `/deep-research:deep-research --ephemeral` plus prompt-equivalent unattended (S 2.4.3 has no `--unattended`) | ignored `run-s-ephemeral.sh` with `S_LANE_MODEL=flash-max` |

cwd: suite default `grok-build` checkout (required for q2 fairness).

Artifact root (gitignored, never vault):

`.superpowers/sdd/deep-research-dev-eval-matrix/eval-runs/flash-max-k2-2026-08-20/`

Cell names: `{q1,q2,q3}-{S,D}-a{1,2}/`.

Run **serially**. Do not parallelize lanes (plugin discovery + rate limits).
Budget: 12 × ~2–10 min; abort a cell at the existing 1800s timeout and keep
the failed `meta.json`.

S scoring uses ignored `assess-cell.py` (Status Verified + duration +
nonempty report). D scoring uses the same eligibility gate **plus** D
`lint.json` recorded; D lint failure does not rewrite the report. Partial /
failed / missing-duration cells go to a rejected-attempt list in this work
item, not the median.

If a lane/query cannot collect 2 eligible cells, mark that lane/query
**incomplete**, not zero. Do not relaunch B.

## Task 8 — Scoreboard (vault-normalized only)

Write `matrix.md` in **this** work item (not the 2026-08-11 folder).

Include:

- Pin `flash-max` and observed wire `actual_model`
- Eligible-only table: query, lane, attempt, structure 0–5, false_claim_flags,
  `duration_s`, quality_per_min
- Per-query median; suite majority winner
- Explicit line: 2026-08-12 deepseek cells are historical and **not** in
  these medians
- Promotion line: **no promotion** unless D beats S on majority of q1–q3
  under the locked winner rules

Raw cells stay ignored. Do not copy `cell.full.md` into the vault.

## Task 9 — Verify and stop

- `git -C <agent-skills> diff -- skills/deep-research/` is empty
- `grok inspect --json` still one D path under the checkout used for K=2
- Usage ledger rows for Tasks 6–7 have `duration_s`, `plugin_version`
  `0.1.0-beta.4`, and `lint_errors` when `lint_ok` is false
- This work item `spec.md` stays `planned`/`in-progress` until K=2 exists;
  never `completed` with a merge claim
- Parked P1–P5 remain unfixed

## Execution order

`1 → 2 → 3 → 4 → 5 → 1.install → 6 → 7 → 8 → 9`

Tasks 2–4 may be one implementer if they stay on the D plugin tree. Task 7
is operator-expensive and must not start before Task 1 inspect and Task 6
pass.

## Out of scope (repeat)

Merge D → S, edit S, B/Orca baseline, published YAML lint, PE wrapper,
unattended vault leak, `ingested_by` enum split, rewriting evidence to pass
lint.
