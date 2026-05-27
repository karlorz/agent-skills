---
name: host-backup-restore
version: "3.6.1"
description: Host-level backup and restore with profile system (presets + custom YAML profiles), model-aware agents (sonnet worker for mechanical tasks), post-discovery research, and skillwiki infrastructure capture. Uses rsync with partial-dir for resumable WAN transfers. Use when backing up or restoring Caddy reverse-proxy domains, databases (postgres, mysql, redis, mongodb, sqlite), systemd services, SSH configs, and Hermes agent state on remote Linux hosts.
argument-hint: "[host] [mode] [options]"
---

# Host Backup Restore

Orchestrates host infrastructure backup and restore into a single flow: Caddy reverse-proxy domains, databases, systemd services, SSH configs, Hermes agent snapshots, and apt package lists.

Supports interactive (`AskUserQuestion`) mode (default), non-interactive CLI mode, backup profiles, post-discovery research, and skillwiki capture.

## Quick Start

```bash
# Interactive backup — runs discover.sh, presents profile selection, then AskUserQuestion
/host-backup-restore sg01

# With a specific profile
/host-backup-restore sg01 --profile quick

# Non-interactive: use a preset profile
bash scripts/host-backup-cli.sh --host sg01 --profile full

# Non-interactive: quick backup (hermes + databases + base + caddy)
bash scripts/host-backup-cli.sh --host sg01 --profile quick

# Save a custom profile for reuse
bash scripts/host-backup-cli.sh --host sg01 --groups "hermes,databases,caddy_domains" --save-profile daily

# List all available profiles
bash scripts/host-backup-cli.sh --list-profiles

# Backup with post-discovery research
bash scripts/host-backup-cli.sh --host sg01 --profile full --research

# Restore to a fresh host
bash scripts/host-restore-cli.sh --archive ./sg01-backup.tar.gz --target newhost --all
```

---

## Non-Root User Setup (Recommended)

By default, backup and restore operations use the non-root `agent` user for SSH. Root access is not required if the `agent` user has passwordless sudo.

### Prerequisite: Bootstrap the agent user

Run once per target host to create the `agent` user with passwordless sudo:

```bash
bash scripts/hermes/setup-remote-user.sh <host>
```

This connects as root (one-time bootstrap), creates the `agent` user, grants passwordless sudo, deploys your SSH key, and optionally writes an SSH config alias.

### How non-root works

The CLI scripts default to `agent@<host>` for SSH connections:

| Scenario | Result | Example |
|----------|--------|---------|
| Default (no flags) | `agent@<host>` | `ssh agent@sg01 "cmd"` |
| `--user root` | `root@<host>` | `ssh root@sg01 "cat /etc/caddy/Caddyfile"` |
| `--user deploy` | `deploy@<host>` | `ssh deploy@sg01 "cmd"` |
| `<host>-agent` alias | Uses SSH config | `ssh sg01-agent "cmd"` |

The `agent` user requires passwordless sudo for operations that write to system paths (e.g., `/etc/caddy/`, `/etc/hosts`, systemd services). The `setup-remote-user.sh` script configures this automatically.

### Specifying a user explicitly

```bash
# Backup as root (if needed for system-level operations)
bash scripts/host-backup-cli.sh --host sg01 --user root --profile full

# Backup as a specific non-root user
bash scripts/host-backup-cli.sh --host sg01 --user deploy --profile quick

# Restore to a target as non-root agent (default)
bash scripts/host-restore-cli.sh --archive ./backup.tar.gz --target newhost --all

# Restore as root
bash scripts/host-restore-cli.sh --archive ./backup.tar.gz --target newhost --user root --all

# Using SSH config alias (handles user/key/port in ~/.ssh/config)
bash scripts/host-backup-cli.sh --host sg01-agent --profile full
```

### Security

- After bootstrapping `agent` user, consider disabling root SSH login on the target host
- Passwordless sudo is required for non-interactive automation (systemd services, Caddy config)
- The agent user's SSH key is deployed from your local `~/.ssh/id_ed25519.pub` or a specified key

---

## Architecture

```
host-backup-restore/
├── SKILL.md                    # This file — interactive flow + orchestration
├── .claude-plugin/
│   ├── plugin.json             # Plugin manifest (v{{VERSION}})
│   └── agents/
│       ├── backup-worker.md    # Sonnet-pinned worker for general tasks
│       └── hermes-backup-worker.md  # Sonnet-pinned worker for Hermes ops
├── scripts/
│   ├── hermes/
│   │   ├── discover-hermes.sh      # Hermes-specific SSH discovery
│   │   ├── remote-backup.sh        # Remote Hermes backup orchestrator
│   │   ├── remote-restore.sh       # Remote Hermes restore via import
│   │   ├── pre-inspect.sh          # Restore target readiness check
│   │   ├── restore-validate.sh     # Post-restore Hermes validation
│   │   ├── prune-backups.sh        # Retention pruning
│   │   ├── setup-remote-user.sh    # Non-root user bootstrap
│   │   ├── setup-remote-cron.sh    # Automated backup cron
│   │   └── setup-nonroot-hermes.sh # Non-root Hermes installation
│   ├── discover.sh             # SSH discovery: parse Caddyfile, detect services
│   ├── backup-host.sh          # Mechanical backup script (reads manifest)
│   ├── host-backup-cli.sh      # Non-interactive CLI backup (profile-aware)
│   ├── host-restore-cli.sh     # Non-interactive CLI restore
│   ├── profiles.sh             # Profile management (presets + YAML)
│   └── research-host.sh        # Post-discovery research query generator
└── tests/
    └── test-restore.sh         # Per-component restore verification (27 assertions)
```

### Data flow

1. **discover.sh** connects via SSH, parses Caddyfile for domain→upstream mappings, detects running databases, finds sqlite files, enumerates systemd units. Outputs JSON manifest at `/tmp/host-backup-{hostname}-manifest.json`.
2. **profiles.sh** resolves profile name to groups + hermes-tier (built-in presets or user YAML).
3. **Interactive (this SKILL.md):** reads the manifest, presents profile/service selection to user via `AskUserQuestion`, then runs backup/restore based on selection.
4. **CLI (host-backup-cli.sh / host-restore-cli.sh):** reads manifest and accepts group selection via flags or `--profile`.
5. **backup-host.sh** reads manifest + selected groups, backs up each component to a tarball.
6. **research-host.sh** generates research queries from manifest for deep-research skill.
7. **test-restore.sh** validates functional correctness per component.

---

## Profile System

Backup profiles define which groups to back up and what hermes-tier to use. Three built-in presets plus unlimited custom profiles.

### Built-in Presets

| Profile | Groups | Hermes Tier | Use Case |
|---------|--------|-------------|----------|
| `full` | all 7 groups | full | Complete infrastructure backup (default) |
| `quick` | base, caddy_domains, hermes, databases | standard | Essential state — skips systemd units + apt |
| `minimal` | hermes | minimal | Hermes agent state only — fastest snapshot |

### Custom Profiles

Create `~/.config/host-backup-restore/profiles.yaml`:

```yaml
profiles:
  daily:
    groups: [hermes, databases, base, caddy_domains]
    hermes_tier: full
    description: "Daily backup of essential services"
  weekly-full:
    groups: [base, caddy_domains, hermes, databases, other_services, apt]
    hermes_tier: full
    description: "Weekly full infrastructure backup"
  hermes-only:
    groups: [hermes]
    hermes_tier: minimal
    description: "Quick Hermes snapshot before upgrades"
```

### CLI Profile Flags

| Flag | Description |
|------|-------------|
| `--profile NAME` | Use a named profile (preset or custom) |
| `--save-profile NAME` | Save current `--groups` + `--hermes-tier` as a named profile |
| `--list-profiles` | List all available profiles and exit |

### Interactive Profile Selection

In interactive mode, after discovery, present profile selection before group selection:

```json
{
  "question": "Which backup profile for <host>?",
  "header": "Profile",
  "options": [
    {"label": "full (Recommended)", "description": "All 7 groups — complete infrastructure backup"},
    {"label": "quick", "description": "Essential state: Hermes, databases, Caddy, base (skips systemd + apt)"},
    {"label": "minimal", "description": "Hermes agent state only — fastest snapshot"},
    {"label": "Custom", "description": "Select individual groups manually"}
  ]
}
```

If "Custom" is selected, fall back to the per-group `AskUserQuestion` flow (Step 4b).

---

## Model-Aware Agents

The skill uses a **sonnet-pinned worker agent** for mechanical tasks, keeping the orchestrator (main session) for user interaction and decision-making.

### Agent: backup-worker (model: sonnet)

Defined in `agents/backup-worker.md`. Handles:
- SSH discovery (`discover.sh`)
- Backup execution (`backup-host.sh`)
- Restore execution (`host-restore-cli.sh`)
- Post-restore validation (`test-restore.sh`)
- Profile resolution (`profiles.sh`)

### Orchestration Flow

```
User Session (opus/inherit)
  ├── Interactive decisions (AskUserQuestion)
  ├── Profile selection
  ├── Post-discovery research (deep-research skill)
  ├── Skillwiki capture
  ├── Spawns backup-worker (sonnet)
  │     ├── discover.sh
  │     ├── backup-host.sh
  │     ├── host-restore-cli.sh
  │     └── test-restore.sh
  └── Spawns hermes-backup-worker (sonnet)
        ├── discover-hermes.sh
        ├── remote-backup.sh
        ├── remote-restore.sh
        ├── pre-inspect.sh
        ├── restore-validate.sh
        └── prune-backups.sh
```

**When to spawn backup-worker:**
- After user has made all decisions (profile, groups, mode)
- For the mechanical backup/restore execution
- For post-restore validation

**When to stay in orchestrator:**
- User interaction (AskUserQuestion)
- Profile design and custom profile management
- Deep research on detected services
- Skillwiki knowledge capture

---

## Interactive Mode (Default)

Entry point: `/host-backup-restore [host] [mode] [options]`

Arguments:
- `host` — SSH hostname (e.g. sg01, sg03, ptcloud). Required.
- `mode` — `backup` (default) or `restore`. Optional.
- `--profile NAME` — Use a named profile. Optional.
- `--redetect` — Re-run discovery instead of using cached manifest.
- `--dest PATH` — Backup destination directory.
- `--dry-run` — Preview what would be backed up without doing it.
- `--research` — Run post-discovery research. Optional.

### Step 1 — Run discovery

Run `discover.sh` to detect all services on the target host:

```bash
SCRIPT_DIR="$(dirname "$(realpath "$0")") 2>/dev/null || echo /path/to/skill"
bash "$SCRIPT_DIR/scripts/discover.sh" <host>
```

Discovery output is cached at `/tmp/host-backup-{hostname}-manifest.json`. Use `--redetect` to force re-run.

**Model note:** Spawn `backup-worker` agent for discovery to use sonnet for the SSH-heavy work.

### Step 2 — Present discovered services

Read the manifest and present the detected services to the user with a table. Example for sg01:

```
Detected services on sg01:
- Caddy domains: mon.karldigi.dev, status.karldigi.dev, term.karldigi.dev, bot.karldigi.dev, star.karldigi.dev (5 total)
- Hermes: v0.13.0 at /root/.hermes
- Databases: sqlite files (/root/.hermes/state.db, etc.), [redis/postgres/mysql as detected]
- Systemd services: hermes-gateway, hermes-dashboard, caddy, filebrowser, obsidian, xvfb, [others]
- Apt sources: deb https://... (N sources)
```

### Step 3 — Profile selection (AskUserQuestion)

Use `AskUserQuestion` with profile options:

```json
{
  "question": "Which backup profile for <host>?",
  "header": "Profile",
  "options": [
    {"label": "full (Recommended)", "description": "All 7 groups — complete infrastructure backup"},
    {"label": "quick", "description": "Essential state: Hermes, databases, Caddy, base (skips systemd + apt)"},
    {"label": "minimal", "description": "Hermes agent state only — fastest snapshot"},
    {"label": "Custom", "description": "Select individual groups manually"}
  ]
}
```

If a `--profile` flag was passed, skip this step and use the specified profile.

### Step 4a — Preset profile path (full/quick/minimal)

Resolve the profile via `profiles.sh` and run backup with the resolved groups:

```bash
source "$SCRIPT_DIR/scripts/profiles.sh"
resolve_profile "<profile_name>"
bash "$SCRIPT_DIR/scripts/backup-host.sh" "$MANIFEST_FILE" $PROFILE_GROUPS
```

### Step 4b — Custom / "Select individually" path

For each detected group, use `AskUserQuestion` (yes/no). Iterate through groups one at a time. Only ask about groups that have detected services:

```json
{
  "question": "Back up <group_name>? (<brief_description_of_what_this_covers>)",
  "header": "Service group",
  "options": [
    {"label": "Yes", "description": "Include this group in the backup"},
    {"label": "No", "description": "Skip this group"}
  ]
}
```

**Group order and descriptions:**

| Group | Description | Detected on sg01 example |
|-------|------------|--------------------------|
| `base` | SSH config, hostname, `/etc/hosts`, SSL certs | hostname, /etc/hosts |
| `caddy_domains` | Caddy config (`/etc/caddy/Caddyfile`), SSL certs, `caddy validate` | 5 domains: mon, status, term, bot, star |
| `hermes` | `hermes backup` (built-in zip — handles SQLite WAL mode) | v0.13.0 at /root/.hermes |
| `databases` | sqlite files, postgres/mysql/redis dumps, mongodb | state.db, [any others detected] |
| `other_services` | systemd unit files, service states | hermes-gateway, hermes-dashboard, caddy, filebrowser, obsidian, xvfb, [others] |
| `apt` | Package list (`apt list --installed`), apt sources | N sources |
| `wiki` | rclone S3 mount for wiki vault (`~/wiki` backed by cloud:cloud/wiki) | rclone.conf, ~/wiki mount |

After collecting all answers, run backup-host.sh with the selected groups:

```bash
bash "$SCRIPT_DIR/scripts/backup-host.sh" "$MANIFEST" <selected_group1> <selected_group2> ...
```

Offer to save the selection as a custom profile:

```json
{
  "question": "Save this selection as a custom profile for future use?",
  "header": "Save profile",
  "options": [
    {"label": "Yes", "description": "Save as a named profile in ~/.config/host-backup-restore/profiles.yaml"},
    {"label": "No", "description": "Continue without saving"}
  ]
}
```

### Step 4c — "Restore" path

1. **List available backups:** Check `~/Desktop/backups/<host>/` for existing archives.
2. **AskUserQuestion to select archive:**

```json
{
  "question": "Which backup archive do you want to restore from?",
  "header": "Restore archive",
  "options": [
    {"label": "backup-20260510-143000.tar.gz (78M, 2026-05-10)", "description": "Full backup with 54 files"},
    {"label": "backup-20260509-120000.tar.gz (45M, 2026-05-09)", "description": "Partial backup"},
    {"label": "Custom path", "description": "Specify a different archive path"}
  ]
}
```

3. **AskUserQuestion for groups to restore** (same per-group yes/no pattern as Step 4b).

**If `caddy_domains` was selected and Caddy is not on the target:**

Check if Caddy exists on the target:

```bash
ssh <target> "which caddy 2>/dev/null || echo MISSING"
```

If MISSING, prompt the user:

```json
{
  "question": "Caddy is not installed on <target>. Should I install it before restoring Caddy config?",
  "header": "Caddy install",
  "options": [
    {"label": "Yes (Recommended)", "description": "Install caddy via apt-get on the target, then restore config and restart the service"},
    {"label": "No", "description": "Restore config files only — Caddy won't serve domains until manually installed"}
  ]
}
```

If yes, run: `ssh <target> "sudo apt-get install -y caddy"`

**Check wiki S3 mount status on target:**

```bash
ssh <target> "df -T ~/wiki 2>/dev/null | grep -q fuse.rclone && echo 'MOUNTED' || echo 'MISSING'"
```

If MISSING, check FUSE availability:

```bash
ssh <target> "test -c /dev/fuse && echo 'FUSE_OK' || echo 'NO_FUSE'"
```

If `FUSE_OK`, prompt:

```json
{
  "question": "Wiki S3 mount is not active on <target>. Should I set it up?",
  "header": "Wiki mount",
  "options": [
    {"label": "Yes (Recommended)", "description": "Restore rclone.conf from backup and mount wiki at ~/wiki"},
    {"label": "No", "description": "Skip — wiki will not be available on this host until manually mounted"}
  ]
}
```

If yes, run the wiki restore group via: `bash scripts/host-restore-cli.sh --archive <path> --target <host> --groups wiki`

If `NO_FUSE`, inform the user with fix guidance:

```markdown
FUSE is not available on this host. The wiki S3 mount cannot be set up.

Fix options:
1. **LXC template (best):** Add `features: fuse=1` to the PVE base template
2. **LXC per-container:** Set `fuse=1` on the container features in PVE
3. **tmpfiles.d:** Create `/etc/tmpfiles.d/fuse.conf` with `c /dev/fuse 0666 root root - 10:229`

After FUSE is available, re-run the restore with `--groups wiki`.
```

4. Run restore:

```bash
bash "$SCRIPT_DIR/scripts/host-restore-cli.sh" --archive <archive_path> --target <host> --groups <selected_groups>
```

**Restore best practices (from vault research):**
- **Stop gateway before importing** — `ssh <host> "systemctl --user stop hermes-gateway.service"` to avoid conflicts with running processes. ^[queries/hermes-backup-validation-restore-preinspection.md]
- **Check distro compatibility** — Restoring apt sources across different distros (Debian→Ubuntu) breaks apt. Always verify source/target OS match.
- **SQLite WAL mode** — Naively copying a SQLite DB with active WAL mode misses `-wal`/`-shm` files. The `hermes backup` command handles this correctly. For manual sqlite files, use `.backup` command.
- **Post-restore validation** — Run the test harness to verify:

```bash
bash "$SCRIPT_DIR/tests/test-restore.sh" --manifest /tmp/host-backup-<host>-manifest.json
```

### Step 5 — Archiving

Tarball the backup directory:

```bash
cd "$(dirname "$BACKUP_DIR")"
tar czf "<host>-backup-$(date +%Y%m%d-%H%M%S).tar.gz" "$(basename "$BACKUP_DIR")"
```

### Step 6 — Skillwiki Capture (Optional)

After backup completes, offer to capture the host infrastructure snapshot to skillwiki:

```json
{
  "question": "Capture host infrastructure snapshot to skillwiki?",
  "header": "Wiki capture",
  "options": [
    {"label": "Yes", "description": "Write infrastructure snapshot to skillwiki vault as a typed-knowledge page"},
    {"label": "No", "description": "Skip wiki capture"}
  ]
}
```

If yes, use the `wiki-add-task` or `wiki-crystallize` skill to capture:

```bash
# Capture as a typed-knowledge page
skillwiki wiki-crystallize --type entity --title "Host: <hostname>" --content "
## Infrastructure Snapshot (<date>)

**Hostname:** <hostname>
**OS:** <os_id> <os_version>
**Caddy domains:** <domain_list>
**Hermes:** <version> at <home>
**Databases:** <db_summary>
**Systemd services:** <service_list>
**Apt sources:** <source_count> sources
**Profile used:** <profile_name>
**Backup archive:** <archive_path>
"
```

This creates a point-in-time record of host infrastructure that can be queried later for drift detection or disaster recovery reference.

### Step 7 — Post-Discovery Research (Optional)

If `--research` flag is passed or user opts in, generate research queries and run deep-research:

```bash
bash "$SCRIPT_DIR/scripts/research-host.sh" "$MANIFEST_FILE" --output "/tmp/host-backup-${HOST}-research"
```

Then invoke the deep-research skill for high-priority queries:

```json
{
  "question": "Run post-discovery research on detected services?",
  "header": "Research",
  "options": [
    {"label": "Yes", "description": "Research Hermes version, OS security advisories, database backup best practices"},
    {"label": "No", "description": "Skip research and proceed with backup"}
  ]
}
```

Research topics generated from manifest:
- Hermes version changelog and known issues
- OS security advisories for detected distro/version
- Database backup best practices for detected DB types
- Caddy reverse proxy security and performance recommendations

---

## CLI Commands

### `host-backup-cli.sh`

Non-interactive backup for automation/cron/scripting.

```bash
bash scripts/host-backup-cli.sh [options]
```

| Option | Description |
|--------|-------------|
| `--host HOST` | SSH target hostname (required) |
| `--all` | Back up all available groups |
| `--groups "caddy_domains,hermes,databases"` | Specific group selection |
| `--profile NAME` | Use a backup profile (full, quick, minimal, or custom) |
| `--save-profile NAME` | Save current selection as a named profile |
| `--list-profiles` | List all available profiles and exit |
| `--hermes-tier minimal\|standard\|full` | Hermes backup tier |
| `--dest PATH` | Backup destination directory |
| `--dry-run` | Preview what would be backed up without doing it |
| `--redetect` | Re-run discovery instead of using cached manifest |
| `--research` | Run post-discovery research on detected services |

**Hermes tier mapping:**

- `minimal` → `hermes backup --quick` (config + state only)
- `standard` / `full` → `hermes backup` (no flags, full zip — handles SQLite WAL mode)

> **Important:** `hermes backup` does NOT support `--tier`. Using `--tier` causes a silent error that produces no backup zip. Use `--quick` instead.

```bash
# Examples
bash scripts/host-backup-cli.sh --host sg01 --profile full
bash scripts/host-backup-cli.sh --host sg01 --profile quick --research
bash scripts/host-backup-cli.sh --host sg01 --groups "caddy_domains,hermes" --save-profile web-only
bash scripts/host-backup-cli.sh --host sg01 --all --hermes-tier minimal --dest ~/backups
bash scripts/host-backup-cli.sh --list-profiles
```

### `host-restore-cli.sh`

Non-interactive restore from a backup archive.

```bash
bash scripts/host-restore-cli.sh [options]
```

| Option | Description |
|--------|-------------|
| `--archive PATH` | Backup archive path (`.tar.gz`) |
| `--groups "caddy_domains,databases"` | Groups to restore |
| `--target HOST` | Target host for restore |
| `--all` | Restore all groups |
| `--dry-run` | Preview restore actions without executing |
| `--db-user USER` | Database username for pg_restore/mysql (default: postgres/root) |
| `--db-pass PASS` | Database password for mysql (passed securely via temp file) |
| `--allow-cross-distro` | Allow apt restore across different OS (default: skip on mismatch) |

```bash
# Examples
bash scripts/host-restore-cli.sh --archive ./sg01-backup.tar.gz --target newhost --all
bash scripts/host-restore-cli.sh --archive ./sg01-backup.tar.gz --target newhost --groups "caddy_domains,hermes" --dry-run
```

---

## Discovery

Cached manifest at `/tmp/host-backup-{hostname}-manifest.json`. Use `--redetect` to re-run.

**discover.sh** connects via SSH and detects:
- Caddyfile (`/etc/caddy/Caddyfile`) — domain names and upstream targets (via `caddy adapt` + JSON extraction with legacy fallback)
- Systemctl — service states (`systemctl is-active`, `systemctl list-units`)
- Database sockets — postgres, mysql, redis, mongodb listener detection + database name enumeration
- File system — sqlite `.db` files, installed packages, apt sources
- Hermes — version, HERMES_HOME path
- OS release — distro ID and version (for restore compatibility)

### Example output (from sg01)

```json
{
  "hostname": "sg01",
  "timestamp": "2026-05-10T14:30:00Z",
  "caddy_domains": [
    {"domain": "mon.karldigi.dev", "upstream": "localhost:3000"},
    {"domain": "status.karldigi.dev", "upstream": "localhost:3001"},
    {"domain": "term.karldigi.dev", "upstream": "localhost:8080"},
    {"domain": "bot.karldigi.dev", "upstream": "localhost:7456"},
    {"domain": "star.karldigi.dev", "upstream": ""}
  ],
  "hermes": {"version": "0.13.0", "home": "/root/.hermes"},
  "databases": {"sqlite": ["/root/.hermes/state.db"], "redis": ["6379"]},
  "other_services": [
    "hermes-gateway", "hermes-dashboard", "caddy",
    "filebrowser", "obsidian", "xvfb",
    "cmux-execd", "cmux-proxy", "cmux-ide", "cmux-worker-daemon"
  ],
  "apt_sources": ["deb https://deb.debian.org/debian trixie main", "deb https://deb.debian.org/debian trixie-updates main"],
  "os": "debian",
  "os_version": "13"
}
```

---

## Restore Tests

The test harness validates functional correctness per component.

```bash
# Run all tests
bash tests/test-restore.sh --manifest /tmp/manifest.json

# Test a specific group only
bash tests/test-restore.sh --manifest /tmp/manifest.json --group caddy_domains
```

### Test matrix (27 assertions across 8 groups)

| Group | Assertions | What's verified |
|-------|-----------|-----------------|
| base | 3 | SSH config syntax, hostname match, hosts file integrity |
| caddy_domains | 4 | `caddy validate`, HTTP 200 on each domain, certs valid |
| per-domain | 3 | Each domain serves correctly |
| hermes | 4 | `hermes --version`, gateway active, dashboard loads, CLI works |
| databases | 4 | sqlite3 opens `.db`, row count > 0, postgres/mysql connection |
| other_services | 3 | systemd units active, ports listening |
| apt | 3 | `apt list --installed` includes expected packages |
| wiki | 3 | rclone.conf, wiki mount active, fstab entry |

### Known limitations (source-side)

The following test "failures" are source-side edge cases, not restore bugs:
- DNS resolution failure for Caddy domains (no public DNS pointing at test host)
- Database connection refused (locked DB during backup)
- Stopped services (not running on source during discovery)

---

## Hermes Integration

The skill integrates with `hermes backup` for Hermes-specific snapshots:

```bash
# Full backup (SQLite-safe, handles WAL mode)
hermes backup -o hermes-backup.zip

# Quick snapshot (config + state only)
hermes backup --quick

# Restore
hermes import hermes-backup.zip
```

### Hermes restore validation

After restoring Hermes to a target host, run this post-restore validation sequence:

1. **CLI health**: `hermes --version && hermes doctor`
2. **Systemd services**: `systemctl --user status hermes-gateway.service` and `sudo systemctl status hermes-dashboard.service`
3. **Health endpoint**: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8642/health` (expect 200)
4. **API verification**: `curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:8642/v1/models`
5. **Content check**: `du -sh ~/.hermes/state.db`, `ls ~/.hermes/skills/ | wc -l`, `cat ~/.hermes/cron/jobs.json`

> **Important:** Stop the gateway BEFORE importing: `systemctl --user stop hermes-gateway.service` ^[entities/hermes-backup-restore-guide.md]
> Also stop the dashboard if it's running as a system service: `sudo systemctl stop hermes-dashboard.service`

For full Hermes backup/restore reference, see the [[hermes-cli]] skill.

### Hermes Module (scripts/hermes/)

The `scripts/hermes/` directory contains Hermes-specific backup/restore scripts absorbed from the standalone `hermes-remote-backup` skill. These scripts handle the Hermes agent layer of host backup via the official Hermes CLI.

| Script | Purpose |
|--------|---------|
| `discover-hermes.sh` | SSH discovery specific to Hermes (version, home, services) |
| `remote-backup.sh` | Remote Hermes backup orchestrator (`hermes backup` / `--quick`) |
| `remote-restore.sh` | Remote Hermes restore via `hermes import` with service stop/start |
| `pre-inspect.sh` | Restore target readiness check (arch, Python, disk, SSH, Hermes) |
| `restore-validate.sh` | Post-restore Hermes service validation (doctor, health, API, systemd, cron) |
| `prune-backups.sh` | Retention pruning for local Hermes backup archives |
| `setup-remote-user.sh` | Bootstrap non-root automation user on target host |
| `setup-remote-cron.sh` | Set up automated backup cron on target host |
| `setup-nonroot-hermes.sh` | Install Hermes for non-root user on target host |

### Hermes Backup Worker Agent

The `hermes-backup-worker` agent (`model: sonnet`) orchestrates Hermes-specific mechanical tasks. It is spawned by the orchestrator (main session) for:

- **Backup flow**: `discover-hermes.sh` → `remote-backup.sh` → `prune-backups.sh`
- **Restore flow**: `pre-inspect.sh` → `remote-restore.sh` → `restore-validate.sh`
- **Setup flow**: `setup-remote-user.sh` → `setup-remote-cron.sh` → `setup-nonroot-hermes.sh`

**Spawn pattern in interactive mode:**

```
After user selects "hermes" group:
  → Spawn hermes-backup-worker (sonnet)
  → Agent runs: discover-hermes.sh → remote-backup.sh
  → Agent returns result summary
  → Orchestrator continues with next group or wiki capture
```

**Model specification:** Per [[concepts/claude-code-agent-model-specification]], the `model: sonnet` is set in the agent frontmatter (`agents/hermes-backup-worker.md`), not in `plugin.json` or `SKILL.md`. The Agent tool parameter can override at spawn time but defaults to the agent file setting.

> **Primary entry point:** The `hermes-backup-worker` agent is the recommended way to perform Hermes backup/restore operations. Use `Agent(subagent_type="hermes-backup-worker", ...)` instead of calling `scripts/hermes/` scripts directly. The agent handles script selection, error handling, and result reporting.

> **Performance note:** `hermes backup` on sg01 creates a ~2.2 GB zip via SSH. The transfer can take 10+ minutes over WAN. Consider:
> - Spawning `hermes-backup-worker` with `run_in_background: true` for non-blocking backup
> - Using `--profile minimal` or `--hermes-tier minimal` for faster snapshots
> - Running hermes backup directly on the host (`ssh sg01 "hermes backup -o backup.zip"`) for large transfers

---

## DevSH Testing

For automated restore testing on ephemeral VMs:

```bash
# Create a devsh VM (morph provider for sync support)
VM_ID=$(devsh start -p morph --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# Sync backup to VM
devsh sync "$VM_ID" ./backup-staging/

# Run test harness
devsh exec "$VM_ID" "bash /tmp/test-restore.sh --manifest /tmp/manifest.json"

# Clean up
devsh delete "$VM_ID"
```

> **Note:** devsh `pve-lxc` provider does NOT support `devsh sync` or direct SSH file transfer. Use `morph` provider for restore testing. For `pve-lxc`, use HTTP serve (`python3 -m http.server` + `curl`) as a workaround. ^[projects/agent-skills/compound/devsh-restore-testing.md]

---

## Restore Target Pre-Inspection

Before restoring to any target host, run pre-inspection to verify readiness: ^[queries/hermes-backup-validation-restore-preinspection.md]

```bash
# Architecture
ssh <host> "uname -m"       # Expect: aarch64 or x86_64

# OS compatibility (critical for apt restore)
ssh <host> "cat /etc/os-release"

# Python version (Hermes requires 3.10+)
ssh <host> "python3 --version"

# Disk space (2GB+ recommended)
ssh <host> "df -h ~"

# Hermes already installed?
ssh <host> "hermes --version 2>/dev/null || echo NOT_INSTALLED"

# SSH key auth confirmed
ssh -o BatchMode=yes <host> "hostname"
```

### devsh pve-lxc specific notes

- `devsh sync` NOT supported — use HTTP serve or morph provider
- `systemctl --user` FAILS (no user bus in LXC) — run gateway as system service or background process
- `devsh exec` works for all commands
- HTTP file transfer works (same 10.10.x.x/16 subnet)

#### File transfer methods (pve-lxc)

| Method | Works for | Limit | Command |
|--------|-----------|-------|---------|
| base64 + devsh exec | Text files, small binaries | ~32 KB (shell arg limit) | `B64=$(base64 < file); devsh exec "$LXC" "echo \$B64 \| base64 -d > /tmp/file"` |
| Chunked base64 | Any file size | Slower than HTTP for large files | `devsh_transfer "$VM_ID" backup.zip /tmp/backup.zip` (built into host-restore-cli.sh) |
| HTTP serve | Any file size | Requires HTTP server on local machine | `python3 -m http.server 8080 & curl -o /tmp/file http://10.10.x.1:8080/file` |
| SCP via sg01 bridge | Any file size | Requires sg01 as jump host | `rsync -avP file sg01:/tmp/; ssh sg01 "rsync -avP /tmp/file 10.10.1.123:/tmp/"` |

For backup archives larger than 32 KB (Caddy config, SSL certs, Hermes zip), use chunked base64, HTTP serve, or rsync bridge. The `devsh_transfer` helper in host-restore-cli.sh splits files into 30KB base64 chunks and reassembles on the remote side.

---

## Lessons Learned

1. **Bash JSON is fragile** — Use python3 for final JSON assembly in discover.sh
2. **`systemctl is-active` quirks** — Prints to stdout even with stderr redirected; use `&>/dev/null`
3. **`hermes backup --tier` is invalid** — Hermes backup uses `--quick` for minimal, no flag for full
4. **Restore across distros** — Restoring apt sources across different distros (Debian→Ubuntu) breaks apt
5. **SQLite WAL mode** — Naively copying a SQLite DB with active WAL mode misses `-wal`/`-shm` files; use `hermes backup` or `.backup` command
6. **Stop gateway before import** — Always stop `hermes-gateway.service` before `hermes import` to avoid file lock conflicts ^[entities/hermes-backup-restore-guide.md]
7. **sg01 baseline reference** — sg01 provides known-good sizes: state.db ~427 MB, skills ~115 MB, HERMES_HOME ~2.2 GB ^[queries/hermes-backup-validation-restore-preinspection.md]
8. **Model pinning for cost control** — Pin mechanical SSH tasks to sonnet via backup-worker agent; keep orchestration in main session for user interaction quality

## Related

- [[hermes-cli]] — Hermes CLI command reference
- [[entities/hermes-backup-restore-guide]] — Full backup/restore guide
- [[entities/sg01-host-infrastructure]] — Host-level infrastructure (Caddy, services, credstore)
- [[concepts/claude-code-agent-model-specification]] — Agent model pinning reference
