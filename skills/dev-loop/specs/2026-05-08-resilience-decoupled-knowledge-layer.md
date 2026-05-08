---
name: Dev-loop resilience spec
description: Design for decoupling dev-loop from skillwiki and making it work across projects with different knowledge tooling
type: spec
created: 2026-05-08
status: draft
---

# Dev-loop Resilience: Decoupled Knowledge Layer

## Problem Statement

dev-loop v1.3.1 is architecturally coupled to skillwiki in ways that
break flexibility:

1. **Knowledge layer is not pluggable.** The PRD layer (brainstorm/spec/
   plan/execute) is documented as swappable, but the Knowledge layer
   (vault/capture/distill) is hardcoded to skillwiki with no alternative.

2. **No graceful degradation.** When skillwiki isn't installed or the
   vault doesn't exist, steps silently skip or the cycle runs blind —
   producing zero knowledge output without indicating this to the user.

3. **Hardcoded assumptions.** `~/wiki` vault path, 5 vault type dirs
   (entities/concepts/comparisons/queries/meta), fixed IDLE DISCOVERY
   menu of skillwiki maintenance skills.

4. **Plugin cache blocks hot-reload.** Claude Code plugin cache stores
   regular file copies (not symlinks). Editing source SKILL.md doesn't
   take effect until explicit `/reload-plugins`. This blocks iterative
   skill development.

## Design Goals

- **G1**: dev-loop works for any project, with or without skillwiki
- **G2**: each step gracefully degrades based on available tooling
- **G3**: no hardcoded paths or vault schema assumptions in the engine
- **G4**: clear developer workflow for skill iteration with cache sync

## Solution: Three Changes

### Change 1 — Config: `knowledge_layer` field

Add to `templates/project-config.md`:

```yaml
## Knowledge layer

knowledge_layer: skillwiki | none
```

Vault type directories are **discovered from SCHEMA.md**, not configured.
The REFRESH step parses `{vault}/SCHEMA.md` `## Layers` section to extract
backtick-wrapped dir names (regex: `` `(\w+)/` ``), excluding `raw` and
`projects`. This handles different schema versions automatically (Hermes
v2.1 has 4 types, skillwiki has 5).

**Behavior per mode:**

| Mode | QUERY | WORK | SAVE | RETRO | DISTILL | VERIFY | IDLE MAINT |
|------|-------|------|------|-------|---------|--------|------------|
| `skillwiki` | wiki-query | proj-work | wiki-crystallize | vault log.md | proj-distill | wiki-audit | full menu |
| `none` | git log + grep | inline work item | skip | git commit msg | skip | skip | git-based only |

**Default**: `skillwiki` (backwards compatible).

**When `vault` is empty**: force `knowledge_layer: none` regardless of
config, and log a one-line warning at REFRESH.

### Change 2 — SKILL.md: Conditional step blocks

Replace every skillwiki-coupled step with a conditional structure:

```
### N. STEP — (conditional on knowledge_layer)

If `knowledge_layer == none`:
  [alternative behavior or skip with one-line reason]

If `knowledge_layer == skillwiki`:
  [current behavior]

If `knowledge_layer == custom`:
  [invoke knowledge_tool with step-specific args]
```

**Specific step changes:**

**QUERY (step 1):**
- `none` mode: run `git log --oneline -20` + `git diff --stat HEAD~5`
  to surface recent changes. This is the "code-only" context check.
- `custom` mode: `$tool query <search-terms>`

**WORK (step 2):**
- `none` mode: create inline work item in `.claude/dev-loop-work/
  YYYY-MM-DD-{slug}/` (local to repo, not vault). Emit local paths
  for spec.md and plan.md.
- `custom` mode: `$tool work <slug>`

**SAVE (step 7):**
- `none` mode: skip with "no knowledge layer configured"
- `custom` mode: `$tool crystallize <session-context>`

**RETRO (step 11):**
- `none` mode: append retro to `.claude/dev-loop-work/{slug}/retro.md`
  instead of vault log.md. Also write to git commit body if a commit
  was made this cycle.
- `custom` mode: `$tool retro <retro-content>`

**DISTILL (step 12):**
- `none` mode: skip entirely. No concept pages exist.
- `custom` mode: `$tool distill <project-slug>`

**VERIFY (step 14):**
- `none` mode: skip entirely. No provenance to verify.
- `custom` mode: `$tool audit`

**IDLE DISCOVERY:**
- `none` mode: skip skillwiki maintenance menu. Run git-based
  housekeeping (gc, prune stale branches). Run research agent
  with adjusted Track B that skips vault coverage checks.
- `custom` mode: `$tool lint`, `$tool audit`, `$tool drift`

### Change 3 — research.md: Parameterized vault types from SCHEMA.md

Replace hardcoded `entities concepts comparisons queries meta` lists
in B1–B4 with `${VAULT_TYPES}` variable, populated from SCHEMA.md
parsing at REFRESH time. If empty or `KNOWLEDGE_LAYER=none`, skip
Track B entirely.

```bash
# Derived from SCHEMA.md parsing in REFRESH step 3b:
# VAULT_TYPES is set by the parent skill before invoking research agent
for dir in $VAULT_TYPES; do
  ...
done
```

## Hot-Reload Blocker: Plugin Cache Sync

**Problem:** Claude Code plugin cache at
`~/.claude/plugins/cache/{author}-{plugin}/{version}/` stores regular
file copies, not symlinks. Editing source files doesn't propagate.

**Verified:** Source SKILL.md at
`/Users/karlchow/Desktop/code/agent-skills/skills/dev-loop/SKILL.md`
and cache at `~/.claude/plugins/cache/karlorz-agent-skills/dev-loop/
1.3.1/SKILL.md` are identical copies with different timestamps.

**Development workflow options:**

| Option | Steps | Risk |
|--------|-------|------|
| **A: Source → cache sync** | Edit source, `cp` to cache, `/reload-plugins` | Two commands, reliable |
| **B: Edit cache directly** | Edit `~/.claude/plugins/cache/...` files | Fragile, lost on reinstall |
| **C: Symlink override** | Replace cache file with symlink to source | Survives edits, breaks on `/plugin update` |
| **D: Local marketplace reinstall** | `claude plugin uninstall && claude plugin install` | Slow but guaranteed clean |

**Recommended: Option A** — edit source, then:

```bash
# One-liner to sync and reload
cp /path/to/source/SKILL.md ~/.claude/plugins/cache/.../SKILL.md
# Then: /reload-plugins in Claude Code
```

**Ideal long-term fix:** Plugin cache should symlink instead of copy,
or `/reload-plugins` should re-sync from the marketplace source.

## Implementation Plan

### Phase 1 — Config extension (low risk)
1. Add `knowledge_layer` to
   `templates/project-config.md`
2. Add REFRESH logic to parse these fields and set mode variables
3. Update `~/wiki` fallback to use `skillwiki path` CLI output
   instead of hardcoded path

### Phase 2 — SKILL.md conditional steps (medium risk)
4. Wrap each skillwiki-dependent step in conditional blocks
5. Implement `none` mode alternatives (git-based WORK, RETRO)
6. Add one-line status indicators for skipped steps

### Phase 3 — research.md parameterization (low risk)
7. Replace hardcoded vault type lists with `${VAULT_TYPES}` (populated from SCHEMA.md at REFRESH)
8. Add Track B skip logic when VAULT_TYPES is empty or KNOWLEDGE_LAYER=none

### Phase 4 — Validation
9. Test with `knowledge_layer: skillwiki` (regression — must match
   current behavior)
10. Test with `knowledge_layer: none` on a non-skillwiki project
11. Test with `knowledge_layer: custom` pointing to a wrapper script

## Non-Goals

- Building a generic knowledge plugin interface (that's what MCP is for)
- Supporting multiple simultaneous knowledge layers
- Auto-detecting which knowledge tools are installed (explicit config
  over autodiscovery — the user should declare their tooling)

## Open Questions

1. Should `none` mode still create local work items (`.claude/dev-loop-work/`)?
   → Yes, for resumability. Even without a vault, the loop needs to
   track what it's working on.

2. Should the research agent still run in `none` mode?
   → Yes, but only Track A (code quality) and Track C (architecture).
   Track B (vault coverage) is skipped.
