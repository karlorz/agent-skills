# Vault Pipeline Integration

This reference documents the skillwiki vault integration used when `--vault` flag is active. It covers raw capture, schema validation, write pipeline, and related-pages search — not synthesis (which SKILL.md defines).

## Prerequisites

- `skillwiki path` resolves successfully
- `SCHEMA.md`, `index.md`, `log.md` present in vault
- If NO_VAULT_CONFIGURED: STOP and advise user to run `skillwiki init`

## Pre-Orientation Reads (Mandatory Before Writes)

1. `SCHEMA.md` -- vault structure, taxonomy, conventions
2. `index.md` -- existing pages to cross-link
3. Last 20 entries of `log.md` -- recent vault activity

## Output Language

Run `skillwiki lang` at start. Generate page prose in resolved language. Frontmatter keys, file names, schema headers, citation markers, and wikilink slugs remain English.

## Related-Pages Search

Before writing the typed page, scan the vault for existing related content:

1. Search `index.md` for pages with overlapping keywords or tags
2. Check `concepts/` and `queries/` for related topics
3. Add wikilinks to discovered pages in the Related Notes section
4. This enables cross-linking that keeps the vault navigable

## Raw Capture

For each source, follow the raw-capture pattern below:

1. **URL sources**: Write to `raw/articles/<slug>.md`
   - Frontmatter per `RawSourceSchema`: title, source_url, ingested, ingested_by: "deep-research", sha256
   - Compute sha256 via `skillwiki hash <raw-file>`

2. **Context7 results**: Write extract to `raw/articles/<library-id>-docs.md`
   - Frontmatter: source_url: null (or Context7 library URL), ingested, sha256

3. **DeepWiki results**: Write Q&A to `raw/articles/<repo>-deepwiki.md`
   - Frontmatter: source_url: <repo-url>, ingested, sha256

**Stop conditions**: If raw capture fails (hash mismatch, write error), STOP and surface error.

## Typed Knowledge Page

Compose typed-knowledge page per `TypedKnowledgeSchema`:

```yaml
---
title: "<Topic Title>"
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: concept  # or comparison, query, entity
tags:
  - research
  - <domain-tag>
sources:
  - "^[raw/articles/slug.md]"
  - "^[raw/articles/library-docs.md]"
confidence: medium  # high if 3+ diverse sources, low if single source
provenance: research
---
```

**Page type selection**:
| Research output | Type |
|-----------------|------|
| General topic research | concept |
| Side-by-side comparison | comparison |
| Question-answer focus | query |
| Project/tool summary | entity |

**Citation format**: Use `^[raw/articles/slug.md]` markers at paragraph end.

**Body sections**: Follow the synthesis structure defined in SKILL.md Phase 3.

**Diagram placement in page**: If the synthesis includes a Mermaid diagram, place it immediately after the **Overview** section and before the **Findings** section. This gives the wiki reader a visual anchor before diving into source details. If no diagram, omit the section entirely — do not leave a placeholder heading.

## Reusable Research And Follow-Up Queue

When a query page contains a reusable pattern, create a companion
`concepts/<slug>.md` page. The query page answers the specific research
question; the concept page preserves the transferable rule, compatibility
mapping, or implementation pattern for future sessions.

If the research also produces actionable follow-up work, queue that work only
after every typed page validates. Never create `status: planned` work directly
from research output.

Use this schema-adaptive queue:

1. Probe whether the local skillwiki schema accepts a non-executing proposed
   work item by validating a candidate `spec.md` with `status: proposed`.
2. If validation passes, create proposed project work items and validate each
   `spec.md`.
3. If validation rejects `status: proposed`, `kind`, or lifecycle fields,
   queue follow-ups as ad-hoc captures under `raw/transcripts/`.

Raw follow-up captures use this frontmatter:

```yaml
---
source_url:
ingested: YYYY-MM-DD
kind: task          # task | bug | idea | note
project: "[[slug]]"
---
```

Use `task` or `bug` for concrete follow-ups that should surface as unclaimed
transcripts. Use `idea` or `note` for exploratory or context-only findings
that should be preserved but not automatically executed.

## Write Pipeline (Strict Order)

1. **Write draft page**: Save to `concepts/<slug>.md` (or `comparisons/`, `queries/`, `entities/`)
2. **Validate**: `skillwiki validate <page>` -- STOP if non-zero
3. **Write and validate companion pages**: create any reusable `concepts/` companion and validate it before index/log updates
4. **Queue follow-ups**: create schema-compatible proposed items or raw transcript captures, then validate each queued artifact
5. **Update index**: Add typed-page entries to `index.md`
6. **Append log**: Add entry to `log.md`

**Forbidden**: Never update index.md or log.md before validate passes.

## Safety Rules

1. Always validate typed pages and queued follow-ups before writing index/log
2. Never overwrite existing pages without user confirmation
3. Source failures keep other sources; note in report
4. Respect `--no-raw` for quick lookups (no provenance chain)
5. Log all vault resolution and routing decisions
