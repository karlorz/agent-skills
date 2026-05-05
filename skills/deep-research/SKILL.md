---
name: deep-research
description: Use when user requests comprehensive research on a topic, wants multi-source investigation (web, docs, repos), or mentions deep research, literature review, competitive analysis, or technology comparison. Works with or without a knowledge base vault.
---

# Deep Research

## Overview

Multi-source research engine that queries web search, Context7, and DeepWiki in parallel, then synthesizes findings into a structured report. Output is flexible: print to terminal, save as markdown file, or integrate with a skillwiki vault.

## When to Use

- User requests comprehensive research on a topic
- User wants deep investigation across multiple sources
- Topic involves libraries, frameworks, GitHub repos, or general concepts
- User mentions "research", "investigate", "compare", "analyze", or "deep dive"

Do NOT use for:
- Quick factual lookups (use direct web search or docs lookup)
- Single-source questions (use Context7 or web search directly)

## Output Modes

The skill supports three output modes, controlled by flags:

| Flag | Mode | Behavior |
|------|------|----------|
| *(default)* | **stdout** | Print structured report to terminal, no file writes |
| `--save <path>` | **file** | Write markdown report to specified path |
| `--vault` | **vault** | Integrate with skillwiki vault (requires configured vault) |

Vault mode is optional. The research engine works without any knowledge base.

## Workflow

### Phase 1: Topic Analysis

1. Parse topic string for keywords, libraries, frameworks
2. If `--vault` flag present: resolve vault via `skillwiki path`, run `skillwiki lang` for output language, search existing pages for cross-linking
3. If no `--vault`: proceed with research in user's language

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

**Graceful degradation**: If any source fails, continue with remaining sources. Note failures in report.

### Phase 3: Synthesis

Compose research report with these sections:

1. **TL;DR** -- 3-5 bullets of key findings
2. **Overview** -- 1-2 paragraph synthesis
3. **Findings** -- organized by source type with collapsible callouts
   - `> [!abstract]- Web Search Findings`
   - `> [!info]- Documentation (Context7)`
   - `> [!tip]- Repository Insights (DeepWiki)`
4. **Analysis** -- merged patterns, recommendations, caveats
5. **Sources** -- numbered list with access dates

### Phase 4: Output Routing

Route output based on active mode:

**stdout (default)**: Print the full structured report directly to terminal.

**`--save <path>`**: Write the report as a markdown file to the specified path. Create parent directories if needed.

**`--vault`**: Delegate to skillwiki vault pipeline. See `references/vault-pipeline.md` for the full integration workflow (raw capture, schema validation, index/log updates).

### Phase 5: Report

Print a summary block:

```
Deep Research Complete
----------------------
Topic: <topic>
Mode: stdout | file | vault

Sources Queried:
  - Web search: <count> queries
  - Context7: <library-id or "not used">
  - DeepWiki: <repo or "not used">

Output: <path or "terminal">
Warnings: <any>
```

## Flags

| Flag | Effect |
|------|--------|
| `--save <path>` | Write markdown report to file |
| `--vault` | Integrate with skillwiki vault (raw capture, typed pages, index/log) |
| `--type <concept\|comparison\|query\|entity>` | Force page type (vault mode only) |
| `--no-raw` | Skip raw source capture (vault mode: no provenance chain) |

## Stop Conditions

- All three source types fail (web, Context7, DeepWiki)
- `--vault` mode: `skillwiki path` returns NO_VAULT_CONFIGURED
- `--vault` mode: validation fails (do not write index/log)

## Failure Handling

| Failure | Action |
|---------|--------|
| Web search fails | Continue; omit web findings section |
| Context7 fails | Continue; omit Context7 section |
| DeepWiki fails | Continue; omit DeepWiki section |
| All sources fail | STOP; report total failure |
| Vault not configured (`--vault`) | Abort with advisory to run `skillwiki init` |
| Vault validate fails (`--vault`) | STOP; surface errors; do not write index/log |

## Tool Usage

- **Web search**: Current information
- **Context7 MCP**: Library/framework documentation
- **DeepWiki MCP**: GitHub repository insights
- **skillwiki CLI** (vault mode only): `skillwiki path`, `skillwiki lang`, `skillwiki hash`, `skillwiki validate`

## Related Reference

- **references/vault-pipeline.md**: Vault-mode raw capture, validation, and index/log update workflow
