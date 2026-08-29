# Changelog

All notable changes to this skill are documented in this file.

## [0.3.2] - 2026-08-29

- Shorten SKILL.md descriptions to the Codex catalog budget (180-character target, CI fail above 220).

## [0.3.1] - 2026-08-10

- Fresh-host bootstrap for the karlorz subagent harness — installs the custom grok-build-byok parent agent and scout subagent, agentrules.md routing rules, the spliced subagent-contract AGENTS.md (user content preserved), and a sanitized BYOK config template that preserves host-set keys, then adds the companion marketplaces and installs the plugin set with --trust. Idempotent, backup-first, GROK_HOME-aware; keyed configs are never silently downgraded on keyless re-runs.
