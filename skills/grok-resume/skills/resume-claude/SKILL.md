---
name: resume-claude
description: >
  Resume or continue work from a recent Claude Code session. Use when the user
  switched from Claude Code, says "continue from Claude" or "resume my Claude
  session", or names a Claude session by description, path, or native ID.
metadata:
  short-description: "Continue from a recent Claude Code session"
---

Set `TOOL=claude`. Resolve `SHARED_DIR` as `../../shared/resume-session`, relative
to the directory containing this `SKILL.md`. Read and follow
`${SHARED_DIR}/CORE.md`, using the text supplied after the skill invocation
unchanged as the optional session reference.
