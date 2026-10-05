---
name: grok-search
description: This skill should be used when the user needs live web search, current docs, page fetch, or site mapping via grok-search MCP or standalone CLI.
---

# Grok Search

Live web search, fetch, and site mapping. Production HTTP MCP: `https://search.karldigi.dev/mcp`.

## Mode Selection: Connector vs CLI

1. **Connector mode:** If host `grok-search` MCP tools (`web_search`, `get_sources`, etc.) are already connected, use them. Follow the server `plan_*` workflow. If a leftover `grok-search-http` server exists, ignore it; it is not a fallback. Never dual-call it.
2. **CLI mode:** If those tools are missing, do not write host MCP configuration. Plan locally (intent, complexity, sub-queries, search terms). Do not call server `plan_*` tools. Run `node <skill-dir>/scripts/grok-search.cjs`.

HTTP MCP is `type: http`. Installed `.mcp.json` / Cursor `mcp.json` send `Authorization: Bearer ${GROK_SEARCH_MCP_TOKEN}`. Codex uses `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`. Claude/Grok default the URL to production; `GROK_SEARCH_MCP_URL` may override on those hosts only. Codex and Cursor-native pin production; the URL is not configurable in Cursor. Grok skips OAuth when that Authorization header is present. ChatGPT/Doubao keep HTTPS OAuth. Do not start a local stdio `uvx` server.

## First-run readiness

- **Desktop token:** Export `GROK_SEARCH_MCP_TOKEN` in the process that launches the client. A missing token still leaves the header key and yields 401 instead of `[authenticating]`.
- **Operator browser not on this host (SSH):** MCP OAuth loopback binds on the host running the MCP client. Headed vs headless is not the discriminator: `DISPLAY`, VNC, or local Chrome on this host cannot finish a login in a browser on another machine. `SSH_CONNECTION` / `SSH_TTY` is only a hint. If `check_readiness.py` warnings contain `headless_oauth_loopback`, or Grok sits at `[authenticating]` over SSH: stop, and do not press `/mcps` `i`. Confirm `GROK_SEARCH_MCP_TOKEN` is exported. Cursor CLI overlay: `cursor-cli-mcp.example.json`. Optional Grok `~/.grok/config.toml` HTTP overlay (table must not contain `command=`):
    ```toml
    [mcp_servers.grok-search]
    url = "https://search.karldigi.dev/mcp"

    [mcp_servers.grok-search.headers]
    Authorization = "Bearer ${GROK_SEARCH_MCP_TOKEN}"
    ```
  Do not tell the operator to click the login link on another machine. If grok-search tools are already connected, continue.
- **Claude/Grok plugin hosts:** from `GROK_PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT`, run `python3 "$PLUGIN_ROOT/scripts/check_readiness.py" --apply --json` before the first MCP call. `in_sync` means the probe verified configuration. If warnings mention a stale preview URL, keep production. If `headless_oauth_loopback`, follow the operator-browser rule. If `leftover_stdio_config`, `~/.grok/config.toml` `[mcp_servers.grok-search]` still has stdio `command=` / `uvx` and shadows the HTTP plugin; tell the operator to remove that table or replace `command=` with the overlay above. Grok `/mcps` `i` auth is HTTP/SSE only. Do not write `config.toml`.
- **Codex:** native manifest pins production with `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`.
- **Cursor-native / Agent TUI:** Cursor-native pins production and does not run the probe. Installed `mcp.json` sends `Bearer ${GROK_SEARCH_MCP_TOKEN}`.
- **ChatGPT web:** A person creates the app at `https://chatgpt.com/admin/apps` Create App, URL `https://search.karldigi.dev/mcp`, OAuth. The GitHub marketplace card is desktop-only because `mcp.json` ships.
- **A chat cannot finish first-time connector setup.** Doubao Work: `技能 · 連接器 · 夥伴` → 我的技能 → 連接器 → 新增自訂連接器, HTTP, production URL, no custom headers, then 去授權 in the browser. Do not ask the chat to create the app, click 去授權, or type the operator password.
- Grok SessionStart cannot inject the parent MCP environment. `~/.config/grok-search/mcp.env` is not auto-sourced. Never auto-write `~/.cursor/mcp.json`, Grok `config.toml`, or `mcp.env`.
- A 401 is a handshake failure or missing token. Report it and stop.

## CLI Execution (Standalone Mode)

From the installed skill directory:

```bash
node scripts/grok-search.cjs search --query "..."
node scripts/grok-search.cjs fetch --url "https://..."
node scripts/grok-search.cjs map --url "https://..."
```

Plan locally before search: **plan_intent**, **plan_complexity**, **plan_sub_query**, **plan_search_term**, **plan_execution**. Do not invoke server planning tools in CLI mode.

On `auth_required`: run `auth-start`, approve in a browser, then `auth-status` until authenticated. Do not print the token or poll secret. Pass `--agent-id <id>` for this host (`muse` on Muse; otherwise a short host label). If the operator provided an invite code, pass `--invite-code <code>`.

## Connector workflow

Before every `web_search`:

1. Call `plan_intent`.
2. Call `plan_complexity`.
3. Call `plan_sub_query` for each sub-query.
4. For complexity levels that require them, call `plan_search_term`, `plan_tool_mapping`, and `plan_execution` in the order described by the tools.
5. Call `web_search`. Leave `extra_sources` at default unless the user asks for extra hits.
6. Treat `content == ""` or `content` starting with `upstream_error:` / `upstream_empty:` as a failed search. Report the envelope, retry `web_search` once, then `web_fetch`. Do not tell the user the web had no hits.
7. When `web_search` returns a `session_id` and non-empty content, call `get_sources`.

Use `web_fetch` for a specific URL. Use `web_map` to discover a site tree.

`get_config_info` is diagnostics only. Never display credentials. A healthy response names the remote `streamable_http` engine at `https://search.karldigi.dev/mcp` and that the client needs no local GrokSearch stack. Loopback URLs, filesystem paths, credential fragments, and exception bodies in that diagnostic are a contract failure; do not repeat them. Call `toggle_builtin_tools` or `switch_model` only when asked.

## Errors

Report search, fetch, and handshake failures literally. Do not invent credentials or switch to another MCP server name.
