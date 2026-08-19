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
- `WARN`: Actionable drift or stale cache snapshot (e.g., Cursor marketplace pack version older than Claude plugin cache).
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
- When a stale Cursor pack is detected, the remediation path is the Team Marketplace Dashboard (`Dashboard → Plugins → karlorz/llm-wiki → Refresh` or `Enable Auto Refresh`), not local file manipulation or reinstalling.
