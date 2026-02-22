# Obsidian GH Knowledge (Deep)

This folder is the source for the `obsidian-gh-knowledge` skill.

## Operating Rules

- Prefer local vault operations when a local vault exists (path from `~/.config/obsidian-gh-knowledge/config.json` `local_vault_path`, else `~/Documents/obsidian_vault/`), unless config `prefer_local` is `false`.
- Do not guess the user's vault repo.
- Resolve the target repo in this order:
  1. `--repo <owner/repo>` if provided
  2. `--repo <key>` resolved from `~/.config/obsidian-gh-knowledge/config.json` (`repos.<key>`)
  3. `default_repo` from the same config file
  4. If none: print a clear setup error and stop
- Use GitHub via `gh` only when local vault access is unavailable or explicitly disabled.

## Entrypoint

- GitHub mode script: `scripts/github_knowledge_skill.py`
- Commands: `list`, `read`, `search`, `move`, `copy`, `write`

## Files

- `scripts/github_knowledge_skill.py`: GitHub-backed single-file operations.
- `references/obsidian-organizer.md`: Organizing workflow reference.
