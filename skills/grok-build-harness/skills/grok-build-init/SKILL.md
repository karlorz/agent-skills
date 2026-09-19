---
name: grok-build-init
description: Bootstrap or refresh the karlorz grok-build harness (AGENTS.md splice, agents, plugins). On /grok-build-init, Ask User Question first; timeout selects Recommended.
---

# grok-build-init

One file owns the session contract: `$GROK_HOME/AGENTS.md` (default `~/.grok/AGENTS.md`). This skill splices the harness marker block, copies agents + `agentrules.md`, and on a fresh host also renders config and installs companion plugins.

## First action

Do **not** write a long chat essay and wait. Call **Ask User Question** immediately:

- **Refresh AGENTS.md** (Recommended) — harness group update or a new scenario on an existing host. Detect drift, splice the contract, leave user sections alone.
- **Full host init** — new machine. Keys, config, plugins.
- **Status only** — no writes. Run `--status` and quote the **full inventory** in this chat (not a 4-row summary, not a collapsed tool card).

Timeout selects Recommended. Treat that as the go-ahead.

## Locate installer

```bash
grok plugin update grok-build-harness
INSTALL="$(find ~/.grok/installed-plugins -maxdepth 3 -type f -name install.sh -path '*grok-build-harness*' | head -1)"
```

From a checkout: `skills/grok-build-harness/scripts/install.sh`.

Need `python3`. Full init also needs `git` and a runnable `grok --version`. Remote SSH: run `install.sh` directly; never `ssh -t grok whoami`.

## Refresh (Recommended)

```bash
bash "$INSTALL" --docs-status
bash "$INSTALL" --docs-only -y
bash "$INSTALL" --docs-status
```

`--docs-status` prints one word: `missing` | `match` | `drift` | `unmarked` | `absent`. After `--docs-only`, status should be `match`. User content outside `<!-- grok-build-harness:begin/end -->` is preserved. Then Ask User Question once more if another scenario remains.

## Status only

```bash
bash "$INSTALL" --status
```

No bash (Windows): `python3 "$PLUGIN/scripts/status.py" --grok-home "$GROK_HOME" --plugin-root "$PLUGIN"`.

`--docs-status` stays one word for scripts. `--status` is the session inventory: contract word + meaning, plugin vs stamp, required files, `[agent]` name, `plan_mode`, Keep working line, each harness companion (`enabled` / `not-enabled` / `extra`, `present` / `missing`), and `english_rule:` lines for Grok / Claude / Codex / Cursor (`missing` / `match` / `drift` vs `assets/reply-in-english.md`). Quote that block in chat. Do not skip it and jump to "no problem" / the next scenario. Then Ask User Question if another scenario remains.

## Full init

```bash
bash "$INSTALL" --hub-key "$HUB_KEY" --new-key "$NEW_KEY" --context7-key "$CTX7_KEY" --verify -y
```

Keys may also come from `HARNESS_HUB_KEY` / `HARNESS_NEW_KEY` / `HARNESS_CONTEXT7_KEY`. Missing keys → env-only config (warns). `--require-keys` hard-fails. Extra flags: `install.sh --help`.

Finish: start a new session so `AGENTS.md` loads. Skillwiki's `~/.grok/skillwiki.md` marker is preserved; do not overwrite it.

## Contract file

| Path | Role |
|---|---|
| `AGENTS.md` | **The** session contract. Harness block is spliced; everything else is yours. Re-run this skill when the group updates or the scenario changes. |
| `agentrules.md` | Full routing rules (pointed at from the contract). |
| `agents/grok-build-byok.md`, `agents/scout.md` | Parent agent + scout. |

Keep-working rule lives in the harness block: Ask User Question + timeout = Recommended. Do not add a second extras file.

English-thinking rule SSOT is `assets/reply-in-english.md`. `--docs-only` copies/splices each host-native load path under `--user-home` (default: parent of `--grok-home`): Grok `rules/` + `AGENTS.md` bullet, Claude `rules/` + `CLAUDE.md`, Codex `AGENTS.md` bullet, Cursor `rules/reply-in-english.mdc`. Status reports those six paths. Do not recreate vault `.cursor/rules` / `.claude/rules` / `.grok/rules` copies.

## Troubleshooting

- Contract not active → new session after a `match` refresh.
- Full flag list / musl / keyed-config guard → `README.md` and `install.sh --help`.
- Scratch test: `GROK_HOME=/tmp/grok-home bash "$INSTALL" --docs-only --dry-run`
