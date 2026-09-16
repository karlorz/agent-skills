# Brainstorming

Claude Code and Codex plugin package for structured brainstorming with mandatory approval gates and an optional browser visual companion.

## Install

```bash
codex plugin add brainstorming@karlorz-agent-skills
claude plugin install brainstorming@karlorz-agent-skills
```

The visual companion requires Node.js and Bash. It is launched only after the user explicitly accepts the browser companion. Persistent session files must use an approved ignored scratch path such as `.superpowers/sdd/<work-id>/brainstorm/`.

External Prime Radiant branding traffic is disabled by default. Set `BRAINSTORM_ENABLE_TELEMETRY=1` only when the operator explicitly accepts that external image request.
