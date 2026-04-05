---
name: deep-research
description: Multi-source deep research on any topic with auto-routing to the correct Obsidian vault folder. Use Codex web search plus Context7 and DeepWiki MCP servers, then optionally chain through compaction overlap check and content simplification. Use when a user wants comprehensive research synthesized into a polished vault note.
triggers:
  - /deep-research
  - $deep-research
  - deep research on
  - research and add to vault
  - comprehensive research
---

# Deep Research

## TL;DR

- Query multiple sources in parallel: Codex web search, Context7, and DeepWiki.
- Auto-route output to the correct vault folder based on topic analysis.
- Chain through compactor overlap check and content simplification by default.
- Use flags to skip chain steps or override routing.

## Scope

Use this skill when the user wants to:

- Research a topic and save findings to the Obsidian vault
- Get up-to-date documentation and code examples for libraries/frameworks
- Explore GitHub repositories and understand implementation patterns
- Create a polished note that integrates with existing vault structure

Do not use this skill for:

- Quick factual lookups (use direct web search or docs lookup)
- Editing existing notes (use local vault tools or obsidian-gh-knowledge)
- Vault reorganization (use obsidian-dry-run-compactor)
- Code-focused simplification (use simplify skill)

## Triggers and Flags

### Invocation Patterns

```
/deep-research <topic>
$deep-research <topic>
"deep research on <topic>"
"research <topic> and add to vault"
```

### Flags

| Flag | Effect |
|------|--------|
| `--no-compact` | Skip compactor overlap check |
| `--no-simplify` | Skip content simplify pass |
| `--no-chain` | Skip both compact and simplify |
| `--draft` | Force output to `0️⃣-Inbox/` |
| `--folder <path>` | Override auto-routing with specific path |

### Examples

```bash
/deep-research K8s networking for cmux
/deep-research --draft React hooks
/deep-research --no-chain GraphQL best practices
/deep-research --folder "5️⃣-Projects/Infrastructure/k8s/" Kubernetes CNI comparison
```

## Workflow

### Phase 1: Topic Analysis + Routing

1. Parse topic string to extract keywords
2. Run in parallel:
   - Dynamically scan `5️⃣-Projects/` to detect project folders
   - Search vault for existing notes on the same topic (title match first, then tags/headings if needed)
3. Match topic against project names (case-insensitive, first match wins)
4. Apply routing rules per [routing-rules.md](references/routing-rules.md)
5. Generate output filename (slugified topic + `-deep-research.md`)

**Routing priority**:
1. `--folder` flag (explicit override)
2. `--draft` flag (forces Inbox)
3. Project folder match (e.g., "cmux" in topic → `5️⃣-Projects/GitHub/cmux/`)
4. Research keywords → `5️⃣-Projects/Research/`
5. Fallback → `0️⃣-Inbox/` with advisory

### Phase 2: Multi-Source Research

Run these queries in parallel where possible.

#### Web Search (2-3 queries)

```
Query 1: <topic> (primary)
Query 2: <topic> best practices OR <topic> tutorial (secondary)
Query 3: <topic> <current-year> (optional, for freshness)
```

For top results, open the most relevant pages and pull the specific passages needed for synthesis.

#### Context7 MCP (max 3 calls)

Use when topic mentions a library, framework, or API:

```
1. resolve-library-id for the library name
2. query-docs with specific questions about usage
3. query-docs for code examples if needed
```

**Important**: Per CLAUDE.md, always use Context7 for framework/library docs instead of relying on training data.

#### DeepWiki MCP

Use when topic relates to a GitHub repository:

```
ask_question on relevant repo about architecture, patterns, or implementation
```

Focus on codebase insights that complement official docs.

### Phase 3: Note Composition

Structure the note per [[agent-skills/skills/deep-research/references/note-template|note-template]]:

1. **YAML frontmatter**: tags, created date, sources, skill marker
2. **TL;DR**: 3-5 bullet summary of key findings
3. **Overview**: 1-2 paragraph synthesis
4. **Mermaid diagram**: When applicable, following CLAUDE.md rules
5. **Research Findings**: Collapsible callouts per source
   - `> [!abstract]- Web Search Findings`
   - `> [!info]- Context7 Documentation`
   - `> [!tip]- DeepWiki Repository Insights`
6. **Synthesis**: Merged analysis with patterns and recommendations
7. **Related Notes**: Wikilinks to existing vault notes
8. **Sources**: Numbered URL list with access dates

### Checkpoint: Save Raw Note

**Critical**: Write the composed note to disk BEFORE any chain steps.

This ensures recovery if chain steps fail.

### Phase 4: Compact Check (unless --no-compact)

Invoke the compactor in **single-note chain mode**:

1. Score new note against its folder neighbors
2. Use heuristics from compactor's scoring.md
3. Take action based on score:
   - Score < 60: No action
   - Score 60-79: Add cross-links to Related Notes
   - Score >= 80: Warn user about potential merge candidate

See compactor SKILL.md "Single-Note Chain Mode" section.

### Phase 5: Content Simplify (unless --no-simplify)

Two-pass simplification per [[agent-skills/skills/deep-research/references/chain-orchestration|chain-orchestration]]:

**Pass A: Consolidation**
- Remove redundancy across callout sections
- Move repeated content into Synthesis
- Merge similar code examples

**Pass B: Tightening**
- Reduce verbose prose
- Verify TL;DR accuracy
- Check Mermaid rendering
- Trim sources to top 5-7

### Phase 6: Finalize + Report

Print execution summary:

```
Deep Research Complete
----------------------
Topic: <topic>
Output: <full path>
Folder: <resolved folder>
Sources queried:
  - Web search: <count> queries
  - Context7: <library-id or "not used">
  - DeepWiki: <repo or "not used">
Chain results:
  - Compact: <score or "skipped">
  - Simplify: <"applied" or "skipped">
Related notes found: <count>
Warnings: <any warnings>
```

## Safety Rules

1. Always save raw note before chain steps
2. Never overwrite existing notes without user confirmation
3. Chain failures keep note as-is and warn user
4. Respect `--draft` flag for uncertain routing
5. Log routing decisions for transparency

## Tool Usage

### Primary Tools

- **Codex web search**: Current web information, multiple targeted queries, then open the strongest sources
- **Context7 MCP**: Library/framework documentation
  - `mcp__context7__resolve_library_id`
  - `mcp__context7__query_docs`
- **DeepWiki MCP**: GitHub repository insights
  - `mcp__deepwiki_mcp__ask_question`

### Vault Tools

- **Shell + `rg`**: Scan project folders, locate existing notes, and search note content
- **File reads**: Check existing notes, verify `_Overview.md`, and inspect candidate related notes
- **File writes/edits**: Create the research note first, then add any cross-links during compact phase

## Mermaid Guidelines

Follow the Mermaid rules in [[AGENTS#Mermaid (Obsidian Compatibility)|CLAUDE.md]].

Include diagrams when explaining system architecture, data flow, comparisons, or concept relationships. Skip for simple factual lookups.

## Failure Handling

| Failure | Action |
|---------|--------|
| Web search fails | Continue with other sources, note in report |
| Context7 fails | Omit that callout section, note in report |
| DeepWiki fails | Omit that callout section, note in report |
| ALL sources fail | Abort with error, no note created |
| Mermaid invalid | Remove diagram, add warning |
| Compact fails | Keep note as-is, warn in report |
| Simplify fails | Keep note as-is, warn in report |

## References

- [[agent-skills/skills/deep-research/references/routing-rules|routing-rules]] - Auto-routing algorithm
- [[agent-skills/skills/deep-research/references/note-template|note-template]] - Output note structure
- [[agent-skills/skills/deep-research/references/chain-orchestration|chain-orchestration]] - Pipeline details
- [[agent-skills/skills/obsidian-dry-run-compactor/SKILL|obsidian-dry-run-compactor]] - Compactor skill
- [[AGENTS|CLAUDE.md]] - Vault conventions and Mermaid rules

## Related Skills

- **obsidian-dry-run-compactor**: Used for compact check chain step
- **obsidian-gh-knowledge**: Vault operations and project scoping
- **simplify**: Code-focused simplification (not used here; content-simplify is inline)
