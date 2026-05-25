---
name: hermes-cli
version: "1.0.0"
description: Hermes Agent CLI commands reference. Use when the user asks about hermes-agent CLI usage, commands, flags, or subcommands. Covers the full hermes terminal command surface.
argument-hint: "[command-family]"
---

# Hermes Agent CLI Reference

Authoritative reference for Hermes terminal commands. For in-chat slash commands, see the Hermes docs slash-commands page.

Source: https://github.com/NousResearch/hermes-agent/blob/main/website/docs/reference/cli-commands.md

## Global entrypoint

```bash
hermes [global-options] <command> [subcommand/options]
```

### Global options

| Option | Description |
|--------|-------------|
| `--version`, `-V` | Show version and exit. |
| `--profile <name>`, `-p <name>` | Select which Hermes profile to use. Overrides the sticky default from `hermes profile use`. |
| `--resume <session>`, `-r <session>` | Resume a previous session by ID or title. |
| `--continue [name]`, `-c [name]` | Resume the most recent session, or most recent matching a title. |
| `--worktree`, `-w` | Start in an isolated git worktree for parallel-agent workflows. |
| `--yolo` | Bypass dangerous-command approval prompts. |
| `--pass-session-id` | Include the session ID in the agent's system prompt. |
| `--ignore-user-config` | Ignore `~/.hermes/config.yaml` and fall back to built-in defaults. Credentials in `.env` are still loaded. |
| `--ignore-rules` | Skip auto-injection of `AGENTS.md`, `SOUL.md`, `.cursorrules`, memory, and preloaded skills. |
| `--tui` | Launch the TUI instead of the classic CLI. Equivalent to `HERMES_TUI=1`. |
| `--dev` | With `--tui`: run TypeScript sources directly via `tsx` (for TUI contributors). |

## Top-level commands

| Command | Purpose |
|---------|---------|
| `hermes chat` | Interactive or one-shot chat with the agent. |
| `hermes model` | Interactively choose the default provider and model. |
| `hermes fallback` | Manage fallback providers tried when the primary model errors. |
| `hermes gateway` | Run or manage the messaging gateway service. |
| `hermes setup` | Interactive setup wizard for all or part of the configuration. |
| `hermes whatsapp` | Configure and pair the WhatsApp bridge. |
| `hermes slack` | Slack helpers (generate app manifest with every command as native slash). |
| `hermes auth` | Manage credentials — add, list, remove, reset, set strategy. Handles OAuth flows. |
| `hermes status` | Show agent, auth, and platform status. |
| `hermes cron` | Inspect and tick the cron scheduler. |
| `hermes kanban` | Multi-profile collaboration board (tasks, links, dispatcher). |
| `hermes webhook` | Manage dynamic webhook subscriptions for event-driven activation. |
| `hermes hooks` | Inspect, approve, or remove shell-script hooks declared in config. |
| `hermes doctor` | Diagnose config and dependency issues. |
| `hermes dump` | Copy-pasteable setup summary for support/debugging. |
| `hermes debug` | Debug tools — upload logs and system info for support. |
| `hermes backup` | Back up Hermes home directory to a zip file. |
| `hermes checkpoints` | Inspect/prune/clear `~/.hermes/checkpoints/` (shadow store for `/rollback`). |
| `hermes import` | Restore a Hermes backup from a zip file. |
| `hermes logs` | View, tail, and filter agent/gateway/error log files. |
| `hermes config` | Show, edit, migrate, and query configuration files. |
| `hermes pairing` | Approve or revoke messaging pairing codes. |
| `hermes skills` | Browse, install, publish, audit, and configure skills. |
| `hermes curator` | Background skill maintenance — status, run, pause, pin. |
| `hermes memory` | Configure external memory provider. |
| `hermes acp` | Run Hermes as an ACP server for editor integration. |
| `hermes mcp` | Manage MCP server configurations and run Hermes as an MCP server. |
| `hermes plugins` | Manage Hermes Agent plugins (install, enable, disable, remove). |
| `hermes tools` | Configure enabled tools per platform. |
| `hermes sessions` | Browse, export, prune, rename, and delete sessions. |
| `hermes insights` | Show token/cost/activity analytics. |
| `hermes claw` | OpenClaw migration helpers. |
| `hermes dashboard` | Launch the web dashboard for managing config, API keys, and sessions. |
| `hermes profile` | Manage profiles — multiple isolated Hermes instances. |
| `hermes completion` | Print shell completion scripts (bash/zsh/fish). |
| `hermes version` | Show version information. |
| `hermes update` | Pull latest code and reinstall dependencies. |
| `hermes uninstall` | Remove Hermes from the system. |

---

## `hermes chat`

```bash
hermes chat [options]
```

| Option | Description |
|--------|-------------|
| `-q`, `--query "..."` | One-shot, non-interactive prompt. |
| `-m`, `--model <model>` | Override the model for this run. |
| `-t`, `--toolsets <list>` | Enable a comma-separated set of toolsets. |
| `--provider <name>` | Force a provider: `auto`, `openrouter`, `nous`, `openai-codex`, `copilot-acp`, `copilot`, `anthropic`, `gemini`, `google-gemini-cli`, `huggingface`, `zai`, `kimi-coding`, `kimi-coding-cn`, `minimax`, `minimax-cn`, `minimax-oauth`, `kilocode`, `xiaomi`, `arcee`, `gmi`, `alibaba`, `alibaba-coding-plan`, `deepseek`, `nvidia`, `ollama-cloud`, `xai` (alias `grok`), `qwen-oauth`, `bedrock`, `opencode-zen`, `opencode-go`, `ai-gateway`, `azure-foundry`, `tencent-tokenhub`. |
| `-s`, `--skills <list>` | Preload one or more skills for the session (repeatable or comma-separated). |
| `-v`, `--verbose` | Verbose output. |
| `-Q`, `--quiet` | Programmatic mode: suppress banner/spinner/tool previews. |
| `--image <path>` | Attach a local image to a single query. |
| `--resume <id>` / `--continue [name]` | Resume a session directly from chat. |
| `--worktree` | Create an isolated git worktree for this run. |
| `--checkpoints` | Enable filesystem checkpoints before destructive file changes. |
| `--yolo` | Skip approval prompts. |
| `--pass-session-id` | Pass the session ID into the system prompt. |
| `--ignore-user-config` | Ignore `~/.hermes/config.yaml` and use built-in defaults. |
| `--ignore-rules` | Skip auto-injection of `AGENTS.md`, `SOUL.md`, `.cursorrules`, persistent memory, and preloaded skills. |
| `--source <tag>` | Session source tag for filtering (default: `cli`). Use `tool` for third-party integrations. |
| `--max-turns <n>` | Maximum tool-calling iterations per conversation turn (default: 90). |

### `hermes -z <prompt>` — scripted one-shot

Pure one-shot entry: single prompt in, final response text out, nothing else on stdout/stderr. No banner, no spinner, no tool previews. Designed for shell scripts, CI, cron, and pipe-based workflows.

```bash
hermes -z "What's the capital of France?"
answer=$(hermes -z "summarize this" < /path/to/file.txt)
```

Per-run overrides (no mutation to config):

| Flag | Equivalent env var | Purpose |
|------|---|---|
| `-m` / `--model <id>` | `HERMES_INFERENCE_MODEL` | Override the model for this run |
| `--provider <name>` | `HERMES_INFERENCE_PROVIDER` | Override the provider for this run |

### Examples

```bash
hermes
hermes chat -q "Summarize the latest PRs"
hermes chat --provider openrouter --model anthropic/claude-sonnet-4.6
hermes chat --toolsets web,terminal,skills
hermes chat --quiet -q "Return only JSON"
hermes chat --worktree -q "Review this repo and open a PR"
hermes chat --ignore-user-config --ignore-rules -q "Repro without my personal setup"
```

---

## `hermes model`

Interactive provider + model selector. **This is the command for adding new providers, setting up API keys, and running OAuth flows.** Run from your terminal — not inside an active Hermes chat session.

```bash
hermes model
```

### `/model` slash command (mid-session)

Switch between already-configured models without leaving a session:

```
/model                          # Show current model and available options
/model claude-sonnet-4          # Switch model (auto-detects provider)
/model zai:glm-5                # Switch provider and model
/model custom:qwen-2.5          # Use model on your custom endpoint
/model custom                   # Auto-detect model from custom endpoint
/model custom:local:qwen-2.5   # Use a named custom provider
/model openrouter:anthropic/claude-sonnet-4  # Switch back to cloud
/model claude-sonnet-4 --global # Switch and save as new default
```

---

## `hermes gateway`

```bash
hermes gateway <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `run` | Run the gateway in the foreground. Recommended for WSL, Docker, and Termux. |
| `start` | Start the installed systemd/launchd background service. |
| `stop` | Stop the service (or foreground process). |
| `restart` | Restart the service. |
| `status` | Show service status. |
| `install` | Install as a systemd (Linux) or launchd (macOS) background service. |
| `uninstall` | Remove the installed service. |
| `setup` | Interactive messaging-platform setup. |

| Option | Description |
|--------|-------------|
| `--all` | On `start`/`restart`/`stop`: act on every profile's gateway. |

---

## `hermes setup`

```bash
hermes setup [model|tts|terminal|gateway|tools|agent] [--non-interactive] [--reset] [--quick] [--reconfigure]
```

| Section | Description |
|---------|-------------|
| `model` | Provider and model setup. |
| `terminal` | Terminal backend and sandbox setup. |
| `gateway` | Messaging platform setup. |
| `tools` | Enable/disable tools per platform. |
| `agent` | Agent behavior settings. |

| Option | Description |
|--------|-------------|
| `--quick` | Only prompt for items that are missing or unset. |
| `--non-interactive` | Use defaults/environment values without prompts. |
| `--reset` | Reset configuration to defaults before setup. |
| `--reconfigure` | Backwards-compat alias — bare `hermes setup` on existing install now does this by default. |

---

## `hermes auth`

```bash
hermes auth                    # Interactive wizard
hermes auth list               # Show all pools
hermes auth list openrouter    # Show specific provider
hermes auth add openrouter --api-key sk-or-v1-xxx   # Add API key
hermes auth add anthropic --type oauth               # Add OAuth credential
hermes auth remove openrouter 2                       # Remove by index
hermes auth reset openrouter                          # Clear cooldowns
```

Subcommands: `add`, `list`, `remove`, `reset`. No subcommand launches the interactive wizard.

---

## `hermes status`

```bash
hermes status [--all] [--deep]
```

| Option | Description |
|--------|-------------|
| `--all` | Show all details in a shareable redacted format. |
| `--deep` | Run deeper checks that may take longer. |

---

## `hermes cron`

```bash
hermes cron <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `list` | Show scheduled jobs. |
| `create` / `add` | Create a scheduled job from a prompt (optionally `--skill`). |
| `edit` | Update a job's schedule, prompt, name, delivery, repeat count, or skills. |
| `pause` | Pause a job without deleting it. |
| `resume` | Resume a paused job and compute next run. |
| `run` | Trigger a job on the next scheduler tick. |
| `remove` | Delete a scheduled job. |
| `status` | Check whether the cron scheduler is running. |
| `tick` | Run due jobs once and exit. |

---

## `hermes kanban`

```bash
hermes kanban [--board <slug>] <action> [options]
```

Multi-profile collaboration board with its own SQLite DB per board.

| Action | Purpose |
|--------|---------|
| `init` | Create `kanban.db` if missing. |
| `boards list` / `boards ls` | List all boards with task counts. |
| `boards create <slug>` | Create a new board. Flags: `--name`, `--description`, `--icon`, `--color`, `--switch`. |
| `boards switch <slug>` | Set active board. |
| `boards show` | Print currently-active board info. |
| `boards rename <slug> "name"` | Change display name. Slug is immutable. |
| `boards rm <slug>` | Archive (default) or `--delete` to hard-delete. |
| `create "title"` | Create a task. Flags: `--body`, `--assignee`, `--parent`, `--workspace`, `--tenant`, `--priority`, `--triage`, `--idempotency-key`, `--max-runtime`, `--skill`. |
| `list` / `ls` | List tasks. Filter: `--mine`, `--assignee`, `--status`, `--tenant`, `--archived`, `--json`. |
| `show <id>` | Show task with comments/events. `--json` for machine output. |
| `assign <id> <profile>` | Assign or reassign. Use `none` to unassign. |
| `link <parent> <child>` | Add a dependency (cycle-detected). |
| `unlink <parent> <child>` | Remove a dependency. |
| `claim <id>` | Atomically claim a ready task. |
| `comment <id> "text"` | Append a comment. |
| `complete <id>` | Mark done. Flags: `--result`, `--summary`, `--metadata`. |
| `block <id> "reason"` | Mark blocked (also appends reason as comment). |
| `unblock <id>` | Return blocked task to ready. |
| `archive <id>` | Hide from default list. |
| `tail <id>` | Follow task's event stream. |
| `dispatch` | One dispatcher pass. Flags: `--dry-run`, `--max N`, `--json`. |
| `context <id>` | Print full worker context. |
| `gc` | Remove scratch workspaces for archived tasks. |

---

## `hermes webhook`

```bash
hermes webhook <subscribe|list|remove|test>
```

| Subcommand | Description |
|------------|-------------|
| `subscribe` / `add` | Create a webhook route. |
| `list` / `ls` | Show all agent-created subscriptions. |
| `remove` / `rm` | Delete a dynamic subscription. |
| `test` | Send a test POST to verify a subscription. |

### `hermes webhook subscribe` options

| Option | Description |
|--------|-------------|
| `--prompt` | Prompt template with `{dot.notation}` payload references. |
| `--events` | Comma-separated event types to accept. Empty = all. |
| `--description` | Human-readable description. |
| `--skills` | Comma-separated skill names to load. |
| `--deliver` | Delivery target: `log` (default), `telegram`, `discord`, `slack`, `github_comment`. |
| `--deliver-chat-id` | Target chat/channel ID for cross-platform delivery. |
| `--secret` | Custom HMAC secret. Auto-generated if omitted. |
| `--deliver-only` | Skip the agent — deliver rendered prompt as literal message. Zero LLM cost. |

---

## `hermes doctor`

```bash
hermes doctor [--fix]
```

---

## `hermes dump`

```bash
hermes dump [--show-keys]
```

Outputs a compact plain-text setup summary for sharing. `--show-keys` shows redacted API key prefixes.

---

## `hermes debug`

```bash
hermes debug share [--lines N] [--expire days] [--local]
```

Upload debug report (system info + recent logs) to a paste service and get a shareable URL.

---

## `hermes backup`

```bash
hermes backup [-o path] [-q] [-l label]
```

| Option | Description |
|--------|-------------|
| `-o`, `--output <path>` | Output path for the zip file. Default: `~/hermes-backup-<timestamp>.zip`. |
| `-q`, `--quick` | Quick snapshot: only critical state files. Much faster. |
| `-l`, `--label <name>` | Label for the snapshot (only with `--quick`). |

---

## `hermes checkpoints`

```bash
hermes checkpoints [subcommand]
```

| Subcommand | Description |
|------------|-------------|
| `status` (default) | Show total size, project count, and breakdown. |
| `list` | Alias for `status`. |
| `prune` | Force cleanup — delete orphan/stale projects, GC the store. |
| `clear` | Delete entire checkpoint base. Irreversible (asks confirm unless `-f`). |
| `clear-legacy` | Delete only v1 migration archives. |

| Option | Description |
|--------|-------------|
| `--limit N` | Max projects to list (default 20). |
| `--retention-days N` | Drop projects older than N days (default 7). |
| `--max-size-mb N` | Drop oldest commits until total <= N MB (default 500). |
| `--keep-orphans` | Skip deleting projects whose working directory no longer exists. |
| `-f`, `--force` | Skip confirmation prompt. |

---

## `hermes import`

```bash
hermes import <zipfile> [-f]
```

Restore a Hermes backup. `--force` skips the confirmation prompt.

**Stop the gateway before importing to avoid conflicts.**

---

## `hermes logs`

```bash
hermes logs [log_name] [options]
```

| Name | File | What it captures |
|------|------|-----------------|
| `agent` (default) | `agent.log` | All agent activity — API calls, tool dispatch, session lifecycle |
| `errors` | `errors.log` | Warnings and errors only |
| `gateway` | `gateway.log` | Messaging gateway activity |

| Option | Description |
|--------|-------------|
| `-n`, `--lines <N>` | Number of lines (default: 50). |
| `-f`, `--follow` | Follow the log in real time (like `tail -f`). |
| `--level <LEVEL>` | Minimum log level: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`. |
| `--session <ID>` | Filter by session ID substring. |
| `--since <TIME>` | Show lines from relative time ago: `30m`, `1h`, `2d`. |
| `--component <NAME>` | Filter by component: `gateway`, `agent`, `tools`, `cli`, `cron`. |

---

## `hermes config`

```bash
hermes config <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `show` | Show current config values. |
| `edit` | Open `config.yaml` in your editor. |
| `set <key> <value>` | Set a config value. |
| `path` | Print the config file path. |
| `env-path` | Print the `.env` file path. |
| `check` | Check for missing or stale config. |
| `migrate` | Add newly introduced options interactively. |

---

## `hermes pairing`

```bash
hermes pairing <list|approve|revoke|clear-pending>
```

---

## `hermes skills`

```bash
hermes skills <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `browse` | Paginated browser for skill registries. |
| `search` | Search skill registries. |
| `install` | Install a skill. |
| `inspect` | Preview a skill without installing it. |
| `list` | List installed skills. |
| `check` | Check installed hub skills for upstream updates. |
| `update` | Reinstall hub skills with upstream changes. |
| `audit` | Re-scan installed hub skills. |
| `uninstall` | Remove a hub-installed skill. |
| `reset` | Un-stick a bundled skill flagged as `user_modified`. |
| `publish` | Publish a skill to a registry. |
| `snapshot` | Export/import skill configurations. |
| `tap` | Manage custom skill sources. |
| `config` | Interactive enable/disable configuration by platform. |

Common examples:

```bash
hermes skills browse
hermes skills search react --source skills-sh
hermes skills inspect official/security/1password
hermes skills install official/migration/openclaw-migration
hermes skills install https://sharethis.chat/SKILL.md   # Direct URL
hermes skills check
hermes skills update
hermes skills config
```

---

## `hermes curator`

```bash
hermes curator <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `status` | Show curator status and skill stats. |
| `run` | Trigger a curator review now. |
| `run --sync` | Block until the LLM pass finishes. |
| `run --dry-run` | Preview only — no mutations. |
| `backup` | Take a manual tar.gz snapshot of skills. |
| `rollback` | Restore skills from a snapshot. `--list` to see available. |
| `pause` | Pause the curator until resumed. |
| `resume` | Resume a paused curator. |
| `pin <skill>` | Pin a skill so curator never auto-transitions it. |
| `unpin <skill>` | Unpin a skill. |
| `restore <skill>` | Restore an archived skill. |

---

## `hermes fallback`

```bash
hermes fallback <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `list` (alias: `ls`) | Show current fallback chain. |
| `add` | Pick a provider + model and append to the chain. |
| `remove` (alias: `rm`) | Pick an entry to delete. |
| `clear` | Remove all fallback entries. |

---

## `hermes hooks`

```bash
hermes hooks <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `list` (alias: `ls`) | List configured hooks with matcher, timeout, and consent status. |
| `test <event>` | Fire every hook matching `<event>` against a synthetic payload. |
| `revoke` | Remove a command's allowlist entries. |
| `doctor` | Check each configured hook: exec bit, allowlist, mtime drift, JSON validity. |

---

## `hermes memory`

```bash
hermes memory <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `setup` | Interactive provider selection and configuration. |
| `status` | Show current memory provider config. |
| `off` | Disable external provider (built-in only). |

Available providers: honcho, openviking, mem0, hindsight, holographic, retaindb, byterover, supermemory. When an external provider is active, it may register its own `hermes <provider>` command.

---

## `hermes mcp`

```bash
hermes mcp <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `serve [-v]` | Run Hermes as an MCP server. |
| `add <name> [--url URL] [--command CMD] [--args ...] [--auth oauth|header]` | Add an MCP server. |
| `remove <name>` | Remove an MCP server from config. |
| `list` | List configured MCP servers. |
| `test <name>` | Test connection to an MCP server. |
| `configure <name>` | Toggle tool selection for a server. |

---

## `hermes plugins`

```bash
hermes plugins [subcommand]
```

| Subcommand | Description |
|------------|-------------|
| *(none)* | Composite interactive UI — general plugin toggles + provider plugin config. |
| `install <identifier> [--force]` | Install a plugin from Git URL or `owner/repo`. |
| `update <name>` | Pull latest changes for an installed plugin. |
| `remove <name>` | Remove an installed plugin. |
| `enable <name>` | Enable a disabled plugin. |
| `disable <name>` | Disable a plugin without removing it. |
| `list` | List installed plugins with status. |

---

## `hermes tools`

```bash
hermes tools [--summary]
```

`--summary` prints the enabled-tools summary and exits. Without it, launches the interactive per-platform tool configuration UI.

---

## `hermes sessions`

```bash
hermes sessions <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `list` | List recent sessions. |
| `browse` | Interactive session picker with search and resume. |
| `export <output> [--session-id ID]` | Export sessions to JSONL. |
| `delete <session-id>` | Delete one session. |
| `prune` | Delete old sessions. |
| `stats` | Show session-store statistics. |
| `rename <session-id> <title>` | Set or change a session title. |

---

## `hermes insights`

```bash
hermes insights [--days N] [--source platform]
```

---

## `hermes claw`

```bash
hermes claw migrate [options]
```

Migrate OpenClaw setup to Hermes.

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview without writing anything. |
| `--preset <name>` | `full` (all compatible settings) or `user-data` (excludes infra config). |
| `--overwrite` | Overwrite existing Hermes files on conflicts. |
| `--migrate-secrets` | Include API keys in migration. |
| `--no-backup` | Skip pre-migration zip snapshot. |
| `--source <path>` | Custom OpenClaw directory (default: `~/.openclaw`). |
| `--workspace-target <path>` | Target directory for workspace instructions. |
| `--skill-conflict <mode>` | Handle skill name collisions: `skip` (default), `overwrite`, or `rename`. |
| `--yes` | Skip confirmation prompt. |

---

## `hermes dashboard`

```bash
hermes dashboard [--port N] [--host addr] [--no-open]
```

Launch the web dashboard. Requires `pip install hermes-agent[web]`.

| Option | Default | Description |
|--------|---------|-------------|
| `--port` | `9119` | Port to run the web server on. |
| `--host` | `127.0.0.1` | Bind address. |
| `--no-open` | — | Don't auto-open the browser. |

---

## `hermes profile`

```bash
hermes profile <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `list` | List all profiles. |
| `use <name>` | Set a sticky default profile. |
| `create <name> [--clone] [--clone-all] [--clone-from <source>] [--no-alias]` | Create a new profile. |
| `delete <name> [-y]` | Delete a profile. |
| `show <name>` | Show profile details. |
| `alias <name> [--remove] [--name NAME]` | Manage wrapper scripts. |
| `rename <old> <new>` | Rename a profile. |
| `export <name> [-o FILE]` | Export to `.tar.gz`. |
| `import <archive> [--name NAME]` | Import from `.tar.gz`. |

Examples:

```bash
hermes profile list
hermes profile create work --clone
hermes profile use work
hermes profile alias work --name h-work
hermes -p work chat -q "Hello from work profile"
```

---

## `hermes completion`

```bash
hermes completion [bash|zsh|fish]
```

---

## `hermes update`

```bash
hermes update [--check] [--backup] [--restart-gateway]
```

| Option | Description |
|--------|-------------|
| `--check` | Print current vs latest commit. Does not pull or install. |
| `--backup` | Create pre-update snapshot of `HERMES_HOME`. |
| `--restart-gateway` | Restart the gateway after update. |

---

## `hermes uninstall`

```bash
hermes uninstall [--full] [--yes]
```

Remove Hermes. `--full` deletes all config/data.
