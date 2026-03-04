---
name: obsidian-gh-knowledge
description: Operate an Obsidian vault with official Obsidian CLI first (local), with local filesystem/git fallback, and GitHub API fallback when local access is unavailable. Use for listing, reading, searching, creating/updating, and moving notes in Obsidian vaults.
---

# Obsidian GH Knowledge (CLI-first)

Use this skill to manage an Obsidian vault safely and consistently.

## Source of truth

- Official CLI docs: `https://help.obsidian.md/cli`
- Public release note introducing CLI: `https://obsidian.md/changelog/2026-02-27-desktop-v1.12.4/`

Note: CLI docs may still show early-access wording in some sections. Treat the public changelog (February 27, 2026) as the release marker.

## Execution modes (strict order)

1. **Local Obsidian CLI mode (preferred)**
   - Use when local vault exists and `obsidian` CLI is available and enabled.
2. **Local filesystem/git fallback**
   - Use when local vault exists but CLI is not enabled.
3. **GitHub mode fallback**
   - Use when local vault is unavailable or explicitly disabled.

This ordering is for compatibility across desktop, server, and sandbox environments.

## Mode selection (local vs GitHub)

1. Resolve `VAULT_DIR`:
   - If `~/.config/obsidian-gh-knowledge/config.json` has `local_vault_path`, use it.
   - Else use `~/Documents/obsidian_vault/`.
2. If `VAULT_DIR` exists and `prefer_local` is not `false`, use local mode.
3. In local mode, prefer official Obsidian CLI only if:
   - `command -v obsidian` succeeds, and
   - `obsidian help` succeeds (CLI is enabled and app connection works).
4. If CLI checks fail, fall back to local filesystem/git mode.
5. If local mode is unavailable, use GitHub mode.

Quick checks:

```bash
# Local vault path
python3 - <<'PY'
import json, os
p = os.path.expanduser('~/.config/obsidian-gh-knowledge/config.json')
if os.path.exists(p):
    c = json.load(open(p))
    print(os.path.expanduser(c.get('local_vault_path', '~/Documents/obsidian_vault')))
else:
    print(os.path.expanduser('~/Documents/obsidian_vault'))
PY

# CLI availability
command -v obsidian
obsidian help
```

If `obsidian help` prints `Command line interface is not enabled`, use local filesystem fallback until enabled in Obsidian settings.

## Environment compatibility

- macOS/Windows desktop with Obsidian app running: use local Obsidian CLI mode.
- Linux desktop with Obsidian GUI available: CLI may work, use same checks above.
- Headless Linux/container/sandbox (no GUI app session): assume Obsidian CLI is unavailable and skip directly to local filesystem or GitHub mode.
- In many sandboxes, `~/.config/obsidian-gh-knowledge/config.json` and `~/Documents/obsidian_vault` do not exist by default. Expect explicit `--repo` usage.

Do not block execution waiting for CLI in headless environments.

## Local Obsidian CLI mode (preferred)

### Requirements

- Obsidian desktop `1.12.4+`.
- CLI enabled in app settings: `Settings -> General -> Advanced -> Command line interface`.
- On macOS, ensure PATH contains `/Applications/Obsidian.app/Contents/MacOS`.
- If CLI errors show `Unable to find helper app` or `Command line interface is not enabled`, re-enable the CLI toggle in settings and restart the terminal.

### Targeting vaults and files

- If current directory is the vault, commands target that vault.
- Otherwise use `vault=<name>` as the first parameter.
- Use `file=<name>` for wikilink-style resolution, or `path=<exact/path.md>` for precise targeting.

Examples:

```bash
# Prefer running inside vault root
cd "$VAULT_DIR"

# Or target by vault name explicitly
obsidian vault="My Vault" search query="test"

# Exact file targeting
obsidian read path="5️⃣-Projects/GitHub/cmux/_Overview.md"
```

### Core command patterns

```bash
# Search and read
obsidian search query="MOC" path="5️⃣-Projects/" format=json
obsidian read path="5️⃣-Projects/GitHub/cmux/_Overview.md"

# Create/update content
obsidian create name="new-note" path="2️⃣-Drafts" content="# Title\n\n## TL;DR\n"
obsidian write path="2️⃣-Drafts/new-note.md" content="# Title\n\n## TL;DR\n- [ ] Follow up"
obsidian append path="2️⃣-Drafts/new-note.md" content="\n- [ ] Follow up"

# Move/rename and delete
obsidian move path="0️⃣-Inbox/note.md" to="5️⃣-Projects/GitHub/cmux/note.md"
obsidian delete path="2️⃣-Drafts/tmp-note.md"

# Tasks, tags, properties, templates, daily note
obsidian tasks path="5️⃣-Projects/" todo format=json
obsidian tags counts
obsidian properties path="5️⃣-Projects/GitHub/cmux/_Overview.md"
obsidian templates
obsidian template:read name="github-project-template"
obsidian daily
obsidian daily:append content="- [ ] Review inbox"
```

### Local write workflow

1. Read before write (`obsidian read ...`).
2. For large edits, write to a draft note first, then merge intentionally.
3. Commit locally with small, reviewable commits.

```bash
cd "$VAULT_DIR"
git status --porcelain=v1
git checkout -b update-notes-YYYYMMDD
git add "path/to/note.md"
git commit -m "Update note"
```

## Local filesystem/git fallback (CLI unavailable)

Use only when local CLI cannot be used.

```bash
VAULT_DIR="$HOME/Documents/obsidian_vault"

ls -la "$VAULT_DIR"
rg -n "keyword" "$VAULT_DIR"
sed -n '1,160p' "$VAULT_DIR/5️⃣-Projects/GitHub/cmux/_Overview.md"
```

For edits, keep the same small-commit discipline as local CLI mode.

## GitHub mode fallback

Use when local vault is unavailable or `prefer_local` is explicitly `false`.

### Repo resolution policy

Resolve repo in this order:

1. `--repo <owner/repo>` if provided.
2. `--repo <key>` (no `/`) resolved from `repos.<key>` in config.
3. `default_repo` from config.
4. If none are available, stop and ask for repo/config.

Never guess repo names.

### Requirements

- GitHub CLI installed: `gh`
- Authenticated: `gh auth status`
- Repo access check before reads/writes:
  - `gh repo view <owner/repo> >/dev/null`
  - If this fails, stop and request a repo the current account/team can access.

### Commands

Resolve script path in this order (sandbox-safe):

```bash
if [ -f "skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py" ]; then
  SCRIPT_PATH="skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py"
elif [ -f "agent-skills/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py" ]; then
  SCRIPT_PATH="agent-skills/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py"
elif [ -f "scripts/github_knowledge_skill.py" ]; then
  SCRIPT_PATH="scripts/github_knowledge_skill.py"
else
  SCRIPT_PATH="$HOME/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py"
fi
```

```bash
python3 "$SCRIPT_PATH" \
  --repo <owner/repo> <command> [args]
```

Available commands:

- `list --path <path>`
- `read <file_path>`
- `search <query>`
- `move <src> <dest> --branch <branch_name> --message <commit_msg>`
- `copy <src> <dest> --branch <branch_name> --message <commit_msg>`
- `write <file_path> --stdin|--from-file <path> --branch <branch_name> --message <commit_msg>`

### Headless Linux smoke checks

Run these before substantial work in sandboxes:

```bash
command -v obsidian || true
gh auth status
python3 "$SCRIPT_PATH" --repo <owner/repo> list --path ""
python3 "$SCRIPT_PATH" --repo <owner/repo> read "README.md"
python3 "$SCRIPT_PATH" --repo <owner/repo> search "filename:_Overview.md"
```

Expected behavior from recent validation:

- `obsidian` is often unavailable in headless Linux.
- GitHub mode works when `--repo` is explicit and `gh` has access.
- Emoji paths are supported when quoted:
  - `python3 "$SCRIPT_PATH" --repo <owner/repo> list --path "0️⃣-Inbox"`

## Safety rules (critical)

1. Never force-push to `main`.
2. In GitHub mode, always write on a feature branch.
3. In GitHub mode, always open a PR for review before merge.
4. Read before write.
5. Keep commits small and scoped.
6. Prefer local vault operations whenever available.

## Practical tips (paths and emoji)

- Always quote paths (`"..."`), especially emoji folders.
- Prefer copying exact paths from command output instead of retyping.
- For 404/path errors in GitHub mode, verify with `list` first.
- If `list` on repo root also fails, treat it as repo permission or wrong account/team context, not just path typo.

## Obsidian note authoring rules

If repository-level `AGENTS.md` exists, follow it first.

### Markdown

- Prefer a short `## TL;DR` near the top.
- Use Obsidian wikilinks (`[[note-title]]`) for internal notes.
- Keep headings stable unless rename/move is requested.
- Use YAML frontmatter for metadata when needed.

### Mermaid (Obsidian compatibility)

- Prefer `graph TB` / `sequenceDiagram`.
- Use `subgraph "Title"` (avoid `subgraph ID[Label]`).
- Avoid `\n` in labels; use `<br/>` or single-line labels.
- Keep node IDs ASCII and simple (`CMUX_DB`, `OC_GW`).

### Project folder convention

Each project folder under `5️⃣-Projects/` must include `_Overview.md` as MOC.

When creating a project folder:

1. Create folder in the right category (`GitHub`, `Infrastructure`, `Research`).
2. Create `_Overview.md` first.
3. Include quick navigation and documentation index.
4. Link related notes from `_Overview.md`.

## Templates

For GitHub project notes, use `100-Templates/github-project-template.md`.

GitHub mode example:

```bash
python3 ~/.agents/skills/obsidian-gh-knowledge/scripts/github_knowledge_skill.py \
  --repo <owner/repo> read "100-Templates/github-project-template.md"
```

## Config file

Create `~/.config/obsidian-gh-knowledge/config.json`:

```json
{
  "default_repo": "<owner>/<vault-repo>",
  "repos": {
    "personal": "<owner>/<vault-repo>",
    "work": "<org>/<work-vault-repo>"
  },
  "local_vault_path": "~/Documents/obsidian_vault",
  "prefer_local": true,
  "vault_name": "My Vault"
}
```

`vault_name` is optional; use it when running CLI commands outside the vault directory.

## Workflow reference

See `references/obsidian-organizer.md` for concrete note-organization workflow patterns.
