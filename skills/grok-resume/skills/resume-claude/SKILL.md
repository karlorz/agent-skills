---
name: resume-claude
description: Resume a recent Claude Code session from ~/.claude project JSONL. Use when switching from Claude or naming a Claude session.
metadata:
  short-description: "Continue from a recent Claude Code session"
---

Set `TOOL=claude`. Resolve `SHARED_DIR` as `../../shared/resume-session`, relative
to the directory containing this `SKILL.md`. Read and follow
`${SHARED_DIR}/CORE.md`, using the text supplied after the skill invocation
unchanged as the optional session reference.
