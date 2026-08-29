---
name: grok-build-init
description: Bootstrap grok-build with the karlorz subagent harness and companion plugins. Use when initializing grok-build on a new host.
---

# grok-build-init

Initialize grok-build (v1.0+) on a host with the karlorz subagent harness:
custom user-scope agents, global routing rules, the BYOK model/config layer,
and the companion plugin set. The skill runs `scripts/install.sh` from this
plugin; it is idempotent and backup-first.

## Prerequisites

- `grok` installed and authenticated (`grok --version`, `grok login`).
- On the fresh host, this plugin itself must be installed first:

  ```bash
  grok plugin marketplace add karlorz/agent-skills
  grok plugin install grok-build-harness --trust
  ```

  Then start a new session (or press `r` in the Plugins tab) and run
  `/grok-build-init`.

## Locating install.sh

The installer ships with this plugin at `scripts/install.sh`. Resolve it from
the installed plugin root:

```bash
INSTALL="$(find ~/.grok/installed-plugins -maxdepth 3 -type f -name install.sh -path '*grok-build-harness*' | head -1)"
```

or from the agent-skills repo checkout: `skills/grok-build-harness/scripts/install.sh`.

## Procedure

1. **Update the plugin and locate installer**: On an existing install, refresh the plugin and find `install.sh`:

   ```bash
   grok plugin update grok-build-harness
   INSTALL="$(find ~/.grok/installed-plugins -maxdepth 3 -type f -name install.sh -path '*grok-build-harness*' | head -1)"
   ```

2. **Collect API keys from the user** (or read `HARNESS_HUB_KEY`,
   `HARNESS_NEW_KEY`, `HARNESS_CONTEXT7_KEY`). Two gateway keys
   (hub.karldigi.dev, new.karldigi.dev) and the context7 MCP key. If the user
   declines, install continues env-only — the generated config keeps
   `env_key` lines so `HUB_API_KEY` exports work.
3. **Run the installer** with the keys and any skip flags the user wants:

   ```bash
   bash "$INSTALL" --hub-key "$HUB_KEY" --new-key "$NEW_KEY" --context7-key "$CTX7_KEY" --verify
   ```

   Optional flags: `--skip-codex`, `--skip-vault-sync`, `--skip-playwright-cli`
   (heavy or host-specific plugins); `--require-keys` (hard-fail when hub/new
   gateway keys are missing — use for unattended runs); `--restrictive`
   (render `permission_mode = "plan"` instead of `"always-approve"` for
   shared hosts); `--with-grokgod` / `--skip-grokgod` (force or skip grokgod
   `[plan_mode] implement_via_subagents = true` merge; auto-detected by default);
   `--force-render` (rewrite an existing keyed config env-only
   when no keys are provided — the default is to skip the config render
   instead, to avoid silently downgrading a working keyed config); `--dry-run`
   to preview without writing; `--no-config` to skip config.toml. When keys
   are missing the installer always warns that the config will be env-only
   (model aliases won't resolve until `HARNESS_HUB_KEY` / `HARNESS_NEW_KEY`
   are exported).
4. **Verify** (installer's `--verify` step): `grok plugin list --json` shows
   the 14 enabled plugins (13 companions + grok-build-harness itself), `grok inspect --json` reports agents discovered
   (expect the 2 user agents + plugin agents), stamp file is inspected,
   config does not pair `[agent] name = grok-build-byok` with `agent_type = "codex"`,
   and no unresolved key tokens in config.toml.
5. **Finish**: tell the user to start a new session so `~/.grok/AGENTS.md` and
   the agents load. The skillwiki activation file (`~/.grok/skillwiki.md` and
   the `AGENTS.md` marker block) is owned by the llm-wiki plugin's
   `install:activation` — the harness installer preserves any existing marker;
   no manual step needed.

## What gets installed

| Path (under `~/.grok/`) | Content |
|---|---|
| `agents/grok-build-byok.md`, `agents/scout.md` | Custom parent agent + disposable read-only scout (verbatim) |
| `agentrules.md` | Global subagent routing/workflow rules (verbatim) |
| `AGENTS.md` | Subagent contract in a `<!-- grok-build-harness:begin/end -->` block — spliced in: all other content (user sections, skillwiki marker) is preserved |
| `config.toml` | Rendered from the sanitized template: model aliases (sonnet/haiku → deepseek-v4-flash-max via hub), `[subagents.models]` pins, `[subagents.toggle] grok-build-byok = false`, `[agent] name`, plugin enable list, context7 MCP |
| `.grok-build-harness-stamp.json` | Harness install stamp (`grok-build-harness-stamp/v1`): plugin version, root, install timestamp, and grokgod detection |

Existing files are backed up to
`~/.grok/backups/grok-build-harness-<timestamp>/` before overwrite; identical
files are skipped. Re-runs preserve host-set config keys the template does
not emit (`[plugins].disabled`, extra marketplace sources, extra tables),
and a re-run with no keys over a keyed config skips the render (use
`--force-render` to override).

## Troubleshooting

- **Harness rules not active** → confirm `~/.grok/AGENTS.md` + `agentrules.md`
  exist and start a new session.
- **Plugin skills missing** → `grok plugin list`; add the name to
  `[plugins].enabled` or press `Space` in the Plugins tab; reload with `r`.
- **Hooks/MCP servers inactive** → plugins were installed without trust;
  reinstall with `--trust` (`grok plugin uninstall <name> --confirm &&
  grok plugin install <name> --trust`).
- **Models don't resolve ("sonnet" unknown)** → the `[model.*]` aliases are
  missing or keys were not injected; re-run install.sh with keys, or export
  `HUB_API_KEY` / `NEW_API_KEY` (env_key fallback).
- **Test without touching the host** →

  ```bash
  GROK_HOME=/tmp/grok-home bash "$INSTALL" --dry-run
  ```

  `GROK_HOME` relocates the whole grok tree; `grok inspect` against the scratch
  home validates the generated config safely.

## References

- Design and rationale: `docs/harness-design.md` in this plugin.
- Config semantics: `~/.grok/docs/user-guide/05-configuration.md`,
  `09-plugins.md`, `16-subagents.md`.
