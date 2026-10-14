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

## Standalone Skill+CLI

> Install the grok-search Skill+CLI from https://github.com/karlorz/agent-skills using sparse checkout of skills/grok-search at a reviewed release SHA, copy its nested skills/grok-search unit into this host's skill directory, and run that unit's scripts/grok-search.cjs without configuring host MCP.

The [staging recipe](skills/grok-search/references/install.md) refuses to overwrite an
existing install and copies only the nested unit with root `SKILL.md`, scripts and
references. Use Node 22 or 24; runtime npm, Python and uv are unnecessary. Existing
marketplace connectors keep their own behavior. The CLI uses the pinned HTTPS
origin with a private file token or an environment token, and never writes host
MCP configuration. Hosted approval prints an HTTPS link and a desktop QR; every
status invocation makes one bounded check. See the
[auth contract](skills/grok-search/references/auth-contract.md) for expiry and recovery.

Before release, verify packaged install and QR decoding, hosted phone approval,
source-bearing search, fetch/map, and the unchanged connector at exact deployed
commits. SkillWiki transfer follows deployed M1 evidence; it is separate work.
