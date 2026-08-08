## Subagent contract
- Planning stays on the main agent (frontier). Never delegate planning to `sonnet`.
- Implementation defaults to subagents on `sonnet` (`[subagents.models]` pins gp/scout/explore/browser-use). Skills that spawn gp without `model:` still get sonnet via the pin.
- Review of implementation results returns to the main agent for final mid-round verdict.
- Goal mode: plan inherits parent (fork). Implement via gp → sonnet pin (or product "implement yourself" on parent if no spawn). Skeptics unpinned → sonnet pin (not live parent). Do not unpin gp to chase parent skeptics. Product completion = skeptic panel + host Achieved bind.
- Require file:line evidence. Compress output. No nested subagent trees.
- Parent owns all edits, decisions, and final verification.
- Full rules: read `~/.grok/agentrules.md`.
