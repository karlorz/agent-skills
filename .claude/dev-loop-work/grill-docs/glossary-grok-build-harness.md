# Glossary: grok-build-harness fixes

| Term | Definition | Source ADR |
|------|------------|------------|
| grok-build-harness | The marketplace plugin that bootstraps a fresh grok-build host with the karlorz subagent harness (agents, rules, config, plugin set). | ADR-1 |
| GROK_HOME | Environment variable relocating the entire grok-build config tree; used for scratch bootstrap testing. | ADR-2 |
| env-only config | Rendered config with no inline api_key fields; models fall back to env_key variables (HUB_API_KEY etc.). | ADR-3 |
| --require-keys | Installer flag hard-failing when hub/new gateway keys are missing; context7 key stays optional. | ADR-3 |
| --restrictive | Installer flag rendering permission_mode = "plan" instead of "always-approve". | ADR-8 |
| pin aliases | The sonnet / haiku / deepseek-v4-flash model aliases that [subagents.models] pins resolve to. | ADR-4 |
| release marker | ~~The `vX.Y.Z:` prefix in plugin descriptions that must match the manifest version.~~ Deprecated in v1.26.30: version markers migrated to `CHANGELOG.md`; descriptions are now stable prose. | ADR-5 |
| scratch bootstrap | A full install.sh run against a disposable GROK_HOME, exercising every write path safely. | ADR-9 |
| marketplace provenance | The originating marketplace for each installed plugin, recorded in installed-plugins/registry.json. | ADR-6 |
| unknown-field warning | grok inspect warning for config keys the schema doesn't know; harmless but noisy. | ADR-6 |
| web_search pin | `[models] web_search = "no-such-model"` — intentional disable of the web-search model. | ADR-7 |
| harness marker block | `<!-- grok-build-harness:begin/end -->` — the harness-owned splice region in AGENTS.md that the merge replaces; everything outside it is preserved. | ADR-1 (rerun) |
| marker-splice merge | The AGENTS.md merge strategy: keep all existing content verbatim, replace only the harness marker block (or insert it when absent). | ADR-1 (rerun) |
| block-match migration | One-time conversion of the unmarked v0.2.0 `## Subagent contract` block to the marked form by matching its known heading + final line. | ADR-2 (rerun) |
| preservation whitelist | The rule that any config key the template does not emit survives re-renders (e.g. [plugins].disabled, paths). | ADR-3 (rerun) |
| keyed config | A config.toml with injected `api_key` lines in [model.*] or an `--api-key` arg in mcp_servers. | ADR-4 (rerun) |
| env-only downgrade | Rewriting a keyed config to env-only by re-running without keys. | ADR-4 (rerun) |
| --force-render | Override flag that lets a keyless run rewrite a keyed config to env-only despite the downgrade guard. | ADR-4 (rerun) |
