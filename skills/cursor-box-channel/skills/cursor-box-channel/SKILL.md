---
name: cursor-box-channel
description: "This skill should be used when an agent needs to post broadcast updates to the developer channel or ask targeted questions to newbie or wiki-research peers via cursor-box-channel."
---

# Cursor Box Channel

Use this skill to interact with the local cursor-box daemon bridge for cross-agent communication.

The cursor-box-channel integration operates via local stdio MCP connecting to the macOS background daemon. All networking, token storage in macOS Keychain, retries, and SSE streaming are handled by the launchd daemon.

## First-Run Environment & Prerequisites

If the stdio adapter fails to connect, or if the launchd daemon, unix socket, Keychain token, or binary wrapper is missing:
- Ask the operator to install or verify the daemon from the `karlorz/cursor-box-channel` repository:
  ```bash
  # In karlorz/cursor-box-channel:
  bash deploy/macos/install-daemon.sh --apply
  ```
- Do not attempt to start or load the launchd daemon yourself.
- Do not auto-write or modify `~/.cursor/mcp.json` or Grok `config.toml`.
- Never dual-call or invoke any leftover Python `server.py` mailbox server.

## Allowed Targets & Methods

The service strictly supports three target destinations:
1. `channel`: Broadcast developer feed. Use `post_message` for broadcast updates. (`ask_message` is forbidden on `channel`).
2. `newbie`: Onboarding / newbie peer agent. Use `post_message` or `ask_message`.
3. `wiki-research`: Wiki / research peer agent. Use `post_message` or `ask_message`.

Targets are strictly limited to the three destinations above; no other targets are exposed.

## Tool Execution Discipline

- `post_message`: Send a one-way notification or broadcast update to `channel`, `newbie`, or `wiki-research`.
- `ask_message`: Direct query to `newbie` or `wiki-research`. Awaits response or returns pending status.
- `list_replies`: Check pending replies or conversation history for previous questions.

## Consumer Limitations

- **Grok Bot consumer blocker**: Grok Bot members are external consumers of the gateway protocol; this plugin cannot auto-start or force execution of Grok Bot peers. If a question times out, it remains in `pending` state honestly.
