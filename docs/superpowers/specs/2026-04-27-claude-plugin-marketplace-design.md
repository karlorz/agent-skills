# Claude Plugin Marketplace Support

## Goal

Make the `agent-skills` repo compatible with the Claude Code plugin marketplace so users can:
1. Register this repo as a marketplace via `/plugin marketplace add`
2. Browse available skills
3. Install individual skills as plugins via `/plugin install <name>@agent-skills`
4. Use installed skills with auto-discovery

## Approach: Lightweight Wrapper

Preserve the existing `skills/` directory structure. Add a `.claude-plugin/` marketplace layer on top that references existing skill directories. No restructure, no breakage.

## Directory Layout (after changes)

```
agent-skills/
├── .claude-plugin/
│   └── marketplace.json           # NEW: marketplace catalog
├── skills/
│   ├── autopilot/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json         # NEW: plugin manifest
│   │   ├── SKILL.md                # existing
│   │   ├── AGENTS.md               # existing
│   │   ├── agents/                 # existing
│   │   ├── assets/                 # existing
│   │   ├── references/             # existing
│   │   ├── scripts/                # existing
│   │   └── templates/              # existing
│   ├── deep-research/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json         # NEW
│   │   ├── SKILL.md
│   │   ├── agents/
│   │   └── references/
│   ├── loop/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json         # NEW
│   │   ├── SKILL.md
│   │   └── scripts/
│   ├── obsidian-gh-knowledge/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json         # NEW
│   │   ├── SKILL.md
│   │   ├── AGENTS.md
│   │   ├── references/
│   │   ├── scripts/
│   │   └── tests/
│   └── simplify/
│       ├── .claude-plugin/
│       │   └── plugin.json         # NEW
│       ├── SKILL.md
│       └── agents/
├── archive/                        # existing (unchanged)
├── .gitignore                      # existing
└── docs/                           # existing + this spec
```

## marketplace.json

Located at `.claude-plugin/marketplace.json`. Lists each skill as an independent plugin with a relative-path source.

```json
{
  "name": "agent-skills",
  "owner": {
    "name": "Hermes Agent"
  },
  "metadata": {
    "description": "Curated skills for Claude Code: deep research, scheduled loops, code simplification, Obsidian knowledge management, and autopilot session management.",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "deep-research",
      "source": "./skills/deep-research",
      "description": "Multi-source research pipeline with auto-routing to Obsidian vault",
      "version": "1.0.0",
      "category": "research",
      "keywords": ["research", "deep-research", "obsidian", "pipeline"]
    },
    {
      "name": "loop",
      "source": "./skills/loop",
      "description": "Cron-like scheduler for recurring Claude prompts via OS scheduler backends",
      "version": "1.0.0",
      "category": "automation",
      "keywords": ["loop", "schedule", "cron", "recurring", "automation"]
    },
    {
      "name": "simplify",
      "source": "./skills/simplify",
      "description": "Code review with reuse, quality, and efficiency passes",
      "version": "1.0.0",
      "category": "code-quality",
      "keywords": ["simplify", "review", "refactor", "quality"]
    },
    {
      "name": "obsidian-gh-knowledge",
      "source": "./skills/obsidian-gh-knowledge",
      "description": "CLI-first Obsidian vault bootstrap and operation with local/GitHub fallback",
      "version": "1.0.0",
      "category": "knowledge",
      "keywords": ["obsidian", "knowledge", "github", "vault", "notes"]
    },
    {
      "name": "autopilot",
      "source": "./skills/autopilot",
      "description": "Managed Codex home-hook autopilot for self-sustaining session management",
      "version": "1.0.0",
      "category": "automation",
      "keywords": ["autopilot", "codex", "session", "hooks"]
    }
  ]
}
```

## plugin.json (per skill)

Each `skills/<name>/.claude-plugin/plugin.json` declares the plugin identity and points the `skills` path to `./` (the current directory, since SKILL.md is right there).

Example for `deep-research`:

```json
{
  "name": "deep-research",
  "version": "1.0.0",
  "description": "Multi-source research pipeline with auto-routing to Obsidian vault",
  "author": {
    "name": "Hermes Agent"
  },
  "license": "MIT",
  "keywords": ["research", "deep-research", "obsidian", "pipeline"],
  "skills": "./"
}
```

The `"skills": "./"` field tells Claude Code to scan the current directory for `SKILL.md` files, which is where they already live.

## User Workflow

After these files are added:

1. **Register the marketplace:**
   ```
   /plugin marketplace add github:hermes-agent/agent-skills
   ```
   (or the appropriate GitHub org/repo path)

2. **Browse available plugins:**
   ```
   /plugin marketplace update
   ```

3. **Install a specific skill:**
   ```
   /plugin install deep-research@agent-skills
   /plugin install loop@agent-skills
   ```

4. **Skills auto-discover on next session start** — installed skills' metadata loads into Claude's context; full SKILL.md loads on-demand when triggered.

## What Changes

| What | Before | After |
|------|--------|-------|
| `.claude-plugin/marketplace.json` | Does not exist | Created |
| `skills/<name>/.claude-plugin/plugin.json` | Does not exist (x5) | Created (x5) |
| `skills/` directory contents | Unchanged | Unchanged |
| Existing standalone skill usage | Works | Still works |
| `archive/` directory | Unchanged | Unchanged |

## Non-Goals

- Restructuring the existing `skills/` layout
- Moving skills into separate repos
- Adding a CI/CD pipeline for marketplace publishing
- Modifying SKILL.md content to accommodate the marketplace
