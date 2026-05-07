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

## Write Pipeline (Strict Order)

1. **Validate**: `skillwiki validate <page>` -- STOP if non-zero
2. **Write page**: Save to `concepts/<slug>.md` (or `comparisons/`, `queries/`, `entities/`)
3. **Update index**: Add entry to `index.md`
4. **Append log**: Add entry to `log.md`

**Forbidden**: Never update index.md or log.md before validate passes.

## Safety Rules

1. Always validate before writing index/log
2. Never overwrite existing pages without user confirmation
3. Source failures keep other sources; note in report
4. Respect `--no-raw` for quick lookups (no provenance chain)
5. Log all vault resolution and routing decisions
