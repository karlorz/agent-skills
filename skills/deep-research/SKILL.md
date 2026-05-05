---
name: deep-research
description: Multi-source deep research delegating vault writes to skillwiki. Resolves any configured vault, captures sources to raw/, synthesizes typed-knowledge pages via wiki-ingest pipeline. Use when user wants comprehensive research saved as first-class vault citizens.
---

# Deep Research

## TL;DR

- Multi-source research (web, Context7, DeepWiki) saved to any skillwiki-configured vault
- Sources captured in `raw/` with sha256 provenance via `wiki-ingest` pipeline
- Synthesized pages are schema-compliant typed-knowledge (concept/comparison/query/entity)
- All writes validated before index/log updates — no orphaned files
- Result: verbatim structured report to stdout (no post-processing)

## When This Skill Activates

- User requests comprehensive research on a topic
- User wants findings saved to a skillwiki vault (any configured vault)
- Topic mentions libraries, frameworks, GitHub repos, or general concepts

Do NOT use for:
- Quick factual lookups (use direct web search or docs lookup)
- Editing existing vault pages (use wiki-query or direct edits)
- Vault reorganization (use wiki-lint, wiki-archive)

## Prerequisites

A skillwiki-configured vault must exist:
- `skillwiki path` resolves successfully
- `SCHEMA.md`, `index.md`, `log.md` present
- If NO_VAULT_CONFIGURED: STOP and advise user to run `skillwiki init`

## Output Language

Run `skillwiki lang` at start. Generate page prose in resolved language. Frontmatter keys, file names, schema headers, citation markers, and wikilink slugs remain English.

## Pre-Orientation Reads (Mandatory)

Before any write:
1. `SCHEMA.md` — vault structure, taxonomy, conventions
2. `index.md` — existing pages to cross-link
3. Last 20 entries of `log.md` — recent vault activity

## Workflow

### Phase 1: Vault Resolution + Topic Analysis

1. Run `skillwiki path` — fail fast with advisory if NO_VAULT_CONFIGURED
2. Run `skillwiki lang` — resolve output language
3. Parse topic string for keywords
4. Search vault for existing related notes (title match first)

### Phase 2: Multi-Source Research

Run these queries in parallel where possible.

**Web Search (2-3 queries)**
```
Query 1: <topic> (primary)
Query 2: <topic> best practices OR <topic> tutorial
Query 3: <topic> <current-year> (optional, for freshness)
```

**Context7 MCP** (max 3 calls)
```
1. resolve-library-id for library/framework mentioned
2. query-docs for usage patterns
3. query-docs for code examples if needed
```

**DeepWiki MCP**
```
ask_question on relevant repo about architecture, patterns, implementation
```

### Phase 3: Raw Capture

For each source, follow `wiki-ingest` pattern:

1. **URL sources**: Write to `raw/articles/<slug>.md`
   - Frontmatter per `RawSourceSchema`: title, source_url, ingested, ingested_by: "wiki-ingest", sha256
   - Compute sha256 via `skillwiki hash <raw-file>`

2. **Context7 results**: Write extract to `raw/articles/<library-id>-docs.md`
   - Frontmatter: source_url: null (or Context7 library URL), ingested, sha256

3. **DeepWiki results**: Write Q&A to `raw/articles/<repo>-deepwiki.md`
   - Frontmatter: source_url: <repo-url>, ingested, sha256

**Stop conditions**: If raw capture fails (hash mismatch, write error), STOP and surface error.

### Phase 4: Synthesis + Composition

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
1. **TL;DR** — 3-5 bullets of key findings
2. **Overview** — 1-2 paragraph synthesis
3. **Mermaid diagram** — when applicable (architecture, flow, relationships)
4. **Research Findings** — collapsible callouts per source type
   - `> [!abstract]- Web Search Findings`
   - `> [!info]- Context7 Documentation`
   - `> [!tip]- DeepWiki Repository Insights`
5. **Synthesis** — merged analysis with patterns, recommendations, caveats
6. **Related Notes** — wikilinks to existing vault pages
7. **Sources** — numbered list with access dates, plus Context7/DeepWiki citations

**Citation format**: Use `^[raw/articles/slug.md]` markers at paragraph end.

### Phase 5: Vault Integration (Strict Pipeline)

Follow `wiki-ingest` write order:

1. **Validate**: `skillwiki validate <page>` — STOP if non-zero
2. **Write page**: Save to `concepts/<slug>.md` (or `comparisons/`, `queries/`, `entities/`)
3. **Update index**: Add entry to `index.md`
4. **Append log**: Add entry to `log.md`

**Forbidden**: Never update index.md or log.md before validate passes.

### Phase 6: Report (Verbatim)

Print structured summary exactly as follows:

```
Deep Research Complete
----------------------
Topic: <topic>
Vault: <resolved-vault-path>

Sources Queried:
  - Web search: <count> queries
  - Context7: <library-id or "not used">
  - DeepWiki: <repo or "not used">

Files Written:
  - raw/articles/<slug>.md
  - concepts/<slug>.md

Pipeline Results:
  - Raw capture: <count> sources
  - Validate: pass
  - Index: updated
  - Log: appended

Related notes found: <count>
Warnings: <any>
```

## Flags

| Flag | Effect |
|------|--------|
| `--type <concept\|comparison\|query\|entity>` | Force page type |
| `--no-raw` | Skip raw capture (quick lookup, no provenance) |
| `--folder <path>` | Override destination within vault (rarely needed) |

## Stop Conditions

- `skillwiki path` returns NO_VAULT_CONFIGURED
- Raw capture fails (hash error, write error)
- `skillwiki validate` fails (schema violation)
- All sources fail (web, Context7, DeepWiki all error)

## Safety Rules

1. Always validate before writing index/log
2. Never overwrite existing pages without user confirmation
3. Source failures keep other sources; note in report
4. Respect `--no-raw` for quick lookups (no provenance chain)
5. Log all vault resolution and routing decisions

## Failure Handling

| Failure | Action |
|---------|--------|
| No vault configured | Abort with: "No vault configured. Run `skillwiki init` or set WIKI_PATH." |
| Web search fails | Continue; omit web findings section |
| Context7 fails | Continue; omit Context7 section |
| DeepWiki fails | Continue; omit DeepWiki section |
| Validate fails | STOP — do not write index/log; surface errors |
| Raw hash mismatch | STOP — source content changed mid-capture |

## Tool Usage

### Primary Tools

- **skillwiki CLI**: Vault resolution, validation, hash computation
  - `skillwiki path` — resolve vault root
  - `skillwiki lang` — resolve output language
  - `skillwiki hash <file>` — compute sha256
  - `skillwiki validate <file>` — schema validation gate
- **Web search**: Current information via Codex
- **Context7 MCP**: Library/framework documentation
- **DeepWiki MCP**: GitHub repository insights

### Vault Tools

- **File reads**: Read SCHEMA.md, index.md, log.md for orientation
- **File writes**: Create raw sources, typed pages via Write tool
- **File edits**: Update index.md, append to log.md via Edit tool

## Mermaid Guidelines

Follow Obsidian-compatible Mermaid rules from SCHEMA.md:

- Include for: system architecture, data flow, process steps, concept relationships
- Skip for: simple facts, single concepts, purely textual topics

## Related Skills

- **wiki-ingest**: Raw capture, hash, validate, write pipeline
- **wiki-crystallize**: Alternative for session distillation (use when research comes from working session)
- **wiki-lint**: Post-hoc quality check (orphans, broken citations, oversized pages)
- **wiki-audit**: Citation verification

## References

- [[concepts/skillwiki-architecture]] — vault layers, schema, pipeline
- [[concepts/trivial-cycle-fast-path]] — applicable pattern for vault-only edits
