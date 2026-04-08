# Obsidian GH Knowledge (Deep)

This folder is the source for the `obsidian-gh-knowledge` skill.

## Operating Rules

- Prefer local vault operations when a local vault exists (path from `~/.config/obsidian-gh-knowledge/config.json` `local_vault_path`, else `~/Documents/obsidian_vault/`), unless config `prefer_local` is `false`.
- If no local vault exists yet and the user confirms a vault repo URL, bootstrap local mode first with `scripts/init_local_vault.py`; prefer cloning into `~/Documents/<repo-name>` for the current user and update `~/.config/obsidian-gh-knowledge/config.json` `local_vault_path` before using GitHub-only mode.
- Bootstrap must configure local Git readiness even when Obsidian CLI is unavailable: worktree-local `push.recurseSubmodules`, configured `raw/` submodule init, and raw branch/upstream attachment when safe.
- Bootstrap should clear stale `core.hooksPath` config so new and existing workspaces converge on the same hook-free baseline.
- When configured, `raw/` is a Git submodule for source materials and should be treated as source input, not curated notes.
- Treat `raw/inbox` as the default landing zone for new external source material.
- Treat `0️⃣-Inbox` as curated staging only. Do not use it as a raw-source dump bucket.
- Do not guess the user's vault repo.
- Ask for explicit confirmation before cloning a vault repo or repointing `local_vault_path`.
- Resolve the target repo in this order:
  1. `--repo <owner/repo>` if provided
  2. `--repo <key>` resolved from `~/.config/obsidian-gh-knowledge/config.json` (`repos.<key>`)
  3. `default_repo` from the same config file
  4. If none: print a clear setup error and stop
- Use GitHub via `gh` only when local vault access is unavailable or explicitly disabled.

## Entrypoint

- Bootstrap script: `scripts/init_local_vault.py`
- Local CLI wrapper: `scripts/local_obsidian_knowledge.py`
- GitHub mode script: `scripts/github_knowledge_skill.py`
- Commands: `doctor`, `dashboard`, `review`, `simplify-review`, `audit`, `fix-tldr`, `structure-report`, `structure-fix`, `archive-fix`, `capture`, `capture-raw`, `project-note`, `organize`, `sync`, plus GitHub-mode `list`, `read`, `search`, `move`, `copy`, `write`
- Default health command: `simplify-review` for readability/tracking resilience. `dashboard` and `review` expose Obsidian full-vault counts; `structure-report` and the readability checks focus on active-scope cleanup.

## Files

- `scripts/init_local_vault.py`: Clone a confirmed vault repo into `~/Documents/<repo-name>`, optionally initialize `raw/` as a submodule, and wire local config plus Git bootstrap for first-run setup.
- `scripts/local_obsidian_knowledge.py`: Repo-specific local macOS wrapper around the official Obsidian CLI for health checks, one-click vault review, explicit raw-vs-curated intake metrics, combined simplify/dedupe/readability review reports, stricter vault audits, bulk TL;DR normalization, local structure cleanup reporting/fixes, archive index cleanup, note capture, raw-material capture, project-scoped note creation, note organization, and git sync. `doctor` must still report Git/bootstrap readiness when the Obsidian CLI is missing.
- `scripts/github_knowledge_skill.py`: GitHub-backed single-file operations.
- `references/obsidian-organizer.md`: Organizing workflow reference.

## Related

- [[vault-operations-index|Vault Operations Index]]
