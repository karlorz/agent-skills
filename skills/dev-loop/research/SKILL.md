---
name: research
version: "1.5.2"
description: Pluggable research agent for dev-loop. Scans code health (CLI, tests, skills, specs) and optional vault health (coverage, links, quality). Outputs prioritized work items. Pass 'high' for aggressive mode.
type: companion-prompt
mode: recurring
---

# Dev-Loop Research Agent

Pluggable research cycle for dev-loop. Scans configurable health tracks, cross-references findings with retros, outputs prioritized work-item recommendations.

## Architecture

```
┌─────────────────────────────────────────┐
│ 0. RESOLVE CAPABILITIES                 │
│    Detect: cli_backend, vault_backend   │
├─────────────────────┬─────────────────┤
│ TRACK A (optional)  │ TRACK B (opt)   │
│ Code Health         │ Vault Health    │
│ - Coverage gaps     │ - Raw coverage  │
│ - Skills drift      │ - Cross-links   │
│ - Spec drift        │ - Page quality  │
│ - Unpushed commits  │ - Type coverage │
├─────────────────────┴─────────────────┤
│ 1. RETROS (if vault_backend)            │
│ 2. SYNTHESIZE → P0-P3 (P4+ in high)     │
│ 3. OUTPUT (vault log + memory)          │
└─────────────────────────────────────────┘
```

## Capabilities Detection

At REFRESH, re-derive `BACKEND_CAPS` using the same logic as the parent dev-loop skill. Do NOT assume inherited state — explicitly resolve from config:

1. Read `knowledge_layer` from project config (default: `skillwiki` if vault exists, `none` otherwise).
2. Resolve `BACKEND_CAPS` from `knowledge_layer` — same registry/defaults as parent skill REFRESH step.
3. Derive track booleans from `BACKEND_CAPS` membership:

| Capability | Detection | Track |
|------------|-----------|-------|
| `cli_backend` | `cli_src` field exists | A |
| `vault_backend` | `query_vault` in BACKEND_CAPS | B |

Skip tracks when backends unavailable. Run with available tracks only.

**Critical:** `BACKEND_CAPS` controls work-item creation paths in the Output step. If `create_work_item` is in `BACKEND_CAPS`, use `proj-work` for vault-native paths. Only fall back to git-local (`.claude/dev-loop-work/`) when `create_work_item` is absent.

## Intensity

Parse args for `high` (case-insensitive). Default: `normal`.

| Mode | Output | Recurring | Thresholds |
|------|--------|-----------|------------|
| normal | top-3 | Suppress unchanged | P1: uncited>50%, thin<40L, links<2 |
| high | top-5 | Never suppress | P1: uncited>20%, thin<60L, links<3, P4+ enabled |

## Track A: Code Health

Skip if `cli_backend` unavailable.

### A1. Coverage Gaps
- Source files in `{cli_src}/` without matching `{cli_test}/` tests
- Missing behavioral conventions (`--human`, exit codes)
- Markers: `TODO|FIXME|HACK|XXX`

### A2. Skills Drift
- SKILL.md files referencing non-existent CLI commands
- Skill descriptions stale vs actual behavior
- Skill counts drift from documented

### A3. Spec Drift
- New commands not in canonical spec
- Changed counts vs spec snapshot
- Schema changes unreflected

### A4. Unpushed Commits
```bash
git log origin/${release_branch:-main}..HEAD --oneline 2>/dev/null | wc -l
```
- ≥10 → P1 | 5-9 → P2 | 1-4 → P4+ (defer, unless high)

## Track B: Vault Health

Skip if `vault_backend` unavailable.

### B1. Raw Coverage
- Uncited raw files % (P1: >50% normal, >20% high)
- Single-source pages (P2)

### B2. Cross-Link Density
- Isolated pages (<2 links normal, <3 high)
- Orphan clusters (via backend `orphans` if available)
- Overlap clusters (via backend `overlap` if available)

### B3. Page Quality
- Thin pages (<40L normal, <60L high)
- Missing Overview/Related sections

### B4. Type Coverage
- Empty type dirs (entities, comparisons, queries, meta)
- High: flag regardless of total pages

## Retros

If `vault_backend`:
- Scan `{vault}/log.md` for `Improve:` actions
- Check `{vault}/projects/{slug}/compound/` for pending work
- Retro actions → direct work-item candidates

## Synthesize

Score: impact × effort

| P | Impact | Examples |
|---|--------|----------|
| P0 | Spec violation | Regression, broken contract |
| P1 | High gap | Untested cmd, uncited raw>50%, isolated pages |
| P2 | Medium | Thin pages, skill drift, single-source |
| P3 | Low polish | Quality, cross-links, sections |
| P4+ | Speculative | Proactive improvements, experiments |

Output format:
```markdown
### #[N]: [title] (Px)
**Source**: [track.source]
**What**: One-paragraph spec.
**Acceptance**: Verifiable outcomes.
```

## Idle Detection

**Pre-idle gate:** Check metrics before declaring idle.

| State | Condition | Exit |
|-------|-----------|------|
| Truly idle | Zero findings + healthy metrics | "Research idle" |
| Steady backlog | No new, gaps persist | "Research steady — [N] recurring" |
| High mode | Always | Never idle, proactive suggestions |

Healthy thresholds:
- Uncited: <50% (normal), <20% (high)
- Isolated: 0
- Thin: 0 (at thresholds)

**Never report idle with actionable gaps.**

## Output

### Work-item creation

When synthesizing recommendations that need work items, check `create_work_item in BACKEND_CAPS`:

- **`create_work_item` in BACKEND_CAPS:** Use `proj-work` to create work items under `{vault}/projects/{slug}/work/`. This ensures wiki indexing, `knowledge.md` references, and `wiki-lint` visibility.
- **`create_work_item` not in BACKEND_CAPS:** Fall back to `.claude/dev-loop-work/YYYY-MM-DD-{slug}/` (git-local path). Ensure `.claude/dev-loop-work/` is in `.gitignore`.

Never silently default to git-local when the vault backend is configured — this bypasses the vault and breaks provenance.

### Logging

If `vault_backend`:
- Append to `{vault}/log.md`
- Update MEMORY.md if top-N changed

Always: one-line exit summary.

## Backend Interface (Pluggable)

The agent delegates to configured backends. Expected interface:

```typescript
interface ResearchBackend {
  // Detection
  isAvailable(): boolean;

  // Track A
  listSourceFiles(): string[];
  listTestFiles(): string[];
  listSkillFiles(): string[];

  // Track B
  countRawFiles(): number;
  countCitedRaw(): number;
  countIsolatedPages(): number;
  countThinPages(threshold: number): number;
  listOrphanPages(): string[];

  // Output
  appendLog(entry: string): void;

  // Work-item creation (requires create_work_item in BACKEND_CAPS)
  createWorkItem(slug: string, kind: string): { specPath: string; planPath: string };
}
```

Default implementations provided for:
- `cli_backend`: filesystem + git
- `vault_backend`: skillwiki CLI (if available), else fs-only
