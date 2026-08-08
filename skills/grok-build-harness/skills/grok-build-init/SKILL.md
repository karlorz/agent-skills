---
name: grok-build-init
description: Bootstrap a fresh host's grok-build with the karlorz subagent harness — custom agents (grok-build-byok, scout), agentrules.md, subagent-contract AGENTS.md, sanitized BYOK config, and the companion plugin set. Use when initializing grok-build on a new machine, re-running the harness after an upgrade, or reproducing the harness in a scratch GROK_HOME for testing.
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

1. **Collect API keys from the user** (or read `HARNESS_HUB_KEY`,
   `HARNESS_NEW_KEY`, `HARNESS_CONTEXT7_KEY`). Two gateway keys
   (hub.karldigi.dev, new.karldigi.dev) and the context7 MCP key. If the user
   declines, install continues env-only — the generated config keeps
   `env_key` lines so `HUB_API_KEY` exports work.
2. **Run the installer** with the keys and any skip flags the user wants:

   ```bash
   bash "$INSTALL" --hub-key "$HUB_KEY" --new-key "$NEW_KEY" --context7-key "$CTX7_KEY" --verify
   ```

   Optional flags: `--skip-codex`, `--skip-vault-sync`, `--skip-playwright-cli`
   (heavy or host-specific plugins); `--dry-run` to preview without writing;
   `--no-config` to skip config.toml.
3. **Verify** (installer's `--verify` step): `grok plugin list --json` shows
   the 13 companion plugins, `grok inspect --json` reports agents discovered
   (expect the 2 user agents + plugin agents) and no unresolved key tokens in
   config.toml.
4. **Finish**: tell the user to start a new session so `~/.grok/AGENTS.md` and
   the agents load. The skillwiki activation file (`~/.grok/skillwiki.md` and
   the `AGENTS.md` marker block) is owned by the llm-wiki plugin's
   `install:activation` — the harness installer preserves any existing marker;
   no manual step needed.

## What gets installed

| Path (under `~/.grok/`) | Content |
|---|---|
| `agents/grok-build-byok.md`, `agents/scout.md` | Custom parent agent + disposable read-only scout (verbatim) |
| `agentrules.md` | Global subagent routing/workflow rules (verbatim) |
| `AGENTS.md` | Subagent contract (skillwiki marker block preserved if present) |
| `config.toml` | Rendered from the sanitized template: model aliases (sonnet/haiku → deepseek-v4-flash-max via hub), `[subagents.models]` pins, `[agent] name`, plugin enable list, context7 MCP |

Existing files are backed up to
`~/.grok/backups/grok-build-harness-<timestamp>/` before overwrite; identical
files are skipped.

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
