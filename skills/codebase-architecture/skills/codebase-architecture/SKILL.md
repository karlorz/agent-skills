---
name: codebase-architecture
description: Use when the user asks for codebase-architecture, the architecture skill chain, reimplementation playbook, or is unsure whether to analyze, design vocabulary, improve, or to-spec. Routes to the correct specialized skill; does not replace them.
metadata:
  role: router
---

# Codebase Architecture (router)

Thin router for the **codebase-architecture** plugin. Do **not** run the full chain alone — pick one specialized skill and invoke it.

## Choose one

| User intent | Invoke skill |
|-------------|--------------|
| Document / reverse-engineer / C4 / topology / reimplementation extract | `codebase-architecture-analyze` |
| Deep-module vocabulary, seams, interface design language | `codebase-design` |
| Shallow modules, deepening opportunities, architecture HTML review | `improve-codebase-architecture` |
| Conversation → PRD / spec without interview | `architecture-to-spec` |
| Large multi-file rewrite batches | External `codebase-migrate` (not in this plugin) |

If multiple steps are needed, run them in order:

1. Load `codebase-design` vocabulary first (or let each skill load it before durable writes)
2. `codebase-architecture-analyze` (extracts)
3. Optional `improve-codebase-architecture`
4. `architecture-to-spec`
5. External migrate / normal implementation

(Use the choose-one table when the user wants only vocabulary/interface design — invoke `codebase-design` alone.)

## Shared contracts

- Output routing: [output-routing.md](../../references/output-routing.md)
- Playbook graph: [playbook-chain.md](../../references/playbook-chain.md)
- C4 evidence rules: [c4-evidence.md](../../references/c4-evidence.md)

## Complements (not bundled)

- `deep-research` / PavedPath — external evidence
- `grill-me` / `grilling` — after improve picks a candidate
- Official feature-dev / Archcore when preferred

## After routing

Load the chosen skill's `SKILL.md` and follow it completely. Announce which skill was selected and why (one sentence).
