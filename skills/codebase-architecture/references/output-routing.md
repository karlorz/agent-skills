# Output Routing — Architecture Extract Artifacts

Default markdown extract target for analyze / extract / reimplementation docs.

## Resolution order

1. **Explicit path** — if the user passed `--save <path>`, `--out <path>`, or an absolute/relative path, write there. Create parent dirs if needed.
2. **SkillWiki project architecture** — when a vault is available **and** a project page exists for the target repo:
   - Resolve vault: `skillwiki path` (must succeed).
   - Resolve project slug with the **slug algorithm** below.
   - If `projects/{slug}/` exists (create `architecture/` under that existing project if missing), **default md output** is:
     ```
     {WIKI_VAULT}/projects/{slug}/architecture/
     ```
   - Prefer numbered extract files that match the reimplementation set:
     - `00-reimplementation-blueprint.md`
     - `01-topology.md`
     - `02-module-{name}.md`, `03-module-{name}.md`, … (sequential; one major module / seam cluster per file; start at `02`)
     - Optional: `03-c4-overview.md` may share the `03` slot only when no module file needs it — prefer putting C4 overview sections in `01-topology.md` when short
     - Optional dedicated: `04-adrs.md` (or `adrs/ADR-*.md`), `05-tech-debt.md` when those registers are large
     - `08-control-layer-analysis.md` / `09-dataplane-platform-analysis.md` (layer inventories when useful)
   - Update `projects/{slug}/knowledge.md` via `skillwiki project-index --project {slug} --apply` after writes when available.
3. **Repo docs fallback** — if no vault, or no matching wiki project:
   ```
   {TARGET_REPO}/docs/architecture/
   ```
   Create `docs/architecture/` if missing. Do **not** invent a wiki project without user consent.
4. **Stdout / ephemeral** — only when user passes `--ephemeral` or asks for terminal-only.

## Repo basename (always defined)

`{repo_basename}` is independent of wiki match:

1. `git -C {TARGET_REPO} remote get-url origin` → last path segment without `.git`, if available
2. Else filesystem basename of `{TARGET_REPO}`

Use `{repo_basename}` for docs-fallback filenames such as `spec-{repo_basename}.md`.

## Project slug algorithm

Never invent a wiki project. Prefer **target-repo-root** signals over the agent’s cwd.

### Collect candidates (then decide)

Build a set of **existing** `projects/{name}/` under the vault from these signals (only add a name if that directory already exists):

1. **Target-repo binding** — `{TARGET_REPO}/skillwiki/.env` or equivalent project→wiki binding at the target repo root.
2. **Cwd binding** — only if it differs from the target root and the agent cwd is not the target: cwd `./skillwiki/.env` binding when that project exists.
3. **Remote basename** — origin URL last path segment (same as repo basename) when `projects/{name}/` exists.
4. **Directory basename** — filesystem basename of `{TARGET_REPO}` when `projects/{name}/` exists.
5. **Monorepo package** — if scope is a package subpath with its own name and `projects/{package}/` exists, include it.

### Decision

- **0 candidates** → no wiki project; use `{TARGET_REPO}/docs/architecture/`. Do not create `projects/*`.
- **1 candidate** → that `{slug}`.
- **2+ candidates** → list them and **ask the user** before writing. Do not short-circuit to “first match.”

```bash
skillwiki path
# fail → no vault → use {TARGET_REPO}/docs/architecture/
```

Optional: `skillwiki project-index` / vault search for an existing `architecture/` tree under the project.

## Plugin version for provenance

Read the plugin version from the installed plugin manifest (do not invent):

```bash
# From this package root (sibling of skills/ and references/):
#   .claude-plugin/plugin.json  →  .version
jq -r .version path/to/plugin/.claude-plugin/plugin.json
```

If the manifest is unreachable, omit the version suffix rather than guessing.

## Provenance header (every extract file)

Put this block near the top of each markdown extract (after title):

```markdown
> **Source pin:** `{owner}/{repo}` @ `{git describe --tags --always}` (`{short_sha}`)
> **Analyzed:** `{ISO-8601 date}`
> **Skill:** `codebase-architecture-analyze` v{plugin_version_from_manifest}
> **Output root:** `{resolved output root}`
```

Never claim a marketing UI version equals `pyproject` / package version without checking both.

## What goes where

| Artifact | Wiki path (preferred) | Repo fallback |
|----------|----------------------|---------------|
| Topology / tree | `architecture/01-topology.md` | `docs/architecture/01-topology.md` |
| Module / seam-cluster specs | `architecture/0N-module-{name}.md` (`02+` sequential) | same under `docs/architecture/` |
| C4 / ADRs / debt (optional files) | `04-adrs.md`, `05-tech-debt.md`, or sections in `01` / `00` | same under `docs/architecture/` |
| Blueprint / playbook | `architecture/00-reimplementation-blueprint.md` | `docs/architecture/00-….md` |
| Layer inventories | `architecture/08-*.md`, `09-*.md` | same under `docs/architecture/` |
| Improve-architecture HTML/MD review | **temp dir only** (`$TMPDIR/architecture-review-*.html` or `.md`) | same |
| Spec / PRD (`architecture-to-spec`) | `projects/{slug}/work/YYYY-MM-DD-*/spec.md` under **existing** project (create `work/` + date folder as needed) | optional issue tracker; else `docs/architecture/spec-{repo_basename}.md` |

## Spec / PRD publish order (`architecture-to-spec`)

Announce the chosen path to the user **before** writing.

1. Explicit path from user
2. Else if slug algorithm yields an existing wiki project:  
   `{WIKI}/projects/{slug}/work/YYYY-MM-DD-{topic}/spec.md`  
   Create `work/` and the dated folder under that **existing** project as needed. Do not create a new project.
3. Else if an issue tracker is clearly configured **in this session** (project convention + auth already present): create issue with ready-for-agent-style label only when that convention exists — **optional third choice**, never required
4. Else: `{TARGET_REPO}/docs/architecture/spec-{repo_basename}.md`  
   (`{repo_basename}` always defined — see above)

## Vocabulary

All architecture prose uses **codebase-design** terms: module, interface, depth, seam, adapter, leverage, locality. Do not substitute component/service/API/boundary for those meanings.

**C4 exception:** C4 diagram levels may use the word *Component* only as the **C4 Component level** label. That is diagram taxonomy, not the deep-module glossary. In extract filenames and design prose, prefer **module** / **seam cluster**.

## Related chain

See [playbook-chain.md](playbook-chain.md), [c4-evidence.md](c4-evidence.md), and vault comparison
`comparisons/codebase-analysis-reimplementation-skills.md`.
