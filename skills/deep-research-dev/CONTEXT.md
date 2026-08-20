# Deep research (dev lane)

Language for the experimental `deep-research-dev` skill (D), its daily usage
review loop, and the later promotion of D into production `deep-research` (S).

## Language

**D (dev lane)**:
The experimental plugin/skill `deep-research-dev`. It is a fork of frozen production `deep-research` used to measure and improve the research contract before promotion.
_Avoid_: production deep-research, builtin, S

**S (production skill)**:
The frozen marketplace skill `deep-research`. It is not edited during the D evaluation program.
_Avoid_: D, builtin, production migration as a synonym for “edit S”

**Builtin B**:
The grok-build host `/deep-research` workflow. Matching B is optional for promotion.
_Avoid_: S, D

**Usage ledger**:
The append-only host-local JSONL of D invocation records at `~/.grok/deep-research-dev-usage/ledger.jsonl`. Each record is one run, not one scored eval cell.
_Avoid_: telemetry, analytics, eval matrix, vault log

**Usage record**:
One JSON object in the usage ledger. It stores invocation mode, output mode, a truncated query, the query fingerprint, lint outcome, and timing. It does not store the full prompt.
_Avoid_: cell, score, transcript

**Query fingerprint**:
The SHA-256 of the full query plus the first 200 characters after secret redaction. The fingerprint identifies repeats; the truncation is what a human reviews.
_Avoid_: full query, prompt dump

**Daily usage review**:
A harvested markdown summary for one UTC day under the ignored repository path `.superpowers/sdd/deep-research-dev-usage/reviews/`. It merges the host-local usage ledger with smoke/eval `meta.json` files. It is not a vault page.
_Avoid_: retro, query page, matrix.md

**Smoke harvest**:
Existing ignored cell directories that already contain `cell.md`, `meta.json`, and `lint.json`. Review reads them; it does not treat them as the usage ledger.
_Avoid_: usage record, vault capture

**Structure-only repair**:
A deterministic rewrite that may only restore presentation tokens: Status-then-H1 order, English role labels (`direct-fetch`, `search-summary only`), and a `local-record:` prefix. It must not change Status, claims, URLs, Coverage, or evidence.
_Avoid_: lint rewrite, evidence repair, making lint pass

**Promotion**:
Copying measured D behavior into S after D beats S on the locked eval matrix. Marketplace presence of a D beta is not promotion.
_Avoid_: migration, ship it, replace S

**Wiki corpus comparison**:
Counting vault query/raw pages tagged or ingested as deep-research. It is not a promotion signal because D and S share `ingested_by: "deep-research"`.
_Avoid_: A/B evidence, merge bar, eval matrix

**Historical cell**:
An eligible eval cell captured under a retired model pin (`deepseek-v4-flash` / `deepseek-v4-flash-max`). Directional only; it must not enter a new median or winner rule.
_Avoid_: baseline, current scoreboard

**Matrix model pin**:
The parent catalog id for S/D recapture. This cycle: `flash-max`. Smoke `meta.json` must still record the observed wire `actual_model`.
_Avoid_: host default, `deepseek-v4-flash`, grok-4.6 as the matrix pin

**Capture-validity harden**:
Making a run scorable: one plugin winner, recorded duration, persisted lint errors, correct plugin version. Not a report-quality rewrite.
_Avoid_: promotion, evidence repair, making lint pass by changing claims

**Orchestrator module**:
The single canonical Phase 1–6 research workflow defined in `skills/deep-research-dev/SKILL.md`. It owns the source-triage, claim discipline, synthesis, refinement, routing, and reporting recipes.
_Avoid_: agent twin, dual-file workflow, skill-only feature

**Host adapter**:
The thin entrypoint in `agents/deep-research-dev.md` that Reads and follows `skills/deep-research-dev/SKILL.md` rather than duplicating the research workflow.
_Avoid_: agent twin, standalone agent recipe, fork of SKILL.md
