---
name: grok-search
description: "This skill should be used when the user needs live web search, current documentation, web page fetching, site mapping, or verified external source citations via the grok-search MCP service."
---

# Grok Search

Use this skill to perform live web searches, plan search intent, fetch web content, map site topologies, and extract citations.

The same tools are available over stdio or the additive HTTP MCP (`type: http` to Tailscale `:8800/mcp` with `GROK_SEARCH_MCP_TOKEN`). Prefer whichever transport the host already has connected.

## Tool Workflow

Follow this execution discipline when searching or fetching external information:

### 1. Search Planning & Query Formulation

- Call `plan_intent` before every `web_search`. The MCP tool description requires that planning step.
- Leave `extra_sources` at its default unless the user explicitly requests extra provider hits.

### 2. Search Execution & Citation Tracking

- Execute `web_search` with the formulated query.
- When `web_search` returns a `session_id`, call `get_sources` with that `session_id` to retrieve full source URLs, titles, and publication metadata.
- Cite sources with canonical URLs and factual provenance in the final answer.

### 3. Fetching and Site Exploration

- Use `web_fetch` to retrieve the readable markdown content of a specific URL when search snippets are insufficient.
- Use `web_map` to discover pages, endpoints, and structure across a target domain or documentation tree.

### 4. Diagnostic & Configuration Inspection

- Use `get_config_info` strictly for diagnostic troubleshooting (e.g. verifying connectivity or backend version). Never log or display sensitive credentials or tokens.
- Only call `toggle_builtin_tools` or `switch_model` if explicitly requested by the user.

## Error Handling & Discipline

- Report search or fetch failures honestly. If a URL is inaccessible or search yields no relevant results, state what was attempted rather than speculating.
- Adapt tool invocations to the host environment's MCP tool naming without assuming rigid tool prefixes.
