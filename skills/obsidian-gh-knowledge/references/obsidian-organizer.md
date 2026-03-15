---
description: Organize Obsidian notes by moving them to project folders, renaming to kebab-case, and updating links (remote GitHub repo via bundled CLI).
---

# Obsidian Organizer Workflow

This workflow helps you maintain a clean and organized Obsidian vault by processing notes in `0️⃣-Inbox` and `2️⃣-Drafts`.

## Preferred Local macOS Flow

When the vault is local and the official Obsidian CLI is available, prefer the repo-specific wrapper instead of raw filesystem moves:

```bash
python3 agent-skills/skills/obsidian-gh-knowledge/scripts/local_obsidian_knowledge.py dashboard
python3 agent-skills/skills/obsidian-gh-knowledge/scripts/local_obsidian_knowledge.py organize "0️⃣-Inbox/my-note.md" cmux
python3 agent-skills/skills/obsidian-gh-knowledge/scripts/local_obsidian_knowledge.py sync --message "Organize local notes"
```

This keeps the workflow inside Obsidian so file moves and renames are driven by the app, not by ad hoc shell commands.

## Steps

1. **Check Inbox and Drafts**
   - List files in `0️⃣-Inbox` and `2️⃣-Drafts`.
   - Identify files that belong to existing projects (e.g., `cmux`, `data-labeling`, `k8s`, `pve`).

   ```bash
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> list --path "0️⃣-Inbox"
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> list --path "2️⃣-Drafts"
   ```

2. **Move Files**
   - Move identified files to their respective project folders in `5️⃣-Projects/GitHub/`.
   - **Rule**: If a file is generic (e.g., `notes.md`), ask the user for a better name or context before moving.

   ```bash
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> move "0️⃣-Inbox/my-note.md" "5️⃣-Projects/GitHub/cmux/my-note.md" --branch "organize-notes" --message "Organize notes"
   ```

3. **Rename to Kebab-Case**
   - Rename files to `lowercase-kebab-case` for consistency.
   - **Example**: `My Note.md` -> `my-note.md`.
   - **Example**: `AWS Setup.md` -> `aws-setup-guide.md` (add semantic context if needed).

   ```bash
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> move "5️⃣-Projects/GitHub/cmux/My Note.md" "5️⃣-Projects/GitHub/cmux/my-note.md" --branch "organize-notes" --message "Rename note"
   ```

4. **Update Internal Links**
   - When a note is renamed, find all references to it in specific `_Overview.md` files or other notes.
   - Update the `[[WikiLinks]]` to match the new filename.

   ```bash
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> search "[[My Note]]"
   ```

5. **Verify Structure**
   - Ensure `2️⃣-Drafts` does not contain project-specific notes.
   - Ensure `_Overview.md` files have valid links.

## Remote GitHub Fallback

If local Obsidian CLI access is unavailable, fall back to the GitHub workflow below.
