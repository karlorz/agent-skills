# cursor-box-channel

Thin marketplace plugin for cursor-box-channel, providing stdio MCP connectivity to the local macOS daemon bridge for cross-agent communication.

## Architecture

The plugin executes a lightweight stdio runner script that connects to the local `cursor-box-mcp` Node adapter installed by `karlorz/cursor-box-channel`:

```text
Grok / Cursor / Claude (stdio MCP)
       │
       ▼
  scripts/run-cursor-box-mcp.sh
       │
       ▼
  ~/Library/Application Support/cursor-box-channel/bin/cursor-box-mcp (Node adapter)
       │
       ▼ (unix domain socket)
  launchd daemon (com.karlchow.cursor-box-channel)
```

Networking, Keychain credentials, and remote gateway synchronization are entirely managed by the background launchd daemon.

## Installation & Setup

### Claude Code

Install from the `karlorz-agent-skills` marketplace catalog:

```bash
claude plugin install cursor-box-channel@karlorz-agent-skills
```

Plugin install does not write `~/.cursor/mcp.json` automatically.

### Prerequisites

Ensure the daemon and MCP adapter are installed on your macOS host from the `karlorz/cursor-box-channel` repository:

```bash
# In karlorz/cursor-box-channel:
bash deploy/macos/install-daemon.sh --apply
```

If the wrapper or daemon is missing, the runner fails with a clear error prompt directing the operator to install the daemon.

### Diagnostic Note on `agent mcp list`

`agent mcp list` inspects static `~/.cursor/mcp.json` configuration rather than plugin `.mcp.json` manifests. This is a known CLI diagnostic note and does not reflect runtime plugin MCP availability when third-party plugins are active.

For headless CLI sessions (`agent -p`) invoked without plugin flags, refer to `cursor-cli-mcp.example.json`.

## License

MIT
