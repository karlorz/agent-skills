# grok-build-harness

Fresh-host bootstrap for the karlorz subagent harness: custom agents, routing
rules, a sanitized BYOK config template, and the companion plugin set — all in
one installable plugin for [grok-build](https://x.ai).

## What it collects

| Asset | Purpose |
|---|---|
| `assets/agents/grok-build-byok.md` | Custom user-scope parent agent (`promptMode: extend`) |
| `assets/agents/scout.md` | Custom disposable read-only scout subagent (`model: sonnet`) |
| `assets/agentrules.md` | Global subagent routing and workflow rules (frontier/sonnet split, goal-mode routing, delegation discipline, evidence rules) |
| `assets/AGENTS.md` | Session-start subagent contract, wrapped in a `<!-- grok-build-harness:begin/end -->` marker block so the merge can splice updates without touching user content (or the llm-wiki skillwiki block) |
| `assets/config.toml.template` | Full sanitized config: BYOK model aliases, `[subagents.models]` pins, plugin enable list, marketplace sources, context7 MCP, `[memory]` / `[memory_v2]` enabled=false |
| `docs/harness-design.md` | The design: model routing, workflow, plugin provenance, security notes |
| `references/isolated-diagnostics.md` | Safe procedure for config diagnostics and A/B experiments (private `GROK_HOME`, live-config hashing) |

No secrets are shipped. The template carries `__HUB_API_KEY__` /
`__NEW_API_KEY__` / `__CONTEXT7_API_KEY__` tokens filled at bootstrap time by
`scripts/install.sh` (prompted or via `HARNESS_*` env vars), or left empty for
`env_key`-only operation.

## Quickstart (fresh host)

Prereqs: `python3`, `git`, and a **runnable** `grok --version` (musl hosts: do
not use a glibc grokgod shim). Remote SSH: run `install.sh` directly; do not
`ssh -t grok whoami`.

```bash
grok plugin marketplace add karlorz/agent-skills
grok plugin install grok-build-harness --trust
# start a new session, then:
/grok-build-init
```

The skill runs `scripts/install.sh`, which:

1. Backs up existing `~/.grok` files to
   `~/.grok/backups/grok-build-harness-<timestamp>/`
2. Installs the agents, `agentrules.md`, and `AGENTS.md` — the contract is
   spliced in: **all existing content is preserved** (user sections and the
   llm-wiki skillwiki marker), only the harness marker block is replaced.
   The English-thinking rule (`assets/reply-in-english.md`) is copied/spliced
   into Grok, Claude, Codex, and Cursor native load paths under `--user-home`.
3. Renders `config.toml`, carrying over host state the template does not own:
   skill/plugin path and exclusion arrays are merged as a stable, duplicate-free
   union of template defaults and host entries; other host keys the template
   never emits (extra tables, extra marketplace sources, top-level scalars)
   retain their parsed values. The requested enabled-plugin list and every model/security
   value the template emits stay authoritative. The result is validated as TOML
   and installed atomically with a stale-write check and a backup
4. Adds the companion marketplaces (karlorz-agent-skills, llm-wiki,
   openai-codex, claude-plugins-official) and installs the 13-plugin set with
   `--trust`
5. Verifies with `grok plugin list --json` and `grok inspect --json`

### Flags

```text
--grok-home DIR        target grok home (default: $GROK_HOME or ~/.grok)
--user-home DIR        parent for Claude/Codex/Cursor English-rule files
                       (default: dirname of --grok-home)
--hub-key / --new-key / --context7-key   API keys (or HARNESS_* env vars)
--require-keys         fail when hub/new gateway keys are missing (headless-safe)
--restrictive          render permission_mode = "plan" instead of "always-approve"
--force-render         rewrite an existing keyed config env-only when no keys
                       are provided (overrides the downgrade guard)
--skip-codex | --skip-vault-sync | --skip-playwright-cli   optional plugins
--skip-plugins         files + config only
--docs-only            AGENTS.md splice + agents/agentrules; skip config/plugins/keys
--docs-status          print AGENTS.md contract status and exit
--status               print a no-secrets harness inventory and exit
--no-config            skip config.toml
--dry-run              preview without writing
--force / -y           overwrite without prompting
--verify               run verification after install
```

Missing keys always produce a warning (env-only consequence spelled out);
`--require-keys` upgrades that to a hard failure for unattended runs.
Verification additionally asserts the sonnet/haiku/deepseek-v4-flash pin
aliases via `grok models`.

### Re-run safety

- **Keyed-config guard**: if the existing `config.toml` has injected keys
  (`api_key` lines / context7 `--api-key`) and a re-run provides no keys at
  all, the config render is skipped with a warning — a working keyed config
  is never silently downgraded to env-only. Pass the keys or
  `--force-render` to override.
- **User content**: anything you add to `~/.grok/AGENTS.md` outside the
  `grok-build-harness` marker block survives every re-run.
- **Host state**: on every render, `skills.ignore`, `skills.disabled`,
  `skills.paths`, `skills.server_skill_dirs`, `skills.bundled_skill_dirs`, and
  `plugins.paths` become a stable, duplicate-free union of template defaults and
  host entries; keys the template does not emit (whole tables, extra marketplace
  sources, top-level scalars, extra scalars inside shared tables) are preserved.
  The requested `[plugins].enabled` list and template-owned model/security values
  stay authoritative.
- **Config write safety**: the render must parse as TOML (Python 3.11+
  `tomllib`, or `tomli`). A missing parser exits 2 and a malformed host config,
  or an unsupported preservation shape, exits 1 — both before the destination is
  touched. Installation is staged in a temp file, `fsync`ed, and `os.replace`d,
  with the previous file backed up and the destination mode preserved. A
  symlinked `config.toml` is written through, keeping the link.
- **Stale writes**: the installer hashes the destination before rendering and
  passes that hash to `scripts/install-config.py`; a destination that changed in
  between is rejected with exit 3 instead of overwritten. Cooperating installers
  also serialize on a `~/.grok/.config.toml.lock` advisory lock (the lock file
  is intentionally not deleted). Writers that ignore both the lock and the hash
  check (a GUI config app, an editor save) remain outside that guarantee.

## Diagnostics

Never point a config experiment at the live home. Follow
`references/isolated-diagnostics.md`: private `GROK_HOME`, explicit
`--user-home`, controlled working directory, no update or install steps, an
explicit interpreter path on Windows, and a `sha256` check of the live config
before and after. `GROK_CONFIG_PATH` is allowlisted and is not a substitute for
an isolated config.

## Testing without touching a host

```bash
GROK_HOME=/tmp/grok-home bash scripts/install.sh --dry-run
```

`GROK_HOME` relocates the entire grok-build config tree, so a scratch run
exercises every write path against `/tmp` and `grok inspect` validates the
generated config there.

## Development

- Release version lives in `.claude-plugin/plugin.json` and
  `.codex-plugin/plugin.json`; bump with `scripts/bump-version.sh
  grok-build-harness` from the repo root, and keep the `vX.Y.Z:` release
  marker in all three descriptions (both manifests + marketplace.json).
- Repo contract tests: `bash scripts/test-plugin-metadata.sh` and
  `bash scripts/test-dev-loop-release-tooling.sh`.
- Validate the plugin locally: `grok plugin validate skills/grok-build-harness`.

## License

MIT
