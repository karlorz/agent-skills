---
name: grilling
description: Interview the user relentlessly about a plan or design. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases.
metadata:
  upstream: https://github.com/mattpocock/skills/tree/959a8e9f1edc3adbe2f7e3054bb6fbefa6696260/skills/productivity
  upstream_commit: 959a8e9f1edc3adbe2f7e3054bb6fbefa6696260
  upstream_license: MIT
  provenance: semantic-adaptation
---

# Grilling

Interview me relentlessly about every aspect of this plan until we reach a
shared understanding. Map the work as a design tree: every decision branches
into the decisions that depend on it.

The frontier is the set of decisions whose prerequisites are already settled:
the questions that can be asked now without guessing at answers that have not
been heard yet. Work through the frontier one question at a time. For each
question, provide your recommended answer and wait for feedback. Recompute the frontier
after every answer. Do not ask the whole frontier in one round.

Finding facts is the agent's job, not the user's. If a question needs a fact
from the filesystem, codebase, tools, or other environment, explore it before
asking the user.

In an attended main session, subagents may research only factual or environment
prerequisites. They must not choose design decisions, run the interview, ask
user questions, or act on the user's behalf. Treat an in-flight fact lookup as
an unsettled prerequisite: independent frontier questions may proceed, but
dependent questions wait for the result.

## Ask Style

The interview and all design decisions remain in the attended main session.
Only the factual or environment research described above may be delegated.

Ask open-ended grilling questions conversationally.

For concrete decision points with 2-4 choices, use whichever structured question
tool exists in the current surface:

- Claude Code: `AskUserQuestion`
- Codex CLI/App: `ask_user_question`
- Antigravity CLI: `ask_question`

If no structured question tool exists, ask conversationally with numbered
options. Do not add an explicit "Other" option for Antigravity; its UI already
supplies one.

The session is done when the frontier is empty: every branch has been visited
and nothing remains silently assumed. Do not act on the plan until the user
confirms shared understanding.

Under `/goal`, `codex exec`, scheduled runs, or other unattended contexts, skip
the interview and state that grilling requires an attended main session.
