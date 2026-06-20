---
name: grill-me
description: Interview the user relentlessly about a plan or design. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases.
metadata:
  upstream: https://github.com/mattpocock/skills/tree/main/skills/productivity
  upstream_license: MIT
---

# Grill Me

Interview me relentlessly about every aspect of this plan until we reach a
shared understanding. Walk down each branch of the design tree, resolving
dependencies between decisions one-by-one. For each question, provide your
recommended answer.

Ask the questions one at a time, waiting for feedback on each question before
continuing. Asking multiple questions at once is bewildering.

If a question can be answered by exploring the codebase, explore the codebase
instead.

## Ask Style

Run this skill in the main session; do not delegate it to a subagent.

Ask open-ended grilling questions conversationally.

For concrete decision points with 2-4 choices, use whichever structured question
tool exists in the current surface:

- Claude Code: `AskUserQuestion`
- Codex CLI/App: `ask_user_question`
- Antigravity CLI: `ask_question`

If no structured question tool exists, ask conversationally with numbered
options. Do not add an explicit "Other" option for Antigravity; its UI already
supplies one.

Under `/goal`, `codex exec`, scheduled runs, or other unattended contexts, skip
the interview and state that grilling requires an attended main session.
