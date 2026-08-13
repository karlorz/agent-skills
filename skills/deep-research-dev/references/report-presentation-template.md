# Report Presentation Template — deep-research-dev

This is the source of truth for deep-research-dev (D) report presentation and
its source ledger. D composes every normal report from this bundled template.
The template is language-adaptive and applies to every research topic. Both
entrypoints implement this contract.

## Bundled default

- **D defaults to the bundled template** at
  `references/report-presentation-template.md`; no S report search or copy is
  performed by default. Only explicit interactive `--reuse-s-template` use may
  alter the narrative shape.
- There is no numbered top-N source list. The complete immutable source ledger
  below replaces it.

## Required identity and navigation

The report begins with these elements in exactly this order:

```markdown
**Status: Verified**

# <localized report title>

> Evidence cutoff: YYYY-MM-DD · Verification date: YYYY-MM-DD · Scope: <concise scope>

**This report covers**
1. <localized topic>
2. <localized topic>
3. <localized topic>
```

Use `**Status: Partial**` only for an actual evidence gap. The status header
is exact; reasons belong in `## Coverage and uncertainty`, not beside the
status. The H1 makes a copied report self-identifying. The cutoff is the
user-specified date when one exists; otherwise state the latest date the
retained evidence is intended to cover. The verification date is when the
sources were checked.

The compact navigation is not an H2. It is a topic map, not a second summary;
keep it to three or four labels and omit categories outside the user's scope.

## Adaptive numbered topical narrative

Build a **language-adaptive numbered topical narrative**. Every narrative
section is an H2 with a plain ASCII ordinal prefix: `## 1. <title>`,
`## 2. <title>`, ... . Use `1.`, `2.`, ... in every report language; numbering
is deliberately not localized. Only the title text localizes.

Suggested evidence-first shape (titles shown in English):

1. Decision summary
2. Scope and method
3. Selected topical evidence sections
4. Risks and limitations
5. Conclusion and next steps

Use the smallest useful shape: merge overlapping sections and drop sections
the topic does not warrant. There are **no filler sections**. A report may
have fewer narrative sections, but the sections it has must use sequential
plain ASCII ordinals beginning at `## 1. Decision summary`. The four fixed
audit headings below are the only unnumbered H2 exceptions; every other H2 is
a numbered narrative section.

### Keep each layer distinct

- **TL;DR** contains only three to five decision-relevant facts.
- The numbered narrative explains facts once. It should not repeat dates,
  metrics, or caveats already established in an earlier narrative section.
- Use one canonical timeline table for dates. A Mermaid timeline or Gantt may
  be included only when it is **visual-only**: it must mirror the canonical
  timeline table and must not introduce additional dates or claims.
- The freshness block is an audit, not a second explanation.
- **Coverage contains only** classifications, gaps, degradations, dropped
  items, execution-topology notes, and requested topic-inherent unknowns.

## Fixed audit block

Emit these literal H2 headings exactly once and in this order:

1. `## Freshness & Verification Status`
2. `## Verification Methods`
3. `## Sources`
4. `## Coverage and uncertainty`

Their placement does not alter status semantics. `Partial` remains based on
evidence gaps, not formatting quality.

### Freshness & Verification Status

Include the selected source-plan tags, freshness channel, fallback or
degradation, material conflicts, stale-cache warnings, and a compact
key-claims table:

```markdown
| Claim | Status | Source route | Notes |
| --- | --- | --- | --- |
| <claim> | externally verified / locally verified only / unverified | <route> | <audit note> |
```

This section verifies state; it does not restate the narrative. Do not write
numeric tool-count claims such as `web_fetch ×5` in the report. Exact tool
counts are derived from **capture metadata**, never narrated by the model.

### Verification Methods

State reproducible checks: canonical source URLs, tools or commands, and
common wrong methods. Keep verification advice separate from the Findings
narrative.

## Sources

This section is the complete **immutable source ledger** for retained evidence
and every retained material conflict or degradation. It uses this exact
six-column header:

| Ref | Role / retained use | Publisher / title | Source type | Accessed | Exact URL or local record |
| --- | --- | --- | --- | --- | --- |
| S1 | direct-fetch; supports retained claim | Publisher / title | primary | YYYY-MM-DD | https://example.invalid/source |

- In-body `[S<n>]` markers map to exactly one stable row. Every ledger row is
  cited in the report body or its role explicitly says
  `retained-without-citation` and explains why it remains.
- In every report language, the linter-facing source identifiers are **literal English labels**: `direct-fetch`, `search-summary only`, `local-record:`, and `retained-without-citation`. Localize the surrounding explanation, not these exact tokens.
- In every report language, `Evidence gap` is the literal English classification
  label used by the linter; localize its explanatory text, not the label.
- Every retained external third-party claim has its **exact external URL**.
  The role identifies whether it was `direct-fetch` or `search-summary only`.
  A `search-summary only` row is not treated as a fetched source and must be
  disclosed by its `S<n>` identifier in Coverage.
- Repository or local evidence has an explicit **local record**, never a
  fabricated URL. The final column begins `local-record:`. A local record must
  either be inside the ignored run-artifact directory or include
  `sha256=<64-hex-content-hash>` beside its path. Do not retain a volatile
  `/tmp` path without one of those durability proofs.
- Source type remains `primary`, `secondary`, `repository`, or `other`.
  Unused or unopened search results are not ledger rows.
- Once synthesized, the ledger is **immutable**. Refinement may improve prose
  outside it but must not trim, delete, renumber, merge, or change ledger rows,
  URLs, roles, or a material conflict. It must not be trimmed to a smaller
  top-N list.

`skills/deep-research-dev/scripts/lint-report.py` validates the generated
report's heading order, ledger, citations, disclosure labels, local-record
durability, cutoff declaration, and status/coverage consistency before a
capture is reviewed.

### Coverage and uncertainty

Bullet every dropped claim (with reason), planned question with no usable
output, source-plan degradation, synthesis fallback, execution-topology note,
and topic-inherent unknown. Classify every item as one of:

- **Topic-inherent unknown** — primary retained evidence explicitly leaves a
  requested fact undecided. Report it accurately; it does not itself require
  `Partial`.
- **Execution topology** — informational, such as inline fallback. It is not
  an evidence gap by itself.
- **Evidence gap** — missing answer-critical evidence, unresolved material
  conflict, unsupported retained claim, an answer-critical claim without
  external verification, a required source route that failed without a
  substitute, unusable planned output, or invalid synthesis. An evidence gap
  requires `Partial`.

In every report language, `Evidence gap` is the literal English classification
label used by the linter; localize its explanatory text, not the label.

If the status is `Partial`, Coverage names the actual **Evidence gap**. If the
status is `Verified`, Coverage must not call a topic-inherent unknown an
evidence gap. If no classification remains, state that all planned questions
returned usable research and every retained claim has non-empty external
verification.

## Structurally valid fallback

This is a **structurally valid fallback**, not an isolated bullet list. When normal synthesis is empty, malformed, omits required content,
or has invalid Mermaid syntax, return a `Partial` report with the **Status header, H1 title**, `## 1. Findings`, the preserved retained ledger, and **all four audit headings**. Its Coverage has an **explicit evidence-gap Coverage entry** naming the invalid synthesis or unavailable evidence. Never return an
empty report. Preserve the ledger rows accumulated before synthesis; do not
invent citations, source facts, URLs, or conclusions.

## --reuse-s-template (optional, interactive only)

`--reuse-s-template` may change narrative **structure only**:

- Only explicit interactive use — a human passes the flag in an attended
  session — may discover a relevant accessible S outline and reuse its heading
  order/categories. Reused headings still receive D's plain ASCII ordinal H2
  prefixes. The reuse is **structure-only**: D **cannot carry S facts/sources/conclusions** — no S facts, sources, citations, URLs, names,
  dates, metrics, or prose may enter the D report.
- If no usable S outline applies, D **falls back to the bundled template** and
  reports the fallback.
- The flag is **disabled under `--unattended`**; unattended runs always use
  the bundled presentation. That fallback is informational only, not an
evidence gap or degradation.
