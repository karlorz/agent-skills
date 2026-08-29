# Changelog

All notable changes to this skill are documented in this file.

## [0.5.0] - 2026-08-29

- Add `check-config.py` and integrate live `config.toml` schema checking into `--verify` across 3 layers (template-owned, docs-known, runtime extras).
- Support `$GROK_HOME/docs/user-guide/26-config-reference.md` live parsing with vendored fallback `assets/config-reference-keys.json`.
- Add runtime extras catalog (`assets/config-runtime-extras.json`) and validate `[consent.answers.aup]` / `[consent.answers.tos]` structure without logging or leaking PII.
- Add `--strict` flag to `check-config.py` and `install.sh` to fail on unexpected top-level config tables.
- Add assertion in `--verify` ensuring discovered user agent `grok-build-byok` is present when plugins are not skipped.

## [0.4.1] - 2026-08-29

- Synchronize release metadata and marketplace catalog versions following the malformed 0.4.0 release.

## [0.4.0] - 2026-08-29

- Add `[subagents.toggle] grok-build-byok = false` to config template (parent-only agent toggle).
- Add harness stamp file (`.grok-build-harness-stamp.json`) recording schema, version, root, install time, and grokgod detection.
- Add `--with-grokgod` and `--skip-grokgod` flags; auto-detect grokgod and idempotently merge `[plan_mode] implement_via_subagents = true` into config.toml (not part of the stock template).
- Support plugin refresh before install when running from `installed-plugins`, re-executing updated installer.
- Update `--verify` to inspect the stamp, warn when `[agent] name = grok-build-byok` is paired with non-comment `agent_type = "codex"`, and require `implement_via_subagents` when grokgod is detected.

## [0.3.2] - 2026-08-29

- Shorten SKILL.md descriptions to the Codex catalog budget (180-character target, CI fail above 220).

## [0.3.1] - 2026-08-10

- Fresh-host bootstrap for the karlorz subagent harness — installs the custom grok-build-byok parent agent and scout subagent, agentrules.md routing rules, the spliced subagent-contract AGENTS.md (user content preserved), and a sanitized BYOK config template that preserves host-set keys, then adds the companion marketplaces and installs the plugin set with --trust. Idempotent, backup-first, GROK_HOME-aware; keyed configs are never silently downgraded on keyless re-runs.
