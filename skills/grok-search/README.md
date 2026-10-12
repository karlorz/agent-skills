# grok-search

Live web search, page fetch, and site mapping.

## Ask an agent

Copy this to the agent:

> Enable grok-search on this host. Production MCP is https://search.karldigi.dev/mcp. Source: https://github.com/karlorz/agent-skills nested unit skills/grok-search/skills/grok-search. Read that unit's SKILL.md. Discover how this host can connect, then run one tiny search. Do not write host MCP config. Do not paste secrets into chat.

The agent follows [`skills/grok-search/SKILL.md`](skills/grok-search/SKILL.md): use existing grok-search tools, else an in-thread HTTP MCP card, else Skill+CLI, else stop. Host detail lives in [`references/first-run.md`](skills/grok-search/references/first-run.md). Skill+CLI copy steps live in [`references/install.md`](skills/grok-search/references/install.md).

## Marketplace plugin (optional)

```bash
claude plugin install grok-search@karlorz-agent-skills
codex plugin add grok-search@karlorz-agent-skills
```

Cursor: install `grok-search` from the `karlorz-agent-skills` marketplace.

## License

MIT
