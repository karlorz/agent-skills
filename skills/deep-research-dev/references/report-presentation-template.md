# Report Presentation Template — deep-research-dev

Source of truth for deep-research-dev (D) report presentation and the source
ledger. D composes every report from this bundled template. The template is
general-purpose and language-adaptive: it applies to any research topic and to
any report language. Both entrypoints (the slash skill `SKILL.md` and the
direct agent `deep-research-dev.md`) implement exactly this contract.

## Bundled default

- **D defaults to the bundled template** at
  `references/report-presentation-template.md`; no S report search or copy is
  performed by default. Only an explicit interactive `--reuse-s-template`
  invocation (see the last section) may alter the narrative shape.
- There is no other presentation template; if an old numbered top-N source
  list survives anywhere, it is obsolete and must be replaced by the
  immutable source ledger below.

## Adaptive numbered topical narrative

Build a **language-adaptive numbered topical narrative**: sections are
numbered and topical, and their labels localize to the report language (use
the user's language, or `skillwiki lang` when available).

Suggested evidence-first shape:

1. Decision summary
2. Scope and method
3. 3–8 selected topical evidence sections
4. Risks and limitations
5. Conclusion and next steps

Merge sections when topics overlap and drop sections the topic does not
warrant; use fewer/merged sections when appropriate. There are **no filler sections**; never add a section merely to reach a fixed count — 1 to 10 is a
maximum illustrative shape, not a quota. The narrative sections are numbered;
the fixed audit block below stays unnumbered and literal.

## Fixed audit block

The four audit headings below are fixed and literal. Emit them exactly as
written — unnumbered, at `##` level, in this order — in every report. Their
placement must not compromise strict status semantics: `Status: Partial`
remains based on evidence gaps, not on formatting quality.

## Freshness & Verification Status

- Emit `**Status: Verified**` at the top of the report if every retained
  claim carries non-empty external verification and no coverage gaps remain;
  emit `**Status: Partial**` otherwise, listing the gaps inline. Status is
  **Partial** if any of: a question returned no usable output; a claim was
  dropped; an uncertainty was reported; synthesis produced an invalid or
  empty body; a source-plan channel failed without a substitute. Better
  formatting never upgrades `Partial` — status stays based on evidence gaps.
- Include the selected source-plan tags, the freshness channel used,
  fallback/degradation notes, source conflicts, stale local cache warnings,
  and a compact key-claims audit table: `Claim | Status | Source route |
  Notes`, with `source_type` in the source-route column where useful.

## Verification Methods

- Document how to verify or reproduce the findings: the correct tools or
  commands, common wrong verification methods and why they fail, and links to
  canonical reference pages. Research that documents WHAT was found but not
  HOW to verify it creates fragile knowledge.

## Sources

Complete **immutable source ledger** — the only source list in the report (a
numbered top-N list is not used). The ledger includes all **retained
evidence**: every retained external third-party claim carries its **exact external URL**; local/repository evidence carries an explicit **local record** (path, and revision if available) — never a fabricated URL. It also
includes every external material conflict/degradation that survived
synthesis. Unused or unopened search results are not ledger rows.

| Ref | Role / retained use | Publisher / title | Source type | Accessed | Exact URL or local record |
| --- | --- | --- | --- | --- | --- |
| `S1` | supports retained claim | Publisher / doc title | primary | YYYY-MM-DD | exact URL or `path@revision` |

- In-body `[S<n>]` markers map to exactly one stable row; every marker
  resolves to exactly one ledger row and every retained row is referenced
  (or explicitly retained without citation).
- Once synthesized, the ledger is **immutable**: refinement may improve the
  surrounding prose but must not trim, delete, renumber, merge, or change
  ledger rows, URLs, or roles, and must not hide a material conflict. The
  ledger must not be trimmed to a smaller top-N.
- Source type uses the claim-discipline vocabulary: `primary`, `secondary`,
  `repository`, or `other`.

## Coverage and uncertainty

- Bullet every dropped claim (with reason), every question that returned no
  usable output, every source-plan degradation, and every synthesis
  fallback.
- Distinguish `execution topology` (informational — e.g., inline fallback)
  from actual evidence gaps (missing source, unresolved material conflict,
  answer-critical claim without external verification). Only evidence gaps
  can support `Partial`; topology notes are informational only.
- If the list is empty, state: "All planned questions returned usable
  structured research, and every retained claim carries non-empty external
  verification."

## --reuse-s-template (optional, interactive only)

`--reuse-s-template` may change the narrative **structure only**:

- Only explicit interactive use — a human passes the flag in an attended
  session — may discover a relevant accessible S outline and reuse its
  heading order/categories. The reuse is **structure-only**: D **cannot carry S facts/sources/conclusions** — no S facts, sources, citations,
  URLs, names, dates, metrics, or prose may enter the D report.
- If no usable S outline applies, D **falls back to the bundled template**
  and reports the fallback.
- The flag is **disabled under `--unattended`**; unattended runs always use
  the bundled presentation. That presentation fallback is informational
  only — it is not an evidence gap and not a degradation.
