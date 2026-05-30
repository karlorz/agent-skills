---
name: investigate
version: "1.0.0"
description: >
  Companion prompt for dev-loop investigate mode. Proactively scans project
  health (code, vault, transcripts, deep-research) and creates structured
  status:proposed work items in the vault. Invoked via /dev-loop investigate
  [high] [topic]. Requires query_vault in BACKEND_CAPS.
type: companion-prompt
mode: on-demand
---

# Dev-Loop Investigate Mode

Proactive work-item creation pipeline. Scans project health across four
sources, deduplicates against existing work, and creates structured
`status: proposed` work items in the vault for future CORE cycles to consume.

## Prerequisites

**Vault required.** If `query_vault` not in BACKEND_CAPS, refuse:
"Investigate mode requires a vault — run `/setup-dev-loop` to configure one."

This gate is an architectural decision (ADR: `projects/{slug}/architecture/
investigate-mode-vault-required.md`). See the ADR for trade-off rationale
and upgrade path.

## Invocation

The parent dev-loop controller parses args and delegates here with:
- `INTENSITY`: `normal` | `high`
- `INVESTIGATE_TOPIC`: string or empty

```
/dev-loop investigate                           → normal, no topic
/dev-loop investigate high                      → high, no topic
/dev-loop investigate "plugin SDK changes"      → normal, topic set
/dev-loop investigate high "plugin SDK changes" → high, topic set
```

## Model Strategy

| Step | Model | Rationale |
|------|-------|-----------|
| 1. QUERY | sonnet (agent) | Vault search — mechanical lookup |
| 2. SCAN | sonnet (agent) | Research-worker already runs on sonnet |
| 3. DEEPEN | sonnet (agent) | Deep-research manages its own model internally |
| 4. TRIAGE | parent (inline) | Judgment: which findings matter, ranking, dedup |
| 5. SPEC | parent (inline) | Writing specs is creative/architectural |
| 6. RETRO | parent (inline) | Low token, always inline |
| 7. SAVE | parent (inline) | Vault auto-commit, low token |

~70% token spend on sonnet (SCAN + DEEPEN), ~30% on parent (TRIAGE + SPEC).

## Configuration

Read from `investigate` section in `.claude/dev-loop.config.md`:

```yaml
investigate:
  max_items: 5           # cap per invocation (high doubles it)
  topic_seeds: []        # fallback when no user topic; reuses idle_deep_research.topic_seeds if empty
```

**Defaults when absent:**
- `max_items`: 5
- `topic_seeds`: falls back to `idle_deep_research.topic_seeds` from config.
  If that's also empty, DEEPEN step is skipped unless user provides a topic.

## Pipeline

```
┌─────────────────────────────────────────────────────────┐
│ 0. REFRESH (already done by parent dev-loop)            │
├─────────────────────────────────────────────────────────┤
│ INVESTIGATE CORE                                        │
│  1. QUERY     Context check — existing work items,     │
│               prior investigate runs, retros            │
│  2. SCAN      Research-worker (Track A + Track B)       │
│               + unclaimed transcripts                   │
│  3. DEEPEN    Deep-research (high or user topic only)   │
│  4. TRIAGE    Deduplicate, rank, cap                    │
│  5. SPEC      Create proj-work items (tiered output)    │
├─────────────────────────────────────────────────────────┤
│ POSTLUDE                                                │
│  6. RETRO     Log investigation results                 │
│  7. SAVE      Vault auto-commit                         │
└─────────────────────────────────────────────────────────┘
```

## Step Details

### 1. QUERY — context for dedup

Gather existing state to prevent duplicate work-item creation:

1. **List existing work items** — `ls {vault}/projects/{slug}/work/` to get
   all current slugs and their statuses. Parse spec.md frontmatter for
   `status`, `name`, `title`.
2. **Check project history** — `ls {vault}/projects/{slug}/history/` for
   archived work-item slugs (completed work that shouldn't be re-proposed).
   If `history/` is absent, treat as empty.
3. **Read recent retros** — scan `{vault}/log.md` for the last 10 retro
   entries to understand what's been investigated recently.
4. **Check prior investigate runs** — grep log.md for `investigate-cycle`
   entries. If the last investigate run was <24h ago AND intensity is the
   same, warn: "Investigate ran recently (<time> ago) — findings may overlap.
   Continue anyway." Do not block.

Store results as `EXISTING_SLUGS` (set of name slugs + statuses) and
`HISTORY_SLUGS` (set) for TRIAGE.

### 2. SCAN — research-worker (code + vault health + transcripts)

Invoke the existing research-worker with the same interface as IDLE step 4:

```
Agent(description: "Investigate scan", subagent_type: "dev-loop:research-worker",
  model: "sonnet", prompt: "Run research cycle with intensity: <INTENSITY>.
  BACKEND_CAPS: <caps>. VAULT_TYPES: <types>. CRITICAL_PATHS: <paths>.
  Scan code health and vault health per research/SKILL.md.
  Return ALL findings regardless of P-score — do not filter.
  Output as structured findings list.")
```

**Key difference from IDLE:** request ALL findings, not just top-N. TRIAGE
handles filtering — the scan should be exhaustive.

**Inline fallback:** If agent spawn fails (1M-context error per session
memory), run the research scan inline using `Skill("dev-loop:research")`.

**Unclaimed transcripts** — after research-worker returns, scan
`{vault}/raw/transcripts/` for files matching the project slug that are
NOT referenced by any existing work item's `closes:` list. Each unclaimed
transcript is a candidate finding:
- `kind: idea` → P3 finding
- `kind: bug` → P2 finding
- `kind: task` → P2 finding
- Other/unknown → P3 finding

### 3. DEEPEN — deep-research (conditional)

**Hard skip gate (always):**
- `deep-research:deep-research` in `DEP_DRIFT`

When this dependency is missing, skip DEEPEN regardless of intensity/topic.
Continue with SCAN-only findings.

**Run if ANY of (when dependency is available):**
- `INTENSITY == high` (use `topic_seeds` round-robin or first unused seed)
- `INVESTIGATE_TOPIC` is non-empty (user explicitly asked — run regardless
  of intensity)

**Otherwise skip:**
- `INTENSITY == normal` AND `INVESTIGATE_TOPIC` is empty

**Execution:**

If `INVESTIGATE_TOPIC` is set:
```
Invoke Skill("deep-research") with topic = INVESTIGATE_TOPIC
```

If topic is empty (high mode, no user topic):
- Pick next topic from `investigate.topic_seeds` (or fall back to
  `idle_deep_research.topic_seeds`). Round-robin based on which seeds
  have NOT been investigated in the last 7 days (check vault query pages).
- If all seeds are recently covered, skip DEEPEN.

**Output:** Extract actionable ideas from deep-research results. Each idea
becomes a candidate finding with:
- P-score: P3 (exploratory by default)
- kind: `idea`
- Source: `deep-research: <topic>`

**Budget:** Honor `idle_deep_research.budget.*` caps if configured.
Default: `max_sources: 5`, `max_tokens: 50000`.

### 4. TRIAGE — deduplicate, rank, cap

This step runs **inline on the parent model** — it's the judgment core
of investigate.

**Input:** Combined findings from SCAN + DEEPEN (if run).

**Step 4a — Deduplicate:**

For each candidate finding, generate a slug from its title (lowercase,
hyphens, strip common words). Then check:

1. If slug ∈ `EXISTING_SLUGS`:
   - Status `proposed` or `planned` → **skip** (already queued)
   - Status `in-progress` → **skip** (being worked on)
   - Status `completed` → **skip** unless the finding references changes
     since the completion date
2. If slug ∈ `HISTORY_SLUGS` → **skip** (work completed and archived)
3. If slug matches an existing slug with >70% character overlap (Levenshtein
   or common-prefix) → **flag** as "possibly related" but still include

Log skipped duplicates: "Skipped: <slug> (existing: <status>)"

**Step 4b — Rank:**

Sort remaining findings by:
1. P-score (P0 first)
2. Within same P-score: critical-path matches first (if `CRITICAL_PATHS` set)
3. Within same P-score and critical-path tier: concrete findings before
   exploratory ones

**Step 4c — Cap:**

Apply intensity-based cap:
- `normal`: `investigate.max_items` (default 5)
- `high`: `investigate.max_items * 2` (default 10)

Discard findings beyond the cap. Log: "Capped at <N> items (<M> total
findings, <K> deduplicated)."

**Step 4d — Tier assignment:**

For each surviving finding, assign an output tier:

- **Full spec** — the finding points to a **concrete code change** with
  identifiable files, functions, or expected behavior. Examples: "simplify
  has no tests", "marketplace.json version drift", "missing pre-flight
  check in script X."
- **Stub** — the finding points to a **question, investigation, or
  exploratory improvement**. Examples: "investigate agentmemory integration",
  "research Claude Code SDK v2 changes", "evaluate alternative lint rules."

Heuristic: if the finding references specific file paths or has a clear
acceptance criteria expressible as a command (`test passes`, `lint clean`,
`version matches`), it's a full spec. Otherwise, stub.

### 5. SPEC — create work items

For each triaged finding, create a work item via `proj-work`:

**Common frontmatter:**
```yaml
---
title: "<conventional-commit-style title>"
name: <slug>
description: "<one-paragraph summary>"
kind: <bug|feature|task|idea>   # derived from finding source
status: proposed                # always proposed, never planned
priority: <high|medium|low>     # derived from P-score: P0-P1→high, P2→medium, P3+→low
project: "[[<project-slug>]]"
created: YYYY-MM-DD
tags:
  - <project-slug>
  - investigate
  - <source-track>              # e.g., code-health, vault-health, transcript, deep-research
source_investigate: true        # marker for investigate-created items
---
```

**Full spec body:**
```markdown
# <title>

## Problem
<What's wrong or missing — from the finding>

## Requirements
<Concrete changes needed — files, functions, expected behavior>

## Acceptance
<Verifiable outcomes — commands to run, states to check>

## Sources Used
- <finding source reference>
```

**Stub body:**
```markdown
# <title>

## Problem
<What's wrong or missing — from the finding>

## Investigation Questions
- <What needs to be explored before this can be spec'd>
- <What alternatives exist>

## Acceptance
- Investigation questions answered
- Decision recorded (ADR if architectural)
- Follow-up work item created if action needed
```

**Rate limiting:** If creating >3 items, batch-commit vault changes after
every 3 items to avoid large uncommitted working trees.

### 6. RETRO — log investigation

Append to `{vault}/log.md`:

```markdown
## [YYYY-MM-DD] retro | investigate-cycle: <project-slug>
- Mode:          investigate (<intensity>)
- Topic:         <user topic or "autonomous">
- Scanned:       <N> total findings
- Deduplicated:  <K> skipped
- Created:       <M> proposed work items
- Items:         <slug1> (P<x>), <slug2> (P<y>), ...
- Friction:      <any issues during investigation>
- Generalize?:   no
- ClaudeMd?:     no
- WorkflowShift?: no
```

### 7. SAVE — vault auto-commit

Same as CORE step 7:
1. If `VAULT_AUTO_COMMIT` is true AND vault is dirty:
   `git -C $VAULT add -A && git -C $VAULT commit -m "dev-loop[investigate]: <N> proposed items for <slug>"`
2. If `VAULT_SYNC_PEER_AWARE`: acquire lock, push, release.
3. If presync skill available: run before push.

## Hard Rules (investigate-specific)

1. **Never create `status: planned` items.** All investigate output is
   `proposed`. The human promotes.
2. **Never execute work.** Investigate creates specs, not code. If a
   finding is trivially fixable, still create the work item — let
   CORE's trivial fast-path handle it.
3. **Respect the cap.** Never exceed `max_items * (2 if high else 1)`.
   If TRIAGE produces more, discard the lowest-ranked.
4. **Dedup is mandatory.** Every finding must pass the slug + status +
   archive check. Skipping dedup creates vault clutter.
5. **Log everything.** RETRO must include counts (scanned, deduped,
   created) for auditability. Silent investigate runs are forbidden.

## Interaction with Other Modes

| Scenario | Behavior |
|----------|----------|
| `/dev-loop investigate` then `/dev-loop` | CORE picks up proposed items (if promoted to planned) |
| `/dev-loop investigate` then `/dev-loop investigate` | TRIAGE dedup prevents duplicates |
| `/loop 2h /dev-loop investigate` | Recurring investigation, safe due to dedup + 24h warning |
| `/dev-loop investigate` with no vault | Refuses with actionable message |
| IDLE research finds P2+ | Does NOT auto-create items (IDLE stays passive) |
