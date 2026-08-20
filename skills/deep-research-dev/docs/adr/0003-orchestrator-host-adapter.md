# Orchestrator module in SKILL.md with thin host adapter in agents/

The direct agent entrypoint `agents/deep-research-dev.md` previously duplicated
the entire Phase 1–6 workflow, subagent templates, and report contract from
`skills/deep-research-dev/SKILL.md`. This dual-file maintenance created drift
risk and required synchronized edits across both files for every contract change.

We make `skills/deep-research-dev/SKILL.md` the sole canonical orchestrator
module containing the full research recipe. `agents/deep-research-dev.md` becomes
a thin host adapter that instructs the agent to read and follow `SKILL.md` (and
STOP if unreadable), retaining only frontmatter metadata and discovery triggers.
Rejected alternatives: keep the duplicated twin (high maintenance burden and
drift risk); remove the agent entrypoint entirely (breaks direct agent
invocation and host discovery).
