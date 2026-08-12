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

Build a **language-adaptive numbered topical narrative**: every narrative
section is an H2 heading with a plain ASCII ordinal prefix: `## 1. <title>`,
`## 2. <title>`, ... . Use `1.`, `2.`, ... in every report language — the
numbering is deliberately not localized (a Traditional-Chinese report still
uses `## 1. <title>`, never `## 一、<title>`). Only the narrative title text
localizes to the report language (use the user's language, or `skillwiki lang`
when available).

Suggested evidence-first shape (titles shown in English; emit each title as a
sequential numbered H2 — e.g. `## 1. Decision summary` — in the report
language):

1. Decision summary
2. Scope and method
3. 3–8 selected topical evidence sections
4. Risks and limitations
5. Conclusion and next steps

Merge sections when topics overlap and drop sections the topic does not
warrant; use fewer/merged sections when appropriate. There are **no filler sections**; never add a section merely to reach a fixed count — 1 to 10 is a
maximum illustrative shape, not a quota. A report may have fewer narrative
sections, but the sections it has must use sequential plain ordinals. The
four fixed audit headings below are the only unnumbered H2 exceptions; every
other H2 in the report is a numbered narrative section.

## Fixed audit block

The four audit headings below are fixed and literal. Emit them exactly as
written — unnumbered, at `##` level, in this order — in every report. Their
placement must not compromise strict status semantics: `Status: Partial`
remains based on evidence gaps, not on formatting quality.

## Freshness & Verification Status

- Emit `**Status: Verified**` at the top of the report if every retained
  claim carries non-empty external verification and no evidence gaps remain;
  emit `**Status: Partial**` otherwise, listing only the actual gaps inline.
  A **topic-inherent unknown** is a requested fact that primary retained
  evidence explicitly leaves undecided (for example, a consultation's final
  adoption decision or future constituent list). It must be reported in
  Coverage and uncertainty but **does not by itself require `Partial`**.
  Status is **Partial** if a planned question returned no usable output; a
  retained claim is unsupported, malformed, or dropped; an answer-critical
  claim lacks external verification; a material source conflict remains
  unresolved; a **required source route failed without a substitute**;
  or synthesis produced an invalid or empty body. The status line must name only categories actually present in Coverage and uncertainty — do not hand-count claims or state a specific number when Coverage records a different count. Better formatting never upgrades `Partial` — status stays based on evidence gaps.
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
- Classify each item as a **topic-inherent unknown**, **execution topology**
  note, or **evidence gap**. A topic-inherent unknown is explicitly left
  undecided by primary retained evidence and is directly relevant to the
  user's request; report it accurately, but it **does not by itself require
  `Partial`**. Execution topology is informational (for example, inline
  fallback). Evidence gaps include a missing source, unresolved material
  conflict, unsupported retained claim, an answer-critical claim without
  external verification, or a **required source route failed without a
  substitute**; only evidence gaps can support `Partial`.
- If no topic-inherent unknowns or evidence gaps remain, state: "All planned
  questions returned usable structured research, and every retained claim
  carries non-empty external verification."

## --reuse-s-template (optional, interactive only)

`--reuse-s-template` may change the narrative **structure only**:

- Only explicit interactive use — a human passes the flag in an attended
  session — may discover a relevant accessible S outline and reuse its
  heading order/categories. Reused narrative headings still get D's plain
  ASCII ordinal H2 prefixes — structure reuse never removes the numbering.
  The reuse is **structure-only**: D **cannot carry S facts/sources/conclusions** — no S facts, sources, citations,
  URLs, names, dates, metrics, or prose may enter the D report.
- If no usable S outline applies, D **falls back to the bundled template**
  and reports the fallback.
- The flag is **disabled under `--unattended`**; unattended runs always use
  the bundled presentation. That presentation fallback is informational
  only — it is not an evidence gap and not a degradation.
