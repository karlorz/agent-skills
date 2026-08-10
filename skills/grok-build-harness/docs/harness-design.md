# grok-build-harness — Design

The `grok-build-harness` plugin collects the karlorz subagent harness — its
assets, its design, and a one-shot bootstrap for fresh hosts — so a new machine
runs the same routing rules, the same agents, and the same model economy as the
reference host.

This document records the design. The verbatim runtime artifacts live in
`assets/` and are the source of truth for behavior:

| Asset | Runtime role |
|-------|--------------|
| `assets/agents/grok-build-byok.md` | User-scope parent agent, `promptMode: extend` — installed to `~/.grok/agents/` |
| `assets/agents/scout.md` | User-scope disposable read-only scout, `model: sonnet` — installed to `~/.grok/agents/` |
| `assets/agentrules.md` | Global subagent routing and workflow rules — installed to `~/.grok/agentrules.md` |
| `assets/AGENTS.md` | Session-start subagent contract, wrapped in a `<!-- grok-build-harness:begin/end -->` marker block — installed to `~/.grok/AGENTS.md` by a splice merge that preserves all other content (user sections, the llm-wiki skillwiki block) |
| `assets/config.toml.template` | Sanitized full config with secret tokens — rendered by `scripts/generate-config.py` |

## Goals

1. **Reproduce the harness, not just the files.** A fresh host gets the agents,
   the rules, the model aliases, and the companion plugins — the whole operating
   contract, not a folder of markdown.
2. **Fidelity to the reference host.** The config template mirrors
   `~/.grok/config.toml` section-for-section. The plugin set and its
   marketplace provenance are the same 14 enabled plugins with the same
   originating marketplaces.
3. **Secrets never ship.** The template carries `__HUB_API_KEY__` /
   `__NEW_API_KEY__` / `__CONTEXT7_API_KEY__` tokens. install.sh prompts for
   (or reads env vars for) the keys at bootstrap time and writes them into the
   generated config — matching the reference host's inline-`api_key` layout.
   Empty keys drop the `api_key` line so `env_key` keeps working.
4. **Safe to run, safe to re-run.** Every write is backup-first
   (`~/.grok/backups/grok-build-harness-<timestamp>/`), identical files are
   skipped, and `GROK_HOME` points the whole run at a scratch tree for
   dry-run testing.

## Model routing design (the core decision)

The harness economy rests on one rule: **frontier for judgment, flash for
mechanical work**.

- **Planning and final decisions stay on the main agent** (the frontier model
  the user picked). The built-in `plan` agent is unpinned so it inherits the
  parent; skills that spawn `general-purpose` for planning must override the
  sonnet pin at spawn time.
- **Dirty work goes to `sonnet`** — the flash alias. `[subagents.models]` pins
  `general-purpose`, `explore`, `browser-use`, `scout` → `sonnet`
  unconditionally. The pin beats agent frontmatter `model`, so bundled and
  third-party skills that spawn `general-purpose` without a `model:` still land
  on flash instead of leaking the frontier parent.
- **`sonnet` and `haiku` are aliases, not Claude models.** In the config they
  resolve to `deepseek-v4-flash-max` on the hub gateway
  (`hub.karldigi.dev`), which is what makes the pins economical on a BYOK
  host. Without the `[model.sonnet]` / `[model.haiku]` aliases the pins would
  resolve to nothing — the template includes them for exactly this reason.

Subagent model resolution order (grok-build v1.0.0, `README.md:1710-1717`):
`[subagents.models].<agent>` pin → agent definition `model` → parent model.

## Workflow design

- **Planning → implementation → review** is a three-actor pipeline: planning
  runs on the parent (frontier), implementation is delegated to sonnet-pinned
  `general-purpose` subagents, and the diff plus test evidence returns to the
  parent for the final accept/reject verdict. Sonnet reviewers are evidence
  gatherers, never decision-makers on a diff they did not architect.
- **Goal mode** (`/goal`): plan inherits the parent (fork); implementation goes
  through sonnet-pinned gp or the product's own implementer; skeptics resolve
  to the sonnet pin (cheap verification) rather than chasing parent skeptics —
  unpinning gp to "save cost" on skeptics breaks skill code-writing safety.
  Completion is bound by the host after the skeptic panel.
- **Delegation discipline**: prefer one-shot read-only `scout` for evidence
  packs; no nested subagent trees; no overlapping write scopes without
  worktree isolation; explicit `model:` on gp spawns even though the pin
  already enforces it.
- **Evidence rules**: `file:line` references, verbatim excerpts, spot-checks in
  the parent, real entry-point runs. A subagent result is a lead, not a fact.

## Companion plugin set

The 14 enabled plugins and their originating marketplaces (verified from
`~/.grok/installed-plugins/registry.json`, 2026-08-08):

| Marketplace | Plugins |
|---|---|
| `karlorz/agent-skills` | grok-build-harness, simplify, deep-research, dev-loop, claude-md-management, playwright-cli, grill-me, hermes-cli, codebase-architecture |
| `karlorz/llm-wiki` | skillwiki (`#packages/skills`), vault-sync (`#packages/vault-sync`) |
| `openai/codex-plugin-cc` | codex (`#plugins/codex`) |
| `anthropics/claude-plugins-official` | superpowers, context7 |

install.sh adds the marketplaces (idempotently, via `grok plugin marketplace
add`), installs each plugin with `--trust` (the trust gate activates hooks and
MCP servers; without it they silently stay inactive), and the generated config
enables them via `[plugins].enabled`. `--skip-codex`, `--skip-vault-sync`, and
`--skip-playwright-cli` exclude the heavy or host-specific ones.

## Security notes

- `api_key` beats `env_key` in grok-build's credential resolution
  (`11-custom-models.md:98-101`); the template keeps both so a host can run
  env-only (`HUB_API_KEY`) until inline keys are injected.
- `grok mcp list` prints the context7 `--api-key` argument in plaintext —
  treat MCP key material as sensitive even on the host.
- The template ships `[ui] permission_mode = "always-approve"` (personal-host
  posture). `install.sh --restrictive` renders `"plan"` instead for
  shared/non-personal hosts via the `__PERMISSION_MODE__` token.
- Missing gateway keys never fail silently: install.sh always warns when
  hub/new keys are absent (env-only consequence spelled out), and
  `--require-keys` turns that into a hard failure for unattended runs.
  context7 stays optional — it only feeds the MCP server.
- Unknown config keys warn but never fail startup; `[plugins].enabled` accepts
  bare names. The generated config is validated with `tomllib` before writing.
- The skillwiki `skillwiki:begin` block in `~/.grok/AGENTS.md` is owned by the
  llm-wiki plugin (`install:activation`). The harness contract ships wrapped
  in its own `grok-build-harness:begin/end` marker block, and the merge
  (**ADR-1**, 2026-08-09) replaces only that block — everything else in
  AGENTS.md (user sections like `## User preferences`, the skillwiki block)
  survives every re-run. v0.2.0-format files (unmarked contract) get a
  one-time block-match migration (**ADR-2**).

## Re-run safety (v0.3.0)

Field-testing v0.2.0 on the live host surfaced three silent-degradation
paths; each is now guarded:

- **AGENTS.md user content is preserved.** The old merge replaced everything
  except the skillwiki marker with the bundled contract, silently dropping a
  user-authored `## User preferences` section on re-run. Now the contract is
  a marked block and the splice keeps all non-harness content (ADR-1/2).
- **Host-set config keys are preserved.** The render previously rewrote
  `[plugins].disabled`/`paths` from the template, re-enabling deliberately
  disabled plugins. `generate-config.py --preserve` now carries over any key
  the template does not emit (whitelist rule, ADR-3): `[plugins]` sub-keys
  are injected inside the emitted section, extra tables (e.g. a user-added
  `[model."custom"]`) and `[[marketplace.sources]]` entries are appended,
  top-level scalars precede the first table header. Template-owned keys
  still win by design.
- **Keyed configs are never silently downgraded.** A re-run providing no
  keys at all over a config with injected keys now skips the render with a
  specific warning (ADR-4); `--force-render` overrides. A fresh host without
  an existing config still renders env-only as before.

## Deliberate quirks kept from the reference host

- `[models] web_search = "no-such-model"` intentionally disables the
  web-search model (no resolution attempt per search). Kept and documented
  after review (ADR-7).

## Bootstrap flow (fresh host)

```
grok plugin marketplace add karlorz/agent-skills
grok plugin install grok-build-harness --trust
/grok-build-init            # runs scripts/install.sh
```

install.sh: resolve `GROK_HOME` → backup existing files → copy agents and
rules → render and write config.toml (keys prompted or env-provided) → add
marketplaces → install plugins (`--trust`, honoring skip flags) → verify
(`grok plugin list --json`, `grok inspect --json`, agent file presence).

Verification commands are read-only; the whole run is testable against a
scratch tree with `GROK_HOME=/tmp/grok-home scripts/install.sh --dry-run`.
