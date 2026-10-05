---
name: grok-search
description: This skill should be used when the user needs live web search, current docs, page fetch, or site mapping via grok-search MCP or standalone CLI.
---

# Grok Search

Use this skill to perform live web searches, plan search intent, fetch web content, map site topologies, and extract citations.

## Mode Selection: Connector vs CLI

This skill operates in one of two modes:

1. **Connector mode:** If host `grok-search` MCP tools (`web_search`, `get_sources`, etc.) are already connected, use the HTTP MCP tools directly. Follow the server `plan_*` workflow. Do not auto-disable other plugins or dual-call preview aliases.
2. **CLI mode:** If no grok-search MCP connector tools are available, do not write host MCP configuration. Plan searches locally within the conversation (determine intent, complexity, sub-queries, and search terms locally; do NOT call server `plan_*` tools), then execute queries via the bundled CLI: `node <skill-dir>/scripts/grok-search.cjs`.

Grok-search HTTP MCP uses `type: http`. The installed desktop plugin sends `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}` from `.mcp.json` / Cursor `mcp.json`; Codex uses `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`. Claude/Grok use `GROK_SEARCH_MCP_URL` as an optional override and otherwise default to `https://search.karldigi.dev/mcp`. Codex and Cursor-native pin production; the URL override is not configurable in Cursor or the Codex marketplace package. Grok skips OAuth when that Authorization header is present. ChatGPT/Doubao keep HTTPS OAuth. Do not start a local stdio `uvx` server.

## First-run readiness

- **Desktop token:** Export `GROK_SEARCH_MCP_TOKEN` in the shell that launches the client. The installed plugin already includes the Authorization header, so Grok skips OAuth. A missing token still leaves the header key and yields 401 instead of `[authenticating]`.
- **Operator browser not on this host (SSH):** MCP OAuth loopback (`http://localhost:<port>/callback`) binds on the host running the MCP client. Headed vs headless is not the discriminator: `DISPLAY`, VNC, or a local Chrome on this host cannot help when the operator browser is on another machine. `SSH_CONNECTION` / `SSH_TTY` is only a hint. If `check_readiness.py` `warnings` contain `headless_oauth_loopback`, or Grok sits at `[authenticating]` / shows an OAuth login URL or 401 over SSH: stop, and do not press `/mcps` `i`. Confirm `GROK_SEARCH_MCP_TOKEN` is exported. Cursor CLI overlay remains `cursor-cli-mcp.example.json`. Optional Grok user `~/.grok/config.toml` HTTP overlay (table must not contain `command=`):
    ```toml
    [mcp_servers.grok-search]
    url = "https://search.karldigi.dev/mcp"

    [mcp_servers.grok-search.headers]
    Authorization = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
    ```
  Do not tell the operator to click the login link on another machine. If grok-search tools are already connected, continue.
- **Claude/Grok plugin hosts:** resolve the installed root from `GROK_PLUGIN_ROOT`, falling back to `CLAUDE_PLUGIN_ROOT`, and run `python3 "$PLUGIN_ROOT/scripts/check_readiness.py" --apply --json` before the first grok-search MCP call. `in_sync` means the probe has verified the configuration. If `warnings` mention a stale preview URL, report it and keep production; do not start sg01 `:8800` and do not live-probe that listener. If `warnings` mention `headless_oauth_loopback`, follow the operator-browser rule above. If `warnings` mention `leftover_stdio_config`, the marketplace HTTP plugin is shadowed by `~/.grok/config.toml` `[mcp_servers.grok-search]` stdio (`command=` / `uvx`). Tell the operator to remove that table, or replace `command=` with the HTTP overlay above; Grok `/mcps` `i` auth is HTTP/SSE only. Do not write `config.toml`. Claude Code `userConfig` stays removed; in-app and CLI installs read process env `GROK_SEARCH_MCP_TOKEN`.
- **Codex:** the native manifest embeds a Codex-specific production HTTP MCP definition with `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN` and no apps; it pins production and never parses the Claude/Grok shell-style URL fallback.
- **Cursor-native / Agent TUI:** Cursor-native pins production and does not run the probe; the URL is not configurable in Cursor. Cursor plugin `variables` stay removed; installed `mcp.json` sends `Bearer ${GROK_SEARCH_MCP_TOKEN}`. If `grok-search` tools are connected, continue; otherwise report the MCP connection error.
- **ChatGPT web:** A person configures ChatGPT web at `https://chatgpt.com/admin/apps` Create App, URL `https://search.karldigi.dev/mcp`, auth OAuth. The GitHub marketplace card is desktop-only because `mcp.json` ships.
- **A chat cannot finish first-time connector setup.** ChatGPT web chat and Doubao Work chat cannot open connector settings or submit consent. Doubao Work setup is `技能 · 連接器 · 夥伴` → 我的技能 → 連接器 → 新增自訂連接器, HTTP, the production URL, no custom headers, then 去授權 and the operator password in the browser. After that connector is authorized, the chat may call `web_search`. Do not ask the chat to create the app, click 去授權, or type the operator password.
- Grok SessionStart cannot inject the parent MCP environment. `~/.config/grok-search/mcp.env` is not auto-sourced.
- A 401 is an MCP handshake failure or missing `GROK_SEARCH_MCP_TOKEN`, not a readiness-probe status. Report it and stop. Over SSH, treat an OAuth login URL the same way: report `headless_oauth_loopback` and stop.
- Never auto-source `mcp.env` or auto-write `~/.cursor/mcp.json`, Grok `config.toml`, or `~/.config/grok-search/mcp.env`.
- A leftover `grok-search-http` connection is a preview overlay inherited from operator Cursor MCP config. It is not a fallback. Never dual-call it; do not dual-call preview aliases.

## CLI Execution (Standalone Mode)

When grok-search MCP tools are not registered on the host, use the bundled CLI script `scripts/grok-search.cjs`.

### Planning Locally
Plan the search locally inside your reasoning before running CLI search:
- **plan_intent**: Identify search goals, entity disambiguation, and constraints.
- **plan_complexity**: Gauge simple vs complex multi-hop research.
- **plan_sub_query**: Break complex requests into targeted sub-queries.
- **plan_search_term**: Formulate concise queries.
- **plan_execution**: Sequence the search steps.
Do NOT attempt to invoke server planning tools in CLI mode.

### Running CLI Commands
From the installed skill directory root:
```bash
node scripts/grok-search.cjs search --query "..."
node scripts/grok-search.cjs fetch --url "https://..."
node scripts/grok-search.cjs map --url "https://..."
```

If the CLI exits with `{ "ok": false, "error": { "code": "auth_required" } }`:
1. Instruct the user to run `node scripts/grok-search.cjs auth-start`.
2. The user approves authentication on mobile or browser.
3. Check `node scripts/grok-search.cjs auth-status` until authenticated.

## Endpoint contract

- Production (kr01, proven): `https://search.karldigi.dev/mcp` — desktop `GROK_SEARCH_MCP_TOKEN`; ChatGPT/Doubao MCP OAuth (Cursor-native pins this endpoint)
- Stale Tailscale preview (do not use, do not start on sg01): `http://100.76.134.104:8800/mcp` and `http://100.118.12.90:8800/mcp`. sg01 has no grok-search `:8800` listener. `check_readiness.py` warns if `GROK_SEARCH_MCP_URL` still points there; it does not fail the session and does not probe the port.
- Cloudflare Access (preview / fallback): `https://search.termolo.com/mcp` — Claude/Grok override requiring operator-local Access headers

## Tool workflow (Connector Mode)

### Search planning and execution

Before every `web_search` in connector mode, follow the planning tool descriptions:

1. Call `plan_intent`.
2. Call `plan_complexity`.
3. Call `plan_sub_query` for each sub-query.
4. For complexity levels that require them, call `plan_search_term`, `plan_tool_mapping`, and `plan_execution` in the order described by the tools.
5. Call `web_search`. Leave `extra_sources` at its default unless the user explicitly requests extra provider hits.
6. Treat `content == ""` or `content` starting with `upstream_error:` / `upstream_empty:` as a **failed search**, not “no results.” Report the envelope literally, retry `web_search` once, then `web_fetch` an authoritative URL. Do not tell the user the web had no hits.
7. When `web_search` returns a `session_id` and non-empty answer content, call `get_sources` to retrieve full source metadata and cite canonical URLs.

### Fetching and site exploration

- Use `web_fetch` for readable markdown from a specific URL when search snippets are insufficient.
- Use `web_map` to discover pages and structure across a documentation tree or site.

### Diagnostics

- Use `get_config_info` only for connectivity or backend diagnostics. Never display credentials.
- A healthy production response identifies the configured remote engine, `streamable_http` transport, and `https://search.karldigi.dev/mcp`, and explains that the client needs no local GrokSearch, GUDA, Tavily, Firecrawl, `uv`, or Python service.
- Treat loopback or internal service URLs, filesystem paths, credential fields or masked fragments, upstream response bodies, and low-level exception details in the public diagnostic as a contract failure. Do not repeat sensitive output.
- Call `toggle_builtin_tools` or `switch_model` only when explicitly requested.

## Errors

Report search, fetch, and handshake failures literally. Do not speculate, invent credentials, or switch to the leftover preview alias.

A successful MCP tool result can still be a failed search: HTTP 200 with `content: ""` or `upstream_error:` / `upstream_empty:` means GrokSearch got no answer text. New API output tokens do not prove MCP `content` is usable. Retry once, then fetch.
