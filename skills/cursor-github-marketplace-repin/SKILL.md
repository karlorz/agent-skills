---
name: cursor-github-marketplace-repin
description: >-
  Re-pin the two Cursor user GitHub plugin marketplaces llm-wiki
  (karlorz/llm-wiki) and karlorz-agent-skills (karlorz/agent-skills) with
  `plugin marketplace remove` then `add --git-ref`. This skill should be used
  when those two catalog gitRef pins lag GitHub, Cursor SkillWiki or
  karlorz-agent-skills packs look stale, `plugin marketplace update` kept the
  same SHA, or Team Dashboard Refresh/Auto Refresh was suggested for them
  (Refresh does not apply when scope=user). Run status.sh first; execute
  remove+add only if the user asked to update or re-pin these two repos. Do
  not use for Cursor public marketplace, Team admin rows, Claude/Codex/Grok
  plugin updates, `npx skills`, or other user GitHub adds (obsidian-skills,
  newapi-skills, openai-codex).
---

# cursor-github-marketplace-repin

Move **user GitHub marketplace pins** for the two plugin groups the operator
robots share. This is not Team Dashboard Refresh and not `marketplace update`.

## The two groups

| Group | Git URL | Default `--git-ref` |
| --- | --- | --- |
| `llm-wiki` | `https://github.com/karlorz/llm-wiki` | latest `v*` release tag from `status.sh` |
| `karlorz-agent-skills` | `https://github.com/karlorz/agent-skills` | default-branch HEAD SHA from `status.sh` |

`cursor-agent plugin marketplace list --format json` must show `"scope": "user"`
for both. That is a **user GitHub add** pin. There is no Refresh / Auto Refresh
button on this channel.

Team Dashboard (`Dashboard → Plugins → Refresh`) is only for a real Team
marketplace admin row. Public Cursor Marketplace is a third channel and does
not list these repos.

## What does not work

- `plugin marketplace update <name>` re-indexes the **same** SHA.
- `add` without `remove` clones locally, then the old pin can restore.
- Reinstall / UI uninstall without `remove` + `add --git-ref` repeats the pin.
- Copying files under `~/.cursor/plugins/cache/` while the catalog `gitRef` is
  still old. Cursor will restore the pinned snapshot.

## Status first

From this repository:
```bash
bash skills/cursor-github-marketplace-repin/scripts/status.sh
```

Or from the operator's installed skills directory (after republishing):
```bash
bash ~/.cursor/skills/cursor-github-marketplace-repin/scripts/status.sh
```

Read the printed `status:` lines. Do not re-pin from memory or from example
SHAs in this file.

Only continue to remove+add when the user asked to **update** or **re-pin**
these two repos. If they only asked why the pack is stale, report status and
stop.

## Re-pin (attended)

Resolve `AGENT` once (`cursor-agent` or `agent`, same as `status.sh`). Do
**remove then add**. Do not `update`. Do not remove any marketplace except
`llm-wiki` and `karlorz-agent-skills`.

- If status says `MISSING`, skip `remove` and only `add --git-ref`.
- If status says `PIN MATCHES`, stop.
- If `scope` is not `user`, stop (this skill does not apply).

**llm-wiki** — use the tag name from status
(`STALE — remove then add --git-ref v…`), not a floating `main` SHA:

```bash
"$AGENT" plugin marketplace remove llm-wiki
"$AGENT" plugin marketplace add https://github.com/karlorz/llm-wiki --git-ref <tag-from-status.sh>
```

**karlorz-agent-skills** — use the HEAD SHA from status:

```bash
"$AGENT" plugin marketplace remove karlorz-agent-skills
"$AGENT" plugin marketplace add https://github.com/karlorz/agent-skills --git-ref <head-sha-from-status.sh>
```

## Verify

Re-run `status.sh` until both groups print `PIN MATCHES`.

`gitRef` is a 40-character SHA, not the tag string. For llm-wiki annotated
tags it must equal status.sh `tag=` (tag object). The peeled `commit=` may
differ; that is expected. For karlorz-agent-skills it must equal the HEAD SHA
you passed.

Leftover cache dirs under the **old** SHA may remain (for example
`~/.cursor/plugins/cache/llm-wiki/skillwiki/<old-sha>/`). That is expected.
Do not delete them unless the user asks.

This session keeps injected skill paths from start. Tell the user to open a
**new Agent chat** after a successful re-pin.

## Other channels (out of scope — do not mix)

Leave other Cursor `scope=user` GitHub adds unchanged (on this host that
includes openai-codex, newapi-skills, obsidian-skills).

- Claude Code plugins Cursor also loads from `~/.claude/plugins/cache/`:
  `claude plugin marketplace update` then `claude plugin update <name>@<marketplace>`.
- Codex: `codex plugin marketplace upgrade <name>`.
- Grok CLI: `grok plugin marketplace update <name>` then `grok plugin update <plugin>`.
- Cursor-linked `npx skills` packages: `npx skills update <name> -g -y`.
