# Obsidian GH Knowledge (Deep)

This folder is the source for the `obsidian-gh-knowledge` skill.

## Operating Rules

- Do not guess the user's vault repo.
- Resolve the target repo in this order:
  1. `--repo <owner/repo>` if provided
  2. `--repo <key>` resolved from `~/.config/obsidian-gh-knowledge/config.json` (`repos.<key>`)
  3. `default_repo` from the same config file
  4. If none: print a clear setup error and stop
- Never require local filesystem access to the vault content; interact with GitHub via `gh`.

## Entrypoint

- Script: `scripts/github_knowledge_skill.py`
- Commands: `list`, `read`, `search`, `move`

## Files

- `scripts/AGENTS.md`: Implementation notes for config/repo resolution.
- `references/AGENTS.md`: Guidance for using the organizer workflow reference.
