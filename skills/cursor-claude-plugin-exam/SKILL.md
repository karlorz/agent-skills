---
name: cursor-claude-plugin-exam
description: Read-only audit of Claude-to-Cursor plugin discovery, SkillWiki cache freshness vs Cursor marketplace snapshots, and grok-search MCP configuration. Use only when the user asks to exam, audit, or diagnose Claude-to-Cursor plugin discovery.
disable-model-invocation: true
---

# cursor-claude-plugin-exam

Audit tool for inspecting Claude Code to Cursor plugin discovery, cache alignment, and tool availability without converting plugins or creating symlinks.

## Status Vocabulary

The exam reports status rows using strict five-level vocabulary:

- `PASS`: Requirement or discovery check succeeded.
- `INFO`: Informational finding or optional environment state.
- `OPTIONAL`: Dual-path fallback or non-mandatory configuration. Missing `~/.cursor/plugins` or `~/.cursor/plugins/local` is `OPTIONAL` when Claude cache and `enabledPlugins` are healthy.
- `WARN`: Actionable drift or stale cache snapshot (e.g., Cursor marketplace pack version older than Claude plugin cache, or an enabled plugin whose `plugin.json` `skills` path has no `SKILL.md` one level down so Cursor import skips it).
- `FAIL`: Broken configuration or missing required cache/settings.

*(Note: `GAP` status is not part of the vocabulary.)*

## Usage

Run the read-only audit script:

From this repository:
```bash
bash skills/cursor-claude-plugin-exam/scripts/audit-claude-cursor-plugins.sh
```

Or from the operator's installed skills directory (after republishing):
```bash
bash ~/.cursor/skills/cursor-claude-plugin-exam/scripts/audit-claude-cursor-plugins.sh
```

## Behavior & Remediation Rules

- The script is completely **read-only**; it never executes `mkdir`, `ln`, or writes under `$HOME`.
- It withholds `ln -sfn` commands unless discovery has failed on Claude settings or plugin cache (missing settings, empty `enabledPlugins`, or missing skillwiki cache).
- When a stale Cursor pack is detected, run `cursor-github-marketplace-repin` `status.sh`. If status is `user`-scope `STALE`/`MISSING` for `llm-wiki` / `karlorz-agent-skills`, follow that skill (remove then `add --git-ref`). Team Dashboard Refresh / Auto Refresh is only for a real Team marketplace admin row. Do not write local cache files while the catalog pin is still old.
- When `plugin.skills_unresolved` or `plugin.cache_stale` WARNs, the remediation is **reinstall/update that plugin in Claude Code** so the cache `plugin.json` `skills` field points at a directory whose immediate children contain `SKILL.md` (this repo's contract is `"./skills/"`). Do not convert or symlink into `~/.cursor/plugins/local` for this packaging skip.
