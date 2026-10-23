# grok-search

Live web search, page fetch, and site mapping. Choose one setup request below.
Default for a new installation: `https://search.karldigi.dev/mcp`. Reuse a saved
address unless you explicitly supply another compatible GrokSearch MCP URL.
See [address selection](skills/grok-search/references/endpoint.md).

## Connector

> Connect to grok-search using https://search.karldigi.dev/mcp by default, or the MCP URL I explicitly provide, using https://github.com/karlorz/agent-skills. Read skills/grok-search/skills/grok-search/SKILL.md and follow this host's supported connector setup. Reuse a working connection for the selected address, complete secure authorization if needed, then verify one tiny search and source retrieval. Do not write host MCP config. Do not paste secrets into chat.

The agent selects the supported native connector or vaulted helper using the
[host guide](skills/grok-search/references/first-run.md). New authorization may
require your sign-in and consent. If this host cannot support a connector, use
the Skill + CLI route below. No server redeployment is needed.

## Skill + CLI

> Install the grok-search Skill+CLI from https://github.com/karlorz/agent-skills using sparse checkout of skills/grok-search at a reviewed release SHA. Preserve an existing installation and its saved address unless I explicitly provide another MCP URL; otherwise copy its nested skills/grok-search unit into one host skill directory. Follow the installed SKILL.md to authorize and verify a small search with sources. Do not configure host MCP or paste secrets into chat.

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
