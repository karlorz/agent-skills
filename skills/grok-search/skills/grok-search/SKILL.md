---
name: grok-search
description: This skill should be used when the user needs live web search, current docs, page fetch, or site mapping via grok-search MCP.
---

# Grok Search

Use this skill to perform live web searches, plan search intent, fetch web content, map site topologies, and extract citations.

Grok-search is HTTP MCP only (`type: http`). Claude/Grok use `GROK_SEARCH_MCP_URL` as an optional override and otherwise default to `https://search.karldigi.dev/mcp`. Codex and Cursor-native pin production; the URL override is not configurable in Cursor or the Codex marketplace package. Every host requires an operator-provided gateway-keys bearer as `GROK_SEARCH_MCP_TOKEN` before MCP load. Do not start a local stdio `uvx` server.

## First-run readiness

- **Claude/Grok plugin hosts:** resolve the installed root from `GROK_PLUGIN_ROOT`, falling back to `CLAUDE_PLUGIN_ROOT`, and run `python3 "$PLUGIN_ROOT/scripts/check_readiness.py" --apply --json` before the first grok-search MCP call. `missing_prereq` means the token is absent from process environment; stop and ask for a gateway-keys bearer. `in_sync` means the probe has a usable URL/token decision.
- **Codex:** the native manifest embeds a Codex-specific production HTTP MCP definition with `bearer_token_env_var: GROK_SEARCH_MCP_TOKEN`; it never parses the Claude/Grok shell-style URL fallback. Codex Desktop/IDE may not inherit shell variables; place the token in Codex's supported environment file and fully restart Codex. Never put the token value in `config.toml` or plugin files.
- **Cursor-native:** the plugin's **Plugins → Configure** UI requires the token variable and the manifest pins production, so Cursor-native does not run the probe or read a Cursor process environment variable. If `grok-search` tools are connected, continue; otherwise report the MCP connection error.
- Grok SessionStart cannot inject the parent MCP environment. `~/.config/grok-search/mcp.env` is not auto-sourced. A restart cannot supply a missing token.
- A 401 is an MCP handshake failure, not a readiness-probe status. Report it and stop.
- Never auto-source `mcp.env` or auto-write `~/.cursor/mcp.json`, Grok `config.toml`, or `~/.config/grok-search/mcp.env`.
- A leftover `grok-search-http` connection is a preview overlay inherited from operator Cursor MCP config. It is not a fallback. Never dual-call it.

## Endpoint contract

- Production: `https://search.karldigi.dev/mcp` — gateway-keys bearer (recommended; Cursor-native pins this endpoint)
- Tailscale: `http://100.76.134.104:8800/mcp` — Bearer-only preview override for Claude/Grok via `GROK_SEARCH_MCP_URL`
- Cloudflare Access: `https://search.termolo.com/mcp` — Claude/Grok preview override requiring operator-local Access headers

## Tool workflow

### Search planning and execution

Before every `web_search`, follow the planning tool descriptions as the source of truth:

1. Call `plan_intent`.
2. Call `plan_complexity`.
3. Call `plan_sub_query` for each sub-query.
4. For complexity levels that require them, call `plan_search_term`, `plan_tool_mapping`, and `plan_execution` in the order described by the tools.
5. Call `web_search`. Leave `extra_sources` at its default unless the user explicitly requests extra provider hits.
6. When `web_search` returns a `session_id`, call `get_sources` to retrieve full source metadata and cite canonical URLs.

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
