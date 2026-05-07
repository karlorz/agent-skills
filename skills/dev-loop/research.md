---
name: dev-loop-research
description: "Generic research agent for the dev-loop skill. Scans repo health (CLI, skills, spec drift) and vault health (raw-to-page coverage, cross-link density, page quality, type coverage), cross-references with vault retros, outputs a prioritized work-item recommendation list. Reads project config from .claude/dev-loop.config.md. Pass `high` for aggressive mode."
type: companion-prompt
mode: recurring
---

# Dev-Loop Research Agent (Generic)

> **Status: ACTIVE.** Companion to `dev-loop`. Phase 3 cutover complete.

Runs as a recurring research loop. Each pass scans **two parallel
tracks** — code health and vault health — cross-references findings,
and outputs a prioritized work-item recommendation list. When no new
findings emerge across both tracks, exits idle with a one-line status.

This prompt is project-agnostic. All paths, globs, and project
specifics come from `./.claude/dev-loop.config.md` (loaded via the
parent skill's REFRESH step). Do not hardcode project-specific values
in this file.

## Intensity Level

Parse arguments for `high` (case-insensitive). If present,
**intensity = high**; otherwise **intensity = normal**.

### normal (default)
Respect priority tiers. Output top-3 ranked items. Use idle fast-path
when all signals are healthy. Suppress recurring findings that haven't
changed since last pass.

### high
Aggressive mode — **every finding is actionable, priority gates removed.**

- **Output top-5** ranked items (expanded from top-3).
- **Never suppress recurring findings** — re-report them every cycle
  with updated metrics so they stay visible.
- **Lower flagging thresholds**:
  - Thin pages: flag at <60 body lines (up from <40).
  - Uncited raw: flag at >20% (down from >50%).
  - Single-source pages: always flag (not just confidence-low).
  - Cross-links: flag pages with <3 outbound links (up from <2).
- **Include speculative findings**: items normally deferred (e.g.,
  empty type dirs regardless of total page count, potential entity
  extraction candidates, code quality improvements).
- **Expand search surface**: in addition to standard tracks, also scan:
  - Shared types / utility dirs for unused exports or stale types.
  - Templates dirs for drift.
  - Git log for recent commits without corresponding vault retros.
  - Memory files in `~/.claude/projects/.../memory/` for stale entries.
- **Never report truly idle** — in high mode there is always something
  to recommend. If all standard checks pass, suggest proactive
  improvements (new test cases, documentation enrichments, speculative
  refactors).
- **P4+ items are first-class** — score and include them in
  recommendations.

## When to Invoke

1. **Dev-loop idle path**: When dev-loop IDLE DISCOVERY triggers (QUERY
   finds no claimable work AND nothing is in progress), the parent
   skill delegates to this agent.
2. **Standalone**: schedule recurring background scans via the loop
   skill (e.g. `/loop 1h dev-loop-research`).
3. **Intensive sprint**: pass `high` for aggressive continuous scanning.
4. **One-shot**: invoke once when the dev-loop is idle.

## Single-Pass Cycle

```
┌─────────────────────────────────────────────────────────────────┐
│ 0. REFRESH                                                      │
│    Load project config + read CLAUDE.md/MEMORY.md fresh         │
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
│     Canonical spec compliance,  │     Thin pages, missing       │
│     scope vs actual, deferred   │     sections, single-source   │
│     leaks                       │     pages                     │
│                                 │                               │
│ A4. UNPUSHED COMMITS            │ B4. TYPE COVERAGE             │
│     Commits ahead of remote,    │     Empty dirs, entity        │
│     batch push recommended      │
│                                 │     extraction candidates,    │
│                                 │     comparison/query gaps     │
├─────────────────────────────────┴───────────────────────────────┤
│ 1. VAULT RETROS (cross-cutting)                                 │
│    Scan {vault}/log.md for recent Improve: and Generalize?: yes │
│    Check {vault}/projects/{slug}/compound/ for pending          │
│    distillation work                                            │
├─────────────────────────────────────────────────────────────────┤
│ 2. SYNTHESIZE                                                   │
│    Merge findings from both tracks + retros.                    │
│    Score each finding: impact × effort (P0–P3, +P4 in high).    │
│    Output top-N ranked work items with inline specs.            │
├─────────────────────────────────────────────────────────────────┤
│ 3. SAVE & EXIT                                                  │
│    Append findings to {vault}/log.md as research observation.   │
│    If top-N changed since last pass, update MEMORY.md.          │
│    Exit with one-line summary.                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Step Details

### 0. REFRESH

Confirm project config is loaded. Required fields for this agent:
`slug`, `vault`, `cli_src`, `cli_test`, `skills_glob` (optional). If
`vault` is empty, skip Track B entirely and run Track A only. If
`cli_src` is empty, skip Track A and run Track B only.

Read `CLAUDE.md` and the user MEMORY.md fresh.

### Track A: Code Health

Skip this track entirely if `cli_src` is empty.

#### A1. CLI Coverage Gaps

List all files matching `{cli_src}/*.ts` (or whatever extension the
project uses). For each, check:

- **Test coverage**: Does a sibling `{cli_test}/{name}.test.ts` exist?
  If not, flag.
- **Behavioral conventions**: Does the command follow project-declared
  conventions (e.g., `--human` flag, stable exit codes)? Read these
  conventions from `CLAUDE.md` or `notes` in project config.
- **Markers**: `grep -n 'TODO\|FIXME\|HACK\|XXX' {cli_src}/{name}.*`

Discover counts at runtime:

```
ls {cli_src}/*.ts | wc -l
ls {cli_test}/*.test.ts | wc -l
```

Compare against any documented count in CLAUDE.md. Flag drift.

#### A2. Skills Audit

If `skills_glob` is non-empty, list all SKILL.md files matching it.
For each, check:

- Does it reference correct CLI subcommands that actually exist?
- Does the skill's description match current CLI behavior?
- Does any "skill map" or "using-*" skill list all skills correctly?

Discover skill count at runtime: `ls {skills_glob} | wc -l`.

#### A3. Spec Drift

If project config or CLAUDE.md points to a canonical spec (e.g.,
`notes.canonical_spec`), verify scope-defining fields against current
code. Key drift signals:

- New commands not in spec → document or spec update needed?
- Changed counts (skills, commands) compared to spec snapshot?
- New frontmatter fields or schema changes not in spec?

#### A4. Unpushed Commits

Check for commits that exist locally but not on the remote release branch:

```bash
RELEASE_BRANCH=${release_branch:-main}
UNPUSHED=$(git log origin/$RELEASE_BRANCH..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNPUSHED" -gt 0 ]; then
  echo "UNPUSHED_COMMITS: $UNPUSHED commits ahead of origin/$RELEASE_BRANCH"
fi
```

**Priority scoring:**
- ≥10 unpushed commits → P1 (risk of lost work)
- 5-9 unpushed commits → P2 (batch push recommended)
- 1-4 unpushed commits → P4+ (defer, not urgent)

**Intensity interaction:**
- In **high** mode, any unpushed count ≥1 becomes claimable via the P4+ pickup rule
- In **normal** mode, respect the priority gates above

### Track B: Vault Health

Skip this track entirely if `vault` is empty or `{vault}` does not
exist.

#### B1. Raw-to-Page Coverage

```bash
# Vault existence guard
if [ ! -d "$VAULT/raw" ]; then
  echo "VAULT_NOT_INITIALIZED: $VAULT/raw not found — skipping Track B"
  SKIP_TRACK_B=1
fi

if [ -z "$SKIP_TRACK_B" ]; then

# Total raw vs typed pages
RAW_COUNT=$(find "$VAULT/raw" -name "*.md" | wc -l | tr -d ' ')
PAGE_COUNT=$(find "$VAULT"/{entities,concepts,comparisons,queries,meta} -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$RAW_COUNT" -gt 0 ]; then
  CITED=$(grep -rh '\^\[raw/' "$VAULT"/{entities,concepts,comparisons,queries,meta}/ 2>/dev/null | sed -n 's/.*\^\[raw\/\([^]]*\)\].*/\1/gp' | sort -u | wc -l | tr -d ' ')
  UNCITED=$((RAW_COUNT - CITED))
  echo "Raw: $RAW_COUNT, Pages: $PAGE_COUNT, Cited: $CITED, Uncited: $UNCITED ($((UNCITED * 100 / RAW_COUNT))%)"
else
  echo "Raw: 0, Pages: $PAGE_COUNT"
fi

# Pages citing only 1 source (low confidence flag)
find "$VAULT"/{entities,concepts,comparisons,queries,meta} -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' f; do
  cites=$(grep -c '\^\[raw/' "$f" 2>/dev/null || true)
  cites=${cites:-0}
  if [ "$cites" -le 1 ]; then
    echo "SINGLE-SOURCE: $f ($cites citations)"
  fi
done
```

**Work items to flag:**
- normal: uncited raw >50% → P1; single-source pages → P2
- high: uncited raw >20% → P1; any single-source page → P2

#### B2. Cross-Link Density

**Counting rule (deterministic):** an *outbound link* is a unique
`[[wikilink]]` token that appears in the **body region** (everything
after the second `---` frontmatter delimiter) AND resolves to a
different page in the vault. Self-references (link to own slug) are
excluded. Duplicates of the same target within one page count as one.

```bash
python3 -c "
import os, re
base = '$VAULT'
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
        threshold = 3 if '$INTENSITY' == 'high' else 2
        if len(links) < threshold: print(f'ISOLATED: {f} ({len(links)} outbound links)')
"

# Orphan and overlap detection via skillwiki CLI (resolved via cli_entry_override or installed binary)
${CLI_ENTRY:-skillwiki} orphans "$VAULT" 2>/dev/null || echo "TOOLING_UNAVAILABLE: orphan detection skipped"
${CLI_ENTRY:-skillwiki} overlap "$VAULT" 2>/dev/null || echo "TOOLING_UNAVAILABLE: overlap detection skipped"
```

**Work items to flag:**
- normal: <2 outbound wikilinks → P2; orphan pages → P2; high-overlap clusters → P3
- high: <3 outbound wikilinks → P2; everything else same

#### B3. Page Quality

**Counting rule (deterministic):** a page's *body line count* is the
number of non-blank lines in the body region (everything after the
second `---` frontmatter delimiter), **excluding**:
- empty leading and trailing blank lines
- lines that are only `## Heading` markers
- lines containing only the `---` delimiter itself

A page is **thin** when body line count is below the active threshold
(40 in normal mode, 60 in high mode). This rule must be applied
identically across cycles so isolated/thin counts are comparable.

```bash
python3 -c "
import os, re
base = '$VAULT'
threshold = 60 if '$INTENSITY' == 'high' else 40
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
        # Counting rule: non-blank lines, excluding heading-only and --- lines
        body_lines = sum(
            1 for line in body.splitlines()
            if line.strip()
            and not re.match(r'^#{1,6}\s+\S', line)
            and line.strip() != '---'
        )
        has_overview = bool(re.search(r'^## Overview', body, re.M))
        has_related = bool(re.search(r'^## Related', body, re.M))
        flags = []
        if body_lines < threshold: flags.append(f'THIN({body_lines}L)')
        if not has_overview: flags.append('NO_OVERVIEW')
        if not has_related: flags.append('NO_RELATED')
        if flags: print(f'{f}: {\" \".join(flags)}')
"
```

**Work items to flag:**
- Pages under threshold body lines → stubs needing enrichment
- Pages missing Overview or Related sections → quality gap

#### B4. Type Coverage

```bash
for d in entities concepts comparisons queries meta; do
  count=$(find "$VAULT/$d" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  echo "$d: $count pages"
done
```

**Work items to flag:**
- `entities/` <3 pages → extract named entities from concept pages
- `comparisons/` empty → look for concept pages contrasting approaches
- `queries/` empty → flag if >30 pages exist with no query records
- `meta/` empty → flag when 2+ projects are active and cross-project
  synthesis is possible

In high mode, flag empty dirs regardless of page count.

```bash
fi # end SKIP_TRACK_B guard
```

### 1. VAULT RETROS

```bash
# Recent retros
grep -A5 'Improve:' "$VAULT/log.md" | tail -30
# Generalized retros (distillation candidates)
grep -B2 'Generalize?: yes' "$VAULT/log.md"
# Pending compound entries
ls "$VAULT/projects/$SLUG/compound/" 2>/dev/null
```

A retro's `Improve:` field that names a concrete action is a direct
work-item candidate.

### 2. SYNTHESIZE

Merge all findings from both tracks and retros. Score each:

| Score | Impact | Effort |
|-------|--------|--------|
| P0 | Spec violation or regression | Any |
| P1 | High — untested command, raw-to-page gap >50%, isolated pages | S/M |
| P2 | Medium — thin pages, skill map drift, single-source pages, empty type dirs | S/M |
| P3 | Low — code quality, cross-link improvement, section completeness | Any |
| P4+ | Speculative — proactive improvements, future-proofing, polish | Any |

**Priority bias: vault health findings rank alongside code health.**
A vault with 40 raw files and 14 pages where 26 raw files lack typed
knowledge pages is a P1 gap — do NOT report idle.

**Intensity-driven adjustments:**
- **normal**: Output top-3 items, P0–P3 only. Suppress recurring items
  that haven't changed since last pass.
- **high**: Output top-5 items, P0–P4+ included. Never suppress
  recurring findings — re-report with current metrics every cycle.

Output format for each recommended work item:

```markdown
### #N: [title] (P0/P1/P2/P3/P4+)

**Source**: [vault retro | cli gap | skills audit | spec drift | raw-to-page | cross-link | page quality | type coverage | shared types | templates | git-vault gap | stale memory]
**What**: One-paragraph spec of the change.
**Acceptance**: Bullet list of verifiable outcomes.
**Files**: Likely files to touch (omit for vault-only items).
```

### 3. SAVE & EXIT

- Append one research observation to `{vault}/log.md`:
  ```
  ## [YYYY-MM-DD HH:MM] research | dev-loop-research cycle [normal|high]
  - Findings: [count] new, [count] recurring from last pass
  - Vault health: raw=[N] pages=[N] cited=[N]% isolated=[N] thin=[N]
  - Top-N: [titles]
  ```
- If the ranked list changed since the last research cycle, update the
  user MEMORY.md with a `research-backlog.md` entry.
- Exit with:
  - normal: `"Research cycle — [N] findings, top-3: [titles]"` or
    `"Research idle — no new findings."` or
    `"Research steady — [N] recurring: [titles]"`
  - high: `"Research high — [N] items: [titles]"` (always has findings)

## Idle Fast-Path

Two distinct idle states (three in high mode):

1. **Truly idle** — all signal sources across both tracks return zero
   new findings AND vault health metrics are healthy (uncited raw
   <20%, no isolated pages, no thin pages, no empty type dirs). Skip
   synthesis, write a minimal idle log entry with vault health stats,
   exit with: `"Research idle — no new findings."`

   **Pre-idle gate (mandatory):** Before declaring truly idle, the
   agent MUST collect actual vault health metrics by running B1–B4
   (or reading their output if already computed). If any metric
   exceeds the thresholds below, the agent is NOT idle — it MUST
   proceed to SYNTHESIZE with those findings:

   | Metric | normal threshold | high threshold |
   |--------|-----------------|----------------|
   | Uncited raw | >50% | >20% |
   | Isolated pages | any | any (<3 links) |
   | Thin pages | any (<40L) | any (<60L) |
   | Empty type dirs | any (entities, comparisons) | any |

   Skip this gate and you will report idle while actionable vault
   work exists (this was the idle-threshold-gap bug).

2. **Steady backlog** — no NEW findings this cycle, but previously
   identified gaps still exist. Report the recurring backlog, write a
   log entry noting recurrence, exit with: `"Research steady — [N]
   recurring findings: [titles]"`. Do NOT suppress known gaps to
   report idle.

3. **High mode never idle** — in high mode, states 1 and 2 do NOT
   apply. Every cycle produces recommendations. If standard checks
   find nothing, generate proactive suggestions (new tests,
   documentation, speculative refactors, memory cleanup).

**NEVER report truly idle when vault health stats show actionable
gaps.** Uncited raw >50%, any isolated page, or any thin page IS a
finding. In high mode, the thresholds are tighter — uncited raw >20%,
any single-source page, or any page under 60 lines IS a finding.

## Auto-Memory Protocol

The research agent saves two kinds of memory:

1. **Vault log** — every cycle writes a research observation with
   vault health stats.
2. **MEMORY.md** — updated only when top-N recommendations change.
   Format:
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
