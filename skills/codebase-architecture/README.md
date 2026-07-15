# codebase-architecture

Plugin skill chain for **analyze / extract → deep-module design → optional deepen → to-spec**, with wiki-first markdown output.

**Version:** see `.claude-plugin/plugin.json` (keep in sync with `.codex-plugin/plugin.json` and root marketplace entry).

## Skills

| Skill | Role |
|-------|------|
| `codebase-architecture` | Router — choose one specialized skill |
| `codebase-design` | Deep-module vocabulary (module, interface, depth, seam, adapter, leverage, locality) |
| `codebase-architecture-analyze` | Architecture analyze + durable extracts |
| `improve-codebase-architecture` | Shallow-module scan → HTML/MD review in temp |
| `architecture-to-spec` | Conversation → PRD/spec without interview |

**Not bundled:** `codebase-migrate` (batched execution), deep-research, PavedPath, grill-me (optional complements).

## Output routing (default)

1. Explicit user path  
2. SkillWiki vault + existing `projects/{slug}/` → `{vault}/projects/{slug}/architecture/`  
3. Else `{repo}/docs/architecture/`  
4. Improve reports: `$TMPDIR` only  

Slug algorithm, provenance headers, and spec publish order: `references/output-routing.md`.

## Layout

```
skills/codebase-architecture/
├── .claude-plugin/plugin.json
├── .codex-plugin/plugin.json
├── README.md
├── references/
│   ├── playbook-chain.md
│   ├── output-routing.md
│   ├── c4-evidence.md
│   ├── deepening.md
│   ├── design-it-twice.md
│   └── html-report.md
└── skills/
    ├── codebase-architecture/
    │   ├── SKILL.md                            # router
    │   └── agents/openai.yaml
    ├── codebase-design/
    │   ├── SKILL.md
    │   └── agents/openai.yaml
    ├── codebase-architecture-analyze/
    │   ├── SKILL.md
    │   └── agents/openai.yaml
    ├── improve-codebase-architecture/
    │   ├── SKILL.md
    │   └── agents/openai.yaml
    └── architecture-to-spec/
        ├── SKILL.md
        └── agents/openai.yaml
```

## Install smoke

After marketplace or local path install, confirm these skill names appear:

- `codebase-architecture`
- `codebase-design`
- `codebase-architecture-analyze`
- `improve-codebase-architecture`
- `architecture-to-spec`

Dry-run routing mentally:

- Target with wiki project → `projects/{slug}/architecture/`
- Target without wiki project → `docs/architecture/`

From agent-skills repo:

```bash
bash scripts/test-dev-loop-release-tooling.sh
bash scripts/test-dev-loop-preflight-inventory.sh
```

## Lineage

- [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) — design / improve / to-spec  
- FindSkill architecture-explainer — analysis phases  
- [lmammino/c4-codebase-architecture-skill](https://github.com/lmammino/c4-codebase-architecture-skill) (MIT) — evidence vs inference patterns  
- Vault: `comparisons/codebase-analysis-reimplementation-skills`, `concepts/codebase-analysis-reimplementation-playbook`
