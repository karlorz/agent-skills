# grok-search

Live web search, page fetch, and site mapping. Choose one setup request below.
Production MCP: `https://search.karldigi.dev/mcp`.

## Connector

> Connect to the grok-search MCP at https://search.karldigi.dev/mcp using https://github.com/karlorz/agent-skills. Read skills/grok-search/skills/grok-search/SKILL.md and follow this host's supported connector setup. Reuse a working connection, complete secure authorization if needed, then verify one tiny search and source retrieval. Do not write host MCP config. Do not paste secrets into chat.

The agent selects the supported native connector or vaulted helper using the
[host guide](skills/grok-search/references/first-run.md). New authorization may
require your sign-in and consent. If this host cannot support a connector, use
the Skill + CLI route below. No server redeployment is needed.

## Skill + CLI

> Install the grok-search Skill+CLI from https://github.com/karlorz/agent-skills using sparse checkout of skills/grok-search at a reviewed release SHA. Reuse an existing installation; otherwise copy its nested skills/grok-search unit into one host skill directory. Follow the installed SKILL.md to authorize and verify a small search with sources. Do not configure host MCP or paste secrets into chat.

Use this route on a terminal host with git and Node 22 or 24. The
[installation guide](skills/grok-search/references/install.md) covers the complete
copy and verification steps; the [auth contract](skills/grok-search/references/auth-contract.md)
covers approval, expiry and recovery. Runtime npm, Python and uv are unnecessary.

<details>
<summary>Optional marketplace package</summary>

```bash
claude plugin install grok-search@karlorz-agent-skills
codex plugin add grok-search@karlorz-agent-skills
```

Cursor: install `grok-search` from the `karlorz-agent-skills` marketplace.
These commands install the marketplace package.

</details>

License: MIT.
