---
description: Organize Obsidian notes by moving them to project folders, renaming to kebab-case, and updating links (remote GitHub repo via bundled CLI).
---

# Obsidian Organizer Workflow

This workflow helps you maintain a clean and organized Obsidian vault by processing notes in `0️⃣-Inbox` and `2️⃣-Drafts`.

## Steps

1. **Check Inbox and Drafts**
   - List files in `0️⃣-Inbox` and `2️⃣-Drafts`.
   - Identify files that belong to existing projects (e.g., `cmux`, `data-labeling`, `k8s`, `pve`).

   ```bash
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> list --path "0️⃣-Inbox"
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> list --path "2️⃣-Drafts"
   ```

2. **Move Files**
   - Move identified files to their respective project folders in `5️⃣-Projects/`.
   - **Rule**: If a file is generic (e.g., `notes.md`), ask the user for a better name or context before moving.

   ```bash
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> move "0️⃣-Inbox/my-note.md" "5️⃣-Projects/cmux/my-note.md" --branch "organize-notes" --message "Organize notes"
   ```

3. **Rename to Kebab-Case**
   - Rename files to `lowercase-kebab-case` for consistency.
   - **Example**: `My Note.md` -> `my-note.md`.
   - **Example**: `AWS Setup.md` -> `aws-setup-guide.md` (add semantic context if needed).

   ```bash
   python3 scripts/github_knowledge_skill.py --repo <owner/repo> move "5️⃣-Projects/cmux/My Note.md" "5️⃣-Projects/cmux/my-note.md" --branch "organize-notes" --message "Rename note"
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
