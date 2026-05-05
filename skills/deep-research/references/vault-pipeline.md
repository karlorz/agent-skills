# Vault Pipeline Integration

This reference documents the full skillwiki vault integration used when `--vault` flag is active.

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

## Synthesis (Typed Knowledge Page)

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

**Body sections**:
1. **TL;DR** -- 3-5 bullets of key findings
2. **Overview** -- 1-2 paragraph synthesis
3. **Mermaid diagram** -- when applicable (architecture, flow, relationships)
4. **Research Findings** -- collapsible callouts per source type
   - `> [!abstract]- Web Search Findings`
   - `> [!info]- Context7 Documentation`
   - `> [!tip]- DeepWiki Repository Insights`
5. **Synthesis** -- merged analysis with patterns, recommendations, caveats
6. **Related Notes** -- wikilinks to existing vault pages
7. **Sources** -- numbered list with access dates, plus Context7/DeepWiki citations

**Citation format**: Use `^[raw/articles/slug.md]` markers at paragraph end.

## Write Pipeline (Strict Order)

1. **Validate**: `skillwiki validate <page>` -- STOP if non-zero
2. **Write page**: Save to `concepts/<slug>.md` (or `comparisons/`, `queries/`, `entities/`)
3. **Update index**: Add entry to `index.md`
4. **Append log**: Add entry to `log.md`

**Forbidden**: Never update index.md or log.md before validate passes.

## Mermaid Guidelines

Follow Obsidian-compatible Mermaid rules from SCHEMA.md:
- Include for: system architecture, data flow, process steps, concept relationships
- Skip for: simple facts, single concepts, purely textual topics

## Safety Rules

1. Always validate before writing index/log
2. Never overwrite existing pages without user confirmation
3. Source failures keep other sources; note in report
4. Respect `--no-raw` for quick lookups (no provenance chain)
5. Log all vault resolution and routing decisions
