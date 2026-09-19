# Global Subagent Routing and Workflow Rules

These rules apply to parent agents and subagents in this harness. They
supplement — never override — explicit user instructions or deeper project
`AGENTS.md` files.

## Routing

- **Planning and judgment stay on the main agent (frontier).** Planning,
  architecture, synthesis, and final decisions run on the session parent or a
  `model: inherit` agent. If a skill would use sonnet-pinned
  `general-purpose` for planning or final review, override its model to the
  parent model or run that step inline.
- **Implementation and mechanical work default to `sonnet`.** Delegate code
  changes, exploration, and repetitive work to `general-purpose`, `scout`, or
  `explore`; their config pins prevent an accidental frontier-model spawn.
  Override only when the user explicitly asks or unresolved design judgment
  requires the parent.
- **Review returns to the parent.** Review subagents may gather spec, quality,
  and test evidence, but their verdicts are advisory. The parent inspects the
  diff and evidence and decides accept, reject, or fix.
- Keep ordinary spawn calls on the configured pins. Add a model override only
  for the frontier work above; add restrictions such as read-only capability
  or worktree isolation only when the task needs them.

## Goal mode

- The planning fork inherits the live parent model.
- Delegate implementation to sonnet-pinned `general-purpose`; do not unpin it
  to make skeptics inherit the parent.
- The parent reviews each implementation result. Skeptics provide sonnet-pinned
  verification evidence, and the host binds final completion after the panel.

## Delegation

- Prefer a one-shot `scout` for read-only evidence. Use `general-purpose` only
  when broader tools or writes are required.
- Do not create nested subagent trees. A child returns decomposition requests
  to the parent.
- Never give concurrent workers overlapping write scopes. Use isolated
  worktrees for independent concurrent edits.
- The parent owns edits, integration decisions, and final verification.

## Evidence and context

- Treat subagent output as a lead. Require compressed `file:line` evidence,
  symbols, commands, and short excerpts; distinguish facts, inferences,
  uncertainty, and unchecked scope.
- Spot-check important references and run the shipped entry point or relevant
  tests before claiming correctness.
- Do not paste whole files or verbose logs when a path, line range, and concise
  excerpt suffice. Split broad research into focused questions and re-check
  workspace state after parallel or long-running work.
