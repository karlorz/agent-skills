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
| `assets/AGENTS.md` | Session-start subagent contract (skillwiki marker block excluded — the llm-wiki plugin owns it) |
| `assets/config.toml.template` | Full sanitized config: BYOK model aliases, `[subagents.models]` pins, plugin enable list, marketplace sources, context7 MCP |
| `docs/harness-design.md` | The design: model routing, workflow, plugin provenance, security notes |

No secrets are shipped. The template carries `__HUB_API_KEY__` /
`__NEW_API_KEY__` / `__CONTEXT7_API_KEY__` tokens filled at bootstrap time by
`scripts/install.sh` (prompted or via `HARNESS_*` env vars), or left empty for
`env_key`-only operation.

## Quickstart (fresh host)

```bash
grok plugin marketplace add karlorz/agent-skills
grok plugin install grok-build-harness --trust
# start a new session, then:
/grok-build-init
```

The skill runs `scripts/install.sh`, which:

1. Backs up existing `~/.grok` files to
   `~/.grok/backups/grok-build-harness-<timestamp>/`
2. Installs the agents, `agentrules.md`, `AGENTS.md` (preserving any skillwiki
   marker block), and a rendered `config.toml`
3. Adds the companion marketplaces (karlorz-agent-skills, llm-wiki,
   openai-codex, claude-plugins-official) and installs the 13-plugin set with
   `--trust`
4. Verifies with `grok plugin list --json` and `grok inspect --json`

### Flags

```text
--grok-home DIR        target grok home (default: $GROK_HOME or ~/.grok)
--hub-key / --new-key / --context7-key   API keys (or HARNESS_* env vars)
--skip-codex | --skip-vault-sync | --skip-playwright-cli   optional plugins
--skip-plugins         files + config only
--no-config            skip config.toml
--dry-run              preview without writing
--force / -y           overwrite without prompting
--verify               run verification after install
```

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
