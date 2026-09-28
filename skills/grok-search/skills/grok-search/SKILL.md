---
name: grok-search
description: This skill should be used when the user needs live web search, current docs, page fetch, or site mapping via grok-search MCP.
---

# Grok Search

Use this skill to perform live web searches, plan search intent, fetch web content, map site topologies, and extract citations.

Grok-search is HTTP MCP only (`type: http`). The installed desktop plugin uses MCP OAuth for authentication and does not store or require a bearer token. Claude/Grok use `GROK_SEARCH_MCP_URL` as an optional override and otherwise default to `https://search.karldigi.dev/mcp`. Codex and Cursor-native pin production; the URL override is not configurable in Cursor or the Codex marketplace package. A gateway-keys bearer is an operator-written overlay using `GROK_SEARCH_MCP_TOKEN`: Grok user `config.toml` HTTP `url` plus `headers.Authorization`, or `cursor-cli-mcp.example.json` for Cursor CLI. Do not start a local stdio `uvx` server.

## First-run readiness

- **First-run OAuth:** The installed desktop plugin connects to `https://search.karldigi.dev/mcp` via MCP OAuth. On first run, complete the client OAuth authorization prompt **on the same host** as the waiting MCP client if prompted.
- **Operator browser not on this host (SSH):** MCP OAuth loopback (`http://localhost:<port>/callback`) binds on the host running the MCP client. Headed vs headless is not the discriminator: `DISPLAY`, VNC, or a local Chrome on this host cannot help when the operator browser is on another machine. `SSH_CONNECTION` / `SSH_TTY` is only a hint. If `check_readiness.py` `warnings` contain `headless_oauth_loopback`, or Grok sits at `[authenticating]` / shows an OAuth login URL or 401 over SSH: stop, and do not press `/mcps` `i`. Ask the operator to overlay a gateway-keys bearer so the client skips OAuth:
  - Grok: user `~/.grok/config.toml`, with `GROK_SEARCH_MCP_TOKEN` exported in the shell that launches Grok. The table must not contain `command=`; Grok skips OAuth when the HTTP server has an Authorization header.
    ```toml
    [mcp_servers.grok-search]
    url = "https://search.karldigi.dev/mcp"

    [mcp_servers.grok-search.headers]
    Authorization = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
    ```
  - Cursor CLI: `cursor-cli-mcp.example.json`.

  Process env token alone does not skip plugin OAuth. The installed `.mcp.json` stays OAuth with no Authorization header. Do not tell the operator to click the login link on another machine. If grok-search tools are already connected, continue.
- **Claude/Grok plugin hosts:** resolve the installed root from `GROK_PLUGIN_ROOT`, falling back to `CLAUDE_PLUGIN_ROOT`, and run `python3 "$PLUGIN_ROOT/scripts/check_readiness.py" --apply --json` before the first grok-search MCP call. `in_sync` means the probe has verified the configuration. If `warnings` mention a stale preview URL, report it and keep production; do not start sg01 `:8800` and do not live-probe that listener. If `warnings` mention `headless_oauth_loopback`, follow the operator-browser rule above. If `warnings` mention `leftover_stdio_config`, the marketplace HTTP plugin is shadowed by `~/.grok/config.toml` `[mcp_servers.grok-search]` stdio (`command=` / `uvx`). Tell the operator to remove that table, or replace `command=` with the HTTP overlay above; Grok `/mcps` `i` auth is HTTP/SSE only. Do not write `config.toml`. Claude Code `userConfig` is removed; in-app and CLI installs connect via HTTP MCP OAuth without prompting for a token. Grok process environment does not require a token for the installed plugin.
- **Codex:** the native manifest embeds a Codex-specific production HTTP MCP definition without `bearer_token_env_var` or apps; it pins production and never parses the Claude/Grok shell-style URL fallback.
- **Cursor-native / Agent TUI:** Cursor-native pins production and does not run the probe; the URL is not configurable in Cursor. Cursor does not require token variables or prompts. If `grok-search` tools are connected, continue; otherwise report the MCP connection error.
- **ChatGPT web:** A person configures ChatGPT web at `https://chatgpt.com/admin/apps` Create App, URL `https://search.karldigi.dev/mcp`, auth OAuth. The GitHub marketplace card is desktop-only because `mcp.json` ships.
- **A chat cannot finish first-time connector setup.** ChatGPT web chat and Doubao Work chat cannot open connector settings or submit consent. Doubao Work setup is `技能 · 連接器 · 夥伴` → 我的技能 → 連接器 → 新增自訂連接器, HTTP, the production URL, no custom headers, then 去授權 and the operator password in the browser. After that connector is authorized, the chat may call `web_search`. Do not ask the chat to create the app, click 去授權, or type the operator password.
- Grok SessionStart cannot inject the parent MCP environment. `~/.config/grok-search/mcp.env` is not auto-sourced.
- A 401 is an MCP handshake failure or expired OAuth session, not a readiness-probe status. Report it and stop. Over SSH, treat an OAuth login URL the same way: report `headless_oauth_loopback` and stop.
- Never auto-source `mcp.env` or auto-write `~/.cursor/mcp.json`, Grok `config.toml`, or `~/.config/grok-search/mcp.env`.
- A leftover `grok-search-http` connection is a preview overlay inherited from operator Cursor MCP config. It is not a fallback. Never dual-call it; do not dual-call preview aliases.

## Endpoint contract

- Production (kr01, proven): `https://search.karldigi.dev/mcp` — MCP OAuth (recommended; Cursor-native pins this endpoint)
- Stale Tailscale preview (do not use, do not start on sg01): `http://100.76.134.104:8800/mcp` and `http://100.118.12.90:8800/mcp`. sg01 has no grok-search `:8800` listener. `check_readiness.py` warns if `GROK_SEARCH_MCP_URL` still points there; it does not fail the session and does not probe the port.
- Cloudflare Access (preview / fallback): `https://search.termolo.com/mcp` — Claude/Grok override requiring operator-local Access headers

## Tool workflow

### Search planning and execution

Before every `web_search`, follow the planning tool descriptions as the source of truth:

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
