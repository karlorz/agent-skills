---
name: obsidian-gh-knowledge
description: Organize and maintain an Obsidian vault stored in a GitHub repo using a bundled gh-based CLI. Use for listing remote folders, reading notes, searching references, and moving/renaming notes via branch commits (create+delete).
---

# Obsidian GitHub Knowledge

Use this skill to operate on a remote Obsidian vault stored in a GitHub repository without relying on local filesystem edits.

## Requirements

- GitHub CLI installed: `gh`
- Authenticated: `gh auth status`

## Commands

All operations are performed via the bundled script:

```bash
python3 scripts/github_knowledge_skill.py --repo <owner/repo> <command> [args]
```

- `list --path <path>`: List files in a directory.
- `read <file_path>`: Read file content.
- `search <query>`: Search code/content.
- `move <src> <dest> --branch <branch_name> --message <commit_msg>`: Move/rename a file by creating the destination file and deleting the source file on a branch.

## Workflow Reference

See `references/obsidian-organizer.md` for a concrete organizing workflow that uses these commands.

## Notes

- `search` uses GitHub code search and may return empty results for very new repos/commits until indexing finishes.
- Paths must match the repo exactly (including emoji and normalization). Use `list` to discover the exact directory names.
