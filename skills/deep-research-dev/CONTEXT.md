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
