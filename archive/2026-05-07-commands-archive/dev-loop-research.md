---
description: Research agent loop for llm-wiki — scans vault content health, CLI codebase, skills, and spec for next work items. Pass 'high' for aggressive mode. Plug into dev-loop idle path or run standalone via /loop.
mode: recurring
interval: 1h recommended (15m during active sessions), 10m for high mode
---

# Dev-Loop Research Agent — llm-wiki

Runs as a recurring research loop. Each pass scans **two parallel tracks** — code health and vault health — cross-references findings, and outputs a prioritized work-item recommendation list. When no new findings emerge across both tracks, exits idle with a one-line status.

## Intensity Level

Parse `$ARGUMENTS` for the keyword `high` (case-insensitive). If present,
set **intensity = high**; otherwise **intensity = normal**.

### normal (default)
Current behavior — respect priority tiers. Output top-3 ranked items.
Use idle fast-path when all signals are healthy. Suppress recurring
findings that haven't changed since last pass.

### high
Aggressive mode — **every finding is actionable, priority gates removed.**

- **Output top-5** ranked items (expanded from top-3).
- **Never suppress recurring findings** — re-report them every cycle with
  updated metrics so they stay visible.
- **Lower flagging thresholds**:
  - Thin pages: flag at <60 body lines (up from <40).
  - Uncited raw: flag at >20% (down from >50%).
  - Single-source pages: always flag (not just confidence-low).
  - Cross-links: flag pages with <3 outbound links (up from <2).
- **Include speculative findings**: items that would normally be deferred
  or marked "too early" (e.g., empty type dirs regardless of total page
  count, potential entity extraction candidates, code quality improvements).
- **Expand search surface**: in addition to the standard tracks, also scan:
  - `packages/shared/src/` for unused exports or stale types.
  - `packages/cli/templates/` for template drift.
  - Git log for recent commits without corresponding vault retros.
  - Memory files in `~/.claude/projects/.../memory/` for stale entries.
- **Never report truly idle** — in high mode there is always something to
  recommend. If all standard checks pass, suggest proactive improvements
  (new test cases, documentation enrichments, speculative refactors).
- **P4+ items are first-class** — score and include them in recommendations.

## When to Invoke

1. **Dev-loop idle path**: When dev-loop IDLE DISCOVERY triggers (QUERY finds no claimable work AND nothing is in progress), delegate to this agent.
2. **Standalone**: `/loop 1h /dev-loop-research` for continuous background scanning.
3. **Intensive sprint**: `/loop 10m /dev-loop-research high` for aggressive continuous scanning.
4. **One-shot**: Just run `/dev-loop-research` (optionally with `high`) once when the dev-loop is idle.

## Single-Pass Cycle

```
┌─────────────────────────────────────────────────────────────────┐
│ 0. REFRESH                                                      │
│    Read CLAUDE.md + MEMORY.md fresh                             │
├─────────────────────────────────┬───────────────────────────────┤
│ TRACK A: CODE HEALTH            │ TRACK B: VAULT HEALTH         │
│                                 │                               │
│ A1. CLI COVERAGE GAPS           │ B1. RAW-TO-PAGE COVERAGE      │
│     Commands vs tests, markers  │     Uncited raw, low-cite     │
│     --human, exit codes         │     pages, raw dir growth     │
│                                 │                               │
│ A2. SKILLS AUDIT                │ B2. CROSS-LINK DENSITY        │
│     Skill count vs map, CLI ref │     Isolated pages, weak      │
│     accuracy, SKILL.md quality  │     wikilink counts, orphan   │
│                                 │     clusters                  │
│                                 │                               │
│ A3. SPEC DRIFT                  │ B3. PAGE QUALITY              │
│     N1-N18 compliance, scope    │     Thin pages (<40 body      │
│     vs actual, deferred leaks   │     lines), missing sections, │
│                                 │     single-source pages       │
│                                 │                               │
│                                 │ B4. TYPE COVERAGE             │
│                                 │     Empty dirs, entity        │
│                                 │     extraction candidates,    │
│                                 │     comparison/query gaps     │
├─────────────────────────────────┴───────────────────────────────┤
│ 1. VAULT RETROS (cross-cutting)                                 │
│    Scan ~/wiki/log.md for recent Improve: and Generalize?: yes  │
│    Check compound/ for pending distillation work                │
├─────────────────────────────────────────────────────────────────┤
│ 2. SYNTHESIZE                                                   │
│    Merge findings from both tracks + retros.                    │
│    Score each finding: impact × effort (P0–P3).                 │
│    Output top-3 ranked work items with inline specs.            │
├─────────────────────────────────────────────────────────────────┤
│ 3. SAVE & EXIT                                                  │
│    Append findings to vault log.md as research observation.     │
│    If top-3 changed since last pass, update MEMORY.md.          │
│    Exit with one-line summary.                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Step Details

### 0. REFRESH
Read `/Users/karlchow/Desktop/code/llm-wiki/CLAUDE.md` and the user MEMORY.md fresh. First cycle in a session is a no-op if already loaded.

### Track A: Code Health

#### A1. CLI Coverage Gaps (~300 tokens)
List all `packages/cli/src/commands/*.ts` files. For each, check:
- **Test coverage**: Does `packages/cli/test/commands/{name}.test.ts` exist? If not, flag.
- **--human flag**: Does the command support `--human` per N2?
- **Exit codes**: Are exit codes documented and stable per N3?
- **Markers**: `grep -n 'TODO\|FIXME\|HACK\|XXX' packages/cli/src/commands/{name}.ts`

Known: 28 commands, 29 test files (full coverage + wire-compat). Zero markers expected.

#### A2. Skills Audit (~150 tokens)
Verify all 14 SKILL.md files in `packages/skills/`. The using-skillwiki skill map should list all 14 — verify count matches actual skill directories. For each skill, check:
- Does it reference correct CLI subcommands that actually exist?
- Does the skill's description match the current CLI behavior?

#### A3. Spec Drift (~300 tokens)
The canonical spec at `~/wiki/projects/llm-wiki/history/specs/2026-05-02-llm-wiki-skill-design.md` defines N1–N18. Verify each against current code. Key drift signals:
- New commands not in spec → document or spec update needed?
- Changed skill count (spec says 14, verify still 14)?
- New frontmatter fields not in N11–N13?

### Track B: Vault Health

#### B1. Raw-to-Page Coverage (~200 tokens)
**This is the most important new signal.** Run these checks:

```bash
# Vault existence guard — short-circuit Track B if vault not initialized
if [ ! -d ~/wiki/raw ]; then
  echo "VAULT_NOT_INITIALIZED: ~/wiki/raw not found — skipping Track B"
  # Jump directly to step 1 (VAULT RETROS) by setting a flag or exiting early
  SKIP_TRACK_B=1
fi

if [ -z "$SKIP_TRACK_B" ]; then

# Total raw vs typed pages
RAW_COUNT=$(find ~/wiki/raw -name "*.md" | wc -l | tr -d ' ')
PAGE_COUNT=$(find ~/wiki/{entities,concepts,comparisons,queries,meta} -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
UNCITED_PCT=0
if [ "$RAW_COUNT" -gt 0 ]; then
  CITED=$(grep -rh '\^\[raw/' ~/wiki/{entities,concepts,comparisons,queries,meta}/ 2>/dev/null | sed -n 's/.*\^\[raw\/\([^]]*\)\].*/\1/gp' | sort -u | wc -l | tr -d ' ')
  UNCITED=$((RAW_COUNT - CITED))
  echo "Raw: $RAW_COUNT, Pages: $PAGE_COUNT, Cited: $CITED, Uncited: $UNCITED ($((UNCITED * 100 / RAW_COUNT))%)"
else
  echo "Raw: 0, Pages: $PAGE_COUNT"
fi

# Pages citing only 1 source (low confidence flag)
find ~/wiki/{entities,concepts,comparisons,queries,meta} -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' f; do
  cites=$(grep -c '\^\[raw/' "$f" 2>/dev/null || true)
  cites=${cites:-0}
  if [ "$cites" -le 1 ]; then
    echo "SINGLE-SOURCE: $f ($cites citations)"
  fi
done
```

**Work items to flag:**
- Uncited raw percentage >50% → raw sources exist without typed pages citing them (P1)
- Single-source pages → `confidence: low` per N7, consider merging or enriching (P2)

#### B2. Cross-Link Density (~200 tokens)
Run these checks:

```bash
# Per-page outbound wikilink count (exclude frontmatter)
python3 -c "
import os, re
base = os.path.expanduser('~/wiki')
for d in ['entities','concepts','comparisons','queries','meta']:
    dp = os.path.join(base, d)
    if not os.path.isdir(dp): continue
    for f in sorted(os.listdir(dp)):
        if not f.endswith('.md'): continue
        fp = os.path.join(dp, f)
        with open(fp) as fh: content = fh.read()
        parts = content.split('---', 2)
        if len(parts) < 3: print(f'MALFORMED_FRONTMATTER: {f}'); continue
        body = parts[2].strip()
        links = re.findall(r'\[\[([^\]]+)\]\]', body)
        if len(links) < 2: print(f'ISOLATED: {f} ({len(links)} outbound links)')
"

# Orphan detection via CLI (use tsx fallback if installed binary is stale)
npx tsx packages/cli/src/cli.ts orphans ~/wiki 2>/dev/null || npx skillwiki orphans ~/wiki || echo "TOOLING_UNAVAILABLE: orphan detection skipped — neither tsx nor skillwiki found"

# Overlap clusters — pages sharing sources
npx tsx packages/cli/src/cli.ts overlap ~/wiki 2>/dev/null || npx skillwiki overlap ~/wiki || echo "TOOLING_UNAVAILABLE: overlap detection skipped — neither tsx nor skillwiki found"
```

**Work items to flag:**
- Pages with <2 outbound wikilinks → Hermes convention requires minimum 2 cross-references
- Orphan pages → need inbound links from other pages
- High overlap clusters → candidates for merging or comparison pages

#### B3. Page Quality (~200 tokens)
Check for thin or incomplete pages:

```bash
# Body line count per page and missing sections
python3 -c "
import os, re
base = os.path.expanduser('~/wiki')
for d in ['entities','concepts','comparisons','queries','meta']:
    dp = os.path.join(base, d)
    if not os.path.isdir(dp): continue
    for f in sorted(os.listdir(dp)):
        if not f.endswith('.md'): continue
        fp = os.path.join(dp, f)
        with open(fp) as fh: content = fh.read()
        parts = content.split('---', 2)
        if len(parts) < 3: print(f'MALFORMED_FRONTMATTER: {f}'); continue
        body = parts[2].strip()
        body_lines = body.count('\n') + 1
        has_overview = bool(re.search(r'^## Overview', body, re.M))
        has_related = bool(re.search(r'^## Related', body, re.M))
        flags = []
        if body_lines < 40: flags.append(f'THIN({body_lines}L)')
        if not has_overview: flags.append('NO_OVERVIEW')
        if not has_related: flags.append('NO_RELATED')
        if flags: print(f'{f}: {\" \".join(flags)}')
"
```

**Work items to flag:**
- Pages with <40 body lines → stubs needing enrichment from their cited raw sources
- Pages missing Overview or Related sections → quality gap

#### B4. Type Coverage (~150 tokens)
Check for empty typed directories and extraction candidates:

```bash
# Empty type directories
for d in entities concepts comparisons queries meta; do
  count=$(find ~/wiki/$d -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  echo "$d: $count pages"
done

# Entity extraction candidates — concepts mentioning people, orgs, products by name
grep -rn "^#.*(" ~/wiki/concepts/ | head -10
```

**Work items to flag:**
- `entities/` has <3 pages → extract named entities from concept pages (people, orgs, products, repos)
- `comparisons/` is empty → look for concept pages that contrast two approaches
- `queries/` is empty → natural after import; flag if >30 pages exist with no query records
- `meta/` is empty → flag when 2+ projects are active and cross-project synthesis is possible

fi # end SKIP_TRACK_B guard

### 1. VAULT RETROS (~200 tokens)
```bash
# Recent retros
grep -A5 'Improve:' ~/wiki/log.md | tail -30
# Generalized retros (distillation candidates)
grep -B2 'Generalize?: yes' ~/wiki/log.md
# Pending compound entries
ls ~/wiki/projects/llm-wiki/compound/ 2>/dev/null
```
Extract actionable improvement themes. A retro's `Improve:` field that names a concrete action is a direct work-item candidate.

### 2. SYNTHESIZE
Merge all findings from both tracks and retros. Score each:

| Score | Impact | Effort |
|-------|--------|--------|
| P0 | Spec violation or regression | Any |
| P1 | High — untested command, raw-to-page gap >50%, isolated pages | S/M |
| P2 | Medium — thin pages, skill map drift, single-source pages, empty type dirs | S/M |
| P3 | Low — code quality, cross-link improvement, section completeness | Any |
| P4+ | Speculative — proactive improvements, future-proofing, polish | Any |

**Priority bias: vault health findings rank alongside code health.** A vault with 40 raw files and 14 pages where 26 raw files lack typed knowledge pages is a P1 gap — do NOT report idle.

**Intensity-driven adjustments:**
- **normal**: Output top-3 items, P0–P3 only. Suppress recurring items that haven't changed since last pass.
- **high**: Output top-5 items, P0–P4+ included. Never suppress recurring findings — re-report with current metrics every cycle. Lower threshold for flagging (see Intensity Level section above).

Output format for each recommended work item:

```markdown
### #N: [title] (P0/P1/P2/P3/P4+)

**Source**: [vault retro | cli gap | skills audit | spec drift | raw-to-page | cross-link | page quality | type coverage | shared types | templates | git-vault gap | stale memory]
**What**: One-paragraph spec of the change.
**Acceptance**: Bullet list of verifiable outcomes.
**Files**: Likely files to touch (omit for vault-only items).
```

### 3. SAVE & EXIT
- Append one research observation to `~/wiki/log.md`:
  ```
  ## [YYYY-MM-DD HH:MM] research | dev-loop-research cycle [normal|high]
  - Findings: [count] new, [count] recurring from last pass
  - Vault health: raw=[N] pages=[N] cited=[N]% isolated=[N] thin=[N]
  - Top-N: [titles]
  ```
- If the ranked list changed since the last research cycle, update the user MEMORY.md.
- Exit with:
  - normal: `"Research cycle — [N] findings, top-3: [titles]"` or `"Research idle — no new findings."` or `"Research steady — [N] recurring: [titles]"`
  - high: `"Research high — [N] items: [titles]"` (always has findings)

## Idle Fast-Path

Two distinct idle states (three in high mode):

1. **Truly idle** — all signal sources across both tracks return zero new findings AND vault health metrics are healthy (uncited raw <20%, no isolated pages, no thin pages, no empty type dirs). Skip synthesis, write a minimal idle log entry with vault health stats, exit with: `"Research idle — no new findings."`

2. **Steady backlog** — no NEW findings this cycle, but previously identified gaps still exist. Report the recurring backlog, write a log entry noting recurrence, exit with: `"Research steady — [N] recurring findings: [titles]"`. Do NOT suppress known gaps to report idle.

3. **High mode never idle** — in high mode, states 1 and 2 above do NOT apply. Every cycle produces recommendations. If standard checks find nothing, generate proactive suggestions (new tests, documentation, speculative refactors, memory cleanup). Exit with: `"Research high — [N] items (incl. proactive): [titles]"`.

**NEVER report truly idle when vault health stats show actionable gaps.** Uncited raw >50%, any isolated page, or any thin page IS a finding. In high mode, the thresholds are tighter — uncited raw >20%, any single-source page, or any page under 60 lines IS a finding.

## Integration with Dev-Loop

Wired into dev-loop-prompt.md IDLE DISCOVERY step 4.

## Auto-Memory Protocol

The research agent saves two kinds of memory:

1. **Vault log** — every cycle writes a research observation with vault health stats.
2. **MEMORY.md** — updated only when top-3 recommendations change. Format:
   ```markdown
   - [Research backlog](research-backlog.md) — ranked work items from latest research scan
   ```

The `research-backlog.md` memory file contains:
```markdown
---
name: Research backlog
description: Latest top-N work-item recommendations from dev-loop-research (top-3 normal, top-5 high)
type: project
---

# Research Backlog (updated YYYY-MM-DD)

## Top N Recommended Work Items

1. [title] (P0/P1/P2/P3/P4+) — one-line summary
2. [title] (Px) — one-line summary
...

## Completed Items
- [x] [title] — completed YYYY-MM-DD

## Deferred Items
- [ ] [title] — reason for deferral
```
