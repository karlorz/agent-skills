---
name: obsidian-gh-knowledge
description: Organize and maintain an Obsidian vault stored in a GitHub repo using a bundled gh-based CLI. Use for listing remote folders, reading notes, searching references, and moving/renaming notes via branch commits (create+delete).
---

# Obsidian GitHub Knowledge

Use this skill to operate on a remote Obsidian vault stored in a GitHub repository without relying on local filesystem edits.

This skill should NOT guess which repo is your vault.

If the user does not provide `--repo`, require the user to either:

- Provide `--repo <owner/repo>` explicitly, or
- Set up the local config file described below, then use its `default_repo`.

## Requirements

- GitHub CLI installed: `gh`
- Authenticated: `gh auth status`

## Commands

All operations are performed via the bundled script:

```bash
python3 scripts/github_knowledge_skill.py --repo <owner/repo> <command> [args]
```

If the skill is installed globally, the script is typically located at:

```bash
python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo <owner/repo> <command> [args]
```

- `list --path <path>`: List files in a directory.
- `read <file_path>`: Read file content.
- `search <query>`: Search code/content.
- `move <src> <dest> --branch <branch_name> --message <commit_msg>`: Move/rename a file by creating the destination file and deleting the source file on a branch.

## Repo Selection (Local Config)

To avoid hard-coding a personal repo in prompts, store your vault repo(s) locally and have the agent/tooling read it.

First-time setup: create `~/.config/obsidian-gh-knowledge/config.json`:

```json
{
  "default_repo": "<owner>/<vault-repo>",
  "repos": {
    "personal": "<owner>/<vault-repo>",
    "work": "<org>/<work-vault-repo>"
  }
}
```

Usage (resolve repo at runtime):

```bash
REPO="$(python3 -c 'import json,os; p=os.path.expanduser("~/.config/obsidian-gh-knowledge/config.json"); print(json.load(open(p))["default_repo"])')"
python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" list --path "0-Inbox"
```

If the user specifies a repo key (e.g., `work`), resolve it from `repos.<key>` instead of `default_repo`.

## Workflow Reference

See `references/obsidian-organizer.md` for a concrete organizing workflow that uses these commands.

## Notes

- `search` uses GitHub code search and may return empty results for very new repos/commits until indexing finishes.
- Paths must match the repo exactly (including emoji and normalization). Use `list` to discover the exact directory names.
