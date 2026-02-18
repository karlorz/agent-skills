---
name: obsidian-gh-knowledge
description: Operate an Obsidian vault stored in GitHub using a bundled gh-based CLI. Use when users ask to list folders, read notes, search content, find project tasks/plans, or move/rename notes in a remote vault.
---

# Obsidian GitHub Knowledge

Use this skill to operate on a remote Obsidian vault stored in a GitHub repository without relying on local filesystem edits.

This skill should NOT guess which repo is your vault.

If the user does not provide `--repo`, require the user to either:

- Provide `--repo <owner/repo>` explicitly, or
- Set up the local config file described below, then use its `default_repo`.

## Repo Resolution Policy

Resolve the repository in this order:

1. If the user provides `--repo <owner/repo>`, use it.
2. If the user provides `--repo <key>` (no `/`), resolve it via `~/.config/obsidian-gh-knowledge/config.json` at `repos.<key>`.
3. If `--repo` is omitted, use `default_repo` from the same config file.
4. If none of the above is available, ask the user for the repo or ask them to set local config.

Never guess repo names.

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

Example (resolve repo key):

```bash
REPO="$(python3 -c 'import json,os; p=os.path.expanduser("~/.config/obsidian-gh-knowledge/config.json"); c=json.load(open(p)); print(c["repos"]["work"])')"
python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" search "dev plan"
```

## Quick Workflow Example

When asked to find and read a note:

1. List to discover exact paths:
   ```bash
   python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" list --path "1️⃣-Index"
   ```

2. Search if the path is unknown:
   ```bash
   python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" search "MOC"
   ```

3. Read the target file:
   ```bash
   python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" read "1️⃣-Index/README.md"
   ```

## Search Query Tips

The `search` command uses GitHub code search. Include qualifiers directly in your query string:

```bash
python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" search "TODO path:1️⃣-Index/"
python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" search "project plan path:5️⃣-Projects/ extension:md"
python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py --repo "$REPO" search "filename:_Overview.md cmux"
```

## Workflow Reference

See `references/obsidian-organizer.md` for a concrete organizing workflow that uses these commands.

## Notes

- `search` uses GitHub code search; results may be empty for new commits until GitHub indexes them (typically seconds to minutes).
- Qualifiers like `path:`, `extension:`, `filename:` can narrow results - include them directly in the query string.
- Paths must match the repo exactly (including emoji and normalization). Use `list` to discover the exact directory names.
