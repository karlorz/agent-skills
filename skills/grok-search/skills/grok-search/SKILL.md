---
name: grok-search
description: This skill should be used when the user needs live web search, current docs, page fetch, or site mapping via grok-search; detect a connector, in-thread MCP card, or standalone CLI.
---

# Grok Search

Live web search, fetch, and site mapping. Production HTTP MCP: `https://search.karldigi.dev/mcp`.

## First-run: detect → install → init

When the operator asks to enable grok-search, discover the host. Do not ask them to pick Cue vs CLI vs marketplace.

Detect in order and stop at the first matching route:

1. **Connector present:** Host `grok-search` MCP tools (`web_search`, `get_sources`, …) are available. On desktop Claude/Grok/Codex/Cursor plugin hosts, consult [first-run.md](references/first-run.md) desktop readiness before the first `plan_*` / `web_search`. Then use connector mode: `plan_*` then `web_search`. Ignore leftover `grok-search-http`; it is not a fallback. Never dual-call it or write host MCP files.
2. **In-thread MCP card:** The host can add an HTTP MCP app from chat (Cue / 小Q). Add `grok-search` at `https://search.karldigi.dev/mcp` with **no custom headers**; finish the in-thread Added / authorize card with the operator. Secrets stay in the host UI, never in chat. Then return to step 1.
3. **Skill+CLI:** MCP tools are still missing, no in-thread card is available, and the host has git + Node. Follow [install.md](references/install.md): sparse-checkout `https://github.com/karlorz/agent-skills` at `skills/grok-search`, copy `skills/grok-search/skills/grok-search` into **one** host skill directory, or reuse the existing unit. Run `node scripts/grok-search.cjs` from that directory. On `auth_required`, run `auth-start --agent-id <short host label>` (`kimi`, `cue`, `muse`, `doubao`, …), reply with `approveUrl` only, and loop `auth-status` in the **same turn** until `authenticated`, respecting `intervalSeconds` and stopping at `expiresAt` or a terminal error. Each invocation makes one check; never start an unbounded poll. Never print the token or poll secret; never write `mcp.json` / `config.toml`.
4. **Chat-only:** Stop (ChatGPT web, Doubao 对话, WeCom). A person finishes connector/OAuth outside chat. Do not ask the chat to create the app, click 去授權, or type the operator password.

**Init smoke:** Make one tiny search after connection/authentication: connector `plan_*` then `web_search`, or CLI `node scripts/grok-search.cjs search --query "Node.js official documentation"`. Verify usable content and sources before claiming readiness.

Host exceptions and setup details: [first-run.md](references/first-run.md). CLI options and auth polling: [cli-contract.md](references/cli-contract.md), [auth-contract.md](references/auth-contract.md).

## CLI Execution (Standalone Mode)

From the installed skill directory:

```bash
node scripts/grok-search.cjs search --query "..."
node scripts/grok-search.cjs fetch --url "https://..."
node scripts/grok-search.cjs map --url "https://..."
```

Plan locally before search: **plan_intent**, **plan_complexity**, **plan_sub_query**, **plan_search_term**, **plan_execution**. Do not invoke server planning tools in CLI mode.

Pass `--invite-code <code>` on `auth-start` only when the operator supplied one.

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

Report safe search, fetch, and handshake error codes. Never repeat raw upstream diagnostics. An ambiguous transport failure must not trigger a duplicate paid search. Do not invent credentials or switch to another MCP server name.
