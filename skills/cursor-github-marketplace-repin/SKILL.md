---
name: cursor-github-marketplace-repin
description: Re-pin Cursor user GitHub marketplaces llm-wiki and karlorz-agent-skills, then reinstall KEEP plugins. Use when gitRef pins lag.
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
- Cursor CLI `plugin install` is missing on `2026.08.25`; do not treat that as
  a completed KEEP reinstall.

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

## KEEP plugins (reinstall after re-pin)

`marketplace remove` uninstalls every plugin from that marketplace on the
shared Cursor account list. Grok Bot uses the same list, so SkillWiki and
vault-sync disappear from Grok Bot until they are installed again. `add`
brings the marketplace back but does **not** reinstall the plugins.

Cursor CLI **does not auto-update** marketplace plugins. On CLI `2026.08.25`
and current `plugin --help`, the only subcommand is `marketplace`. There is
**no** `plugin install`. `plugin install name@marketplace` fails with
`too many arguments for 'plugin'`. Interactive equivalent: `/plugins`.

After each successful remove+add (or add-only when status is `MISSING`),
reinstall that marketplace's KEEP plugins. Idempotent. Do not `plugin
uninstall` KEEP plugins as their own step.

| Marketplace | KEEP plugins |
| --- | --- |
| `llm-wiki` | `skillwiki`, `vault-sync` |
| `karlorz-agent-skills` | `grok-search`, `deep-research`, `cursor-box-channel` |

```bash
# try CLI install first (may exist on a future CLI)
"$AGENT" plugin install skillwiki@llm-wiki
"$AGENT" plugin install vault-sync@llm-wiki
"$AGENT" plugin install grok-search@karlorz-agent-skills
"$AGENT" plugin install deep-research@karlorz-agent-skills
"$AGENT" plugin install cursor-box-channel@karlorz-agent-skills

# if that fails (no install subcommand), use the Dashboard fallback:
bash skills/cursor-github-marketplace-repin/scripts/install-keep-plugins.sh
# or after republish:
bash ~/.cursor/skills/cursor-github-marketplace-repin/scripts/install-keep-plugins.sh
```

`install-keep-plugins.sh` calls Dashboard `InstallUserPlugin` (same API as
`/plugins`). Auth is `CURSOR_AUTH_TOKEN` or macOS keychain
`cursor-access-token` / `cursor-user`. It never prints the token. Override
base URL with `CURSOR_DASHBOARD_BASE` only in tests.

`deep-research` and `cursor-box-channel` must be in the Cursor catalog
(`.cursor-plugin/marketplace.json` on karlorz/agent-skills), not only the
Claude catalog. If the helper cannot find `deep-research` or
`cursor-box-channel` in `ListMarketplacePlugins` for
`karlorz-agent-skills`, the Cursor marketplace pin is still the old catalog
that listed only `grok-search` — finish the karlorz-agent-skills re-pin
first, then install.

`grok-search` may ask for `GROK_SEARCH_MCP_TOKEN` and
`cursor-box-channel` may ask for `CURSOR_BOX_MCP_TOKEN` (Cursor Plugins →
Configure). Do not invent a token. If a token is already configured, leave it.

Grok Bot **public** catalog ids (`skillwiki` `57442251`, `vault-sync`
`57442252`, `grok-search` `57442314`) are **not** the user GitHub marketplace
plugin ids. Rempin mints new ids. Do not `InstallUserPlugin` those public ids
for these two groups. The helper looks up ids from `ListMarketplacePlugins`
for the user marketplace. `deep-research` has a user-marketplace id after
the karlorz-agent-skills pin includes it in the Cursor catalog.

## Verify

Re-run `status.sh` until both groups print `PIN MATCHES`. Then confirm the
KEEP plugins above are installed again (`skillwiki`, `vault-sync`,
`grok-search`, `deep-research`, `cursor-box-channel`).

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
