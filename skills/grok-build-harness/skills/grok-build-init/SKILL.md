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
- **Status only** — no writes. Print the records **in this chat** (not only a collapsed tool card): status word, what it means, plugin version, live Keep working line.

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
bash "$INSTALL" --docs-status
```

The CLI word is for scripts. In the session, quote:

| Word | Meaning |
|---|---|
| `match` | harness block equals installed assets |
| `drift` | block present but differs |
| `missing` | no `AGENTS.md` |
| `unmarked` | v0.2.0 unmarked contract |
| `absent` | file exists, no harness block |

Also print the installed `grok-build-harness` version and the live Keep working line from `$GROK_HOME/AGENTS.md` (full marker block if that line is missing). Do not skip the records and jump to "no problem" / the next scenario. Then Ask User Question if another scenario remains.

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

Claude.md / Codex AGENTS.md auto-detect is out of scope for this Grok slice.

## Troubleshooting

- Contract not active → new session after a `match` refresh.
- Full flag list / musl / keyed-config guard → `README.md` and `install.sh --help`.
- Scratch test: `GROK_HOME=/tmp/grok-home bash "$INSTALL" --docs-only --dry-run`
