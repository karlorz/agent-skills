---
name: hermes-remote-backup
description: >
  Remote Hermes Agent backup from macOS to any Linux host via official
  `hermes backup` CLI. Trigger when user says backup/restore sg01/sg02,
  Hermes backup, disaster recovery, or migrating Hermes state. Prerequisite:
  run setup-remote-user.sh to create a non-root user with passwordless sudo
  before running backups as non-root. Uses only official CLI commands:
  `hermes backup` (full) or `hermes backup --quick` (snapshot).
---

# Hermes Remote Backup Skill

Backup and restore a remote Hermes Agent host from macOS via SSH. Uses **only the official Hermes CLI** (`hermes backup`, `hermes import`). No custom tier logic, no rsync/cp of HERMES_HOME internals.

## Prerequisite: Non-Root User Setup

Before running backups as a non-root user, set up the target host with an automation user:

```bash
# One-time bootstrap (connects as root, creates "agent" user)
bash scripts/setup-remote-user.sh sg02 --ssh-config
```

This script:
1. Connects to the host as root (via existing SSH alias like `sg02`)
2. Creates the `agent` user (customizable via `--user`)
3. Adds `agent` to the `sudo` group
4. Configures passwordless sudo via `/etc/sudoers.d/agent`
5. Deploys your macOS SSH public key to `~agent/.ssh/authorized_keys`
6. Optionally writes a `~/.ssh/config` entry for `<host>-agent`

After setup, add the SSH config alias to `~/.ssh/config` (or use `--ssh-config`):

```
Host sg02-agent
  HostName <IP-of-sg02>
  User agent
  Port 22
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  PreferredAuthentications publickey
```

Then use `sg02-agent` as the host alias for all backup commands.

Also supports direct connection: `ssh agent@sg02` if the IP/hostname routes correctly.

**Security note:** After verifying non-root access works, consider disabling root SSH login:
```bash
ssh sg02 'sed -i "s/^PermitRootLogin yes/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config && systemctl restart sshd'
```

## Official CLI Reference

```
hermes backup                  # Full backup (config, skills, sessions, state.db, .env, auth)
hermes backup --quick          # Quick snapshot (config, state.db, .env, auth, cron only)
hermes backup -o /path.zip     # Custom output path
hermes import [--force] zip    # Restore from backup
```

**Key facts:**
- `hermes backup` is SQLite-safe — handles WAL mode correctly
- Does NOT support `--tier` flag (use `--quick` or no flag)
- Does NOT include profiles (handled separately if needed)
- Does NOT include systemd service files (handled separately if needed)
- Does NOT include rclone config (handled separately if needed)

## Trigger Reference

See `compound/hermes-backup-trigger-reference` in the vault for the complete map of all Hermes Agent backup mechanisms, trigger events, and coverage gaps. Key points:

- **3 backup mechanisms**: full-zip (`hermes backup`), quick-snapshot (`--quick`), curator snapshot (skills only)
- **5 trigger events**: 3 manual (`hermes backup`, `--quick`, `/snapshot`), 2 event-driven (update, migrate)
- **No routine/scheduled backup** exists in Hermes — use `setup-remote-cron.sh` to fill this gap
- `hermes backup` excludes profiles, projects, systemd, and rclone config

## Workflow

1. **Run backup**: `bash scripts/remote-backup.sh sg01 --mode full`
2. **Optional extras**: add `--include-profiles --include-systemd` for full coverage
3. **Restore**: `bash scripts/remote-restore.sh archive.zip --target sg01`

## CLI Usage

### Root (existing hosts like sg01)

```bash
# Full backup
bash scripts/host-backup-cli.sh --host sg01 --mode full

# Quick snapshot
bash scripts/host-backup-cli.sh --host sg01 --mode quick
```

### Non-root (via SSH config alias, e.g. sg02-agent)

After running `setup-remote-user.sh --ssh-config`, use the `<host>-agent` alias:

```bash
# Full backup as non-root user
bash scripts/host-backup-cli.sh --host sg02-agent --mode full

# Quick snapshot as non-root user
bash scripts/host-backup-cli.sh --host sg02-agent --mode quick

# Direct connection (if DNS resolves hostname)
bash scripts/host-backup-cli.sh --host agent@sg02 --mode full
```

# Full + profiles + systemd
bash scripts/host-backup-cli.sh --host sg01 --mode full --include-profiles --include-systemd

# Restore
bash scripts/host-restore-cli.sh --archive ~/Desktop/backups/sg01/hermes-20260516-full.zip --target sg01
```

## What each mode covers

| Mode | `hermes backup` | Profiles | Systemd | Rclone config |
|------|-----------------|----------|---------|---------------|
| `quick` | `--quick` snapshot | ✗ | ✗ | ✗ |
| `full` | Full backup | ✗ | ✗ | ✗ |
| `full --include-profiles` | Full backup | ✓ | ✗ | ✗ |
| `full --include-profiles --include-systemd` | Full backup | ✓ | ✓ | ✗ |
| `full --include-rclone-config` | Full backup | ✗ | ✗ | ✓ |
| All+ | Full backup | ✓ | ✓ | ✓ |

## Retention (`prune-backups.sh`)

Keep N most recent backup sets per host, removing older archives:

```bash
# Keep 7 most recent per host
bash scripts/prune-backups.sh ~/Desktop/backups --retain 7

# Preview without deleting
bash scripts/prune-backups.sh ~/Desktop/backups --retain 7 --dry-run
```

Automatically runs after backup when `--retain <N>` flag is passed:

```bash
bash scripts/remote-backup.sh sg01 --mode full --retain 7
```

## Cloud Upload (`--upload` flag)

After backup download, sync to S3/cloud via rclone on macOS:

```bash
# Requires rclone configured on macOS (brew install rclone)
bash scripts/remote-backup.sh sg01 --mode full --upload idrive:hermes-backups/sg01/
bash scripts/host-backup-cli.sh --host sg01 --mode full --upload idrive:hermes-backups/sg01/
```

Uses `--backup-dir` for archive rotation on the remote. Non-blocking — backup is still saved locally if upload fails.

## Remote Cron Setup (`setup-remote-cron.sh`)

Fill the "no routine backup" gap by installing a daily `hermes backup` cron job directly on the remote host:

```bash
# Daily quick snapshot at 4am HKT, 7-day retention
bash scripts/setup-remote-cron.sh sg02-agent --quick

# Daily full backup + rclone sync to S3
bash scripts/setup-remote-cron.sh sg02-agent --full --rclone-dest "idrive:hermes-backups/sg02/"

# Custom time and retention
bash scripts/setup-remote-cron.sh sg02-agent --time 02:30 --retain-days 14

# Preview without installing
bash scripts/setup-remote-cron.sh sg02-agent --dry-run
```

The script:
1. Installs `hermes-auto-backup.sh` to `~/.hermes/scripts/` on remote
2. Adds a crontab entry (default: 4:00am HKT daily)
3. Optionally adds rclone sync and retention pruning
4. Verifies cron was installed
5. Logs output to `/var/log/hermes-auto-backup.log`

## Gotchas

1. **No --tier flag**: `hermes backup --tier standard` silently fails. Correct: `--quick` or nothing.
2. **Profiles not in backup**: `hermes backup` skips profiles — add `--include-profiles` if needed.
3. **Secrets in archive**: Archives contain plaintext `.env`/`auth.json`. Encrypt for remote storage.
4. **~/wiki S3 mount**: If `~/wiki` is an S3 rclone mount, verify it's active before restore. A broken mount (`noauto` in fstab) silently writes files to local ext4 — they never reach S3, no alert fires. The test scripts `pre-inspect.sh` (check #7, hard fail) and `restore-validate.sh` (check #11, warn) catch this. Manual check: `df -T ~/wiki | grep fuse.rclone`.

## Backup Validation

`hermes backup` has no built-in `verify` command. Validate externally:

```bash
# 1. Zip integrity
unzip -t archive.zip

# 2. SQLite integrity on state.db
unzip -p archive.zip state.db > /tmp/state.db
sqlite3 /tmp/state.db "PRAGMA integrity_check;"
rm /tmp/state.db

# 3. Content manifest (verify expected files exist)
unzip -l archive.zip | grep -E '(config\.yaml|\.env|auth\.json|state\.db|skills/)'

# 4. SHA256 checksum
sha256sum archive.zip > archive.zip.sha256
```

For comprehensive validation including archive integrity, SQLite PRAGMA checks, content manifest, and test restore dry-run, see `queries/hermes-backup-validation-restore-preinspection` in the vault.

## Restore Target Pre-Inspection

Before restoring to a target, verify readiness. Two target types:

### Standard SSH host (sg03, Debian ARM64)

```bash
# Quick discovery (reuses discover-remote.sh)
bash scripts/discover-remote.sh <host> --verbose

# Manual checklist:
ssh <host> "uname -m"              # Must be aarch64
ssh <host> "python3 --version"      # Must be 3.10+
ssh <host> "curl --version | head -1"
ssh <host> "df -h ~"               # Need >5GB free
ssh <host> "free -h"               # Need >2GB RAM
ssh <host> "hermes --version 2>/dev/null || echo NOT_INSTALLED"
ssh <host> "df -T ~/wiki 2>/dev/null | grep fuse.rclone || echo WARN: ~/wiki not on S3 mount"  # Only if ~/wiki exists
```

### devsh PVE LXC container (restricted)

**Key constraints (verified 2026-05-16 on live VM):**
- `devsh sync` — NOT supported ("not supported for pve-lxc instances yet")
- `devsh ssh` — NOT supported ("ssh is not supported for pve-lxc instances")
- `systemctl --user` — FAILS (no systemd user bus in LXC container)
- Stdin piping to `devsh exec` — NOT supported
- **BUT**: `devsh exec`, HTTP file transfer, and systemd system mode all work

```bash
# Pre-inspect via devsh exec
VM_ID=$(devsh ls --json | python3 -c "import json,sys; vms=[v for v in json.load(sys.stdin) if v['provider']=='pve-lxc' and v['status']=='stopped']; print(vms[0]['id'] if vms else '')")
devsh resume "$VM_ID"
devsh exec "$VM_ID" "uname -m"            # x86_64 (not ARM64!)
devsh exec "$VM_ID" "python3 --version"    # Must be 3.10+
devsh exec "$VM_ID" "df -h /"              # Need >5GB free
devsh exec "$VM_ID" "free -h"              # Need >2GB RAM
devsh exec "$VM_ID" "hermes --version 2>/dev/null || echo NOT_INSTALLED"
devsh exec "$VM_ID" "systemctl --user status 2>&1 | head -3"  # Expected to fail

# File transfer: HTTP serve from macOS
MAC_IP=$(ipconfig getifaddr en1 2>/dev/null || ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
cd /path/to/backups && python3 -m http.server 19999 &
devsh exec "$VM_ID" "curl -s -o /tmp/hermes-backup.zip http://${MAC_IP}:19999/archive.zip"

# Service validation (no --user flag, use system services or direct exec)
devsh exec "$VM_ID" "hermes --version && hermes doctor"
devsh exec "$VM_ID" "curl -s http://127.0.0.1:8642/health"
```

pve-lxc VMs are x86_64 (not ARM64), have 8GB RAM, 32GB disk, Ubuntu 24.04, run as root. For full access, use `morph` provider instead.

## Service Validation Procedure

After `hermes import --force`, run this sequence:

```bash
# 1. CLI health
ssh <target> "hermes --version && hermes doctor"

# 2. Services
ssh <target> "systemctl --user status hermes-gateway.service --no-pager | head -10"
ssh <target> "sudo systemctl status hermes-dashboard.service --no-pager | head -10"

# 3. Health endpoint (direct, bypasses Caddy)
ssh <target> "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8642/health"
# Expected: 200

# 4. API models
API_KEY=$(ssh <target> "grep '^API_SERVER_KEY=' ~/.hermes/.env | cut -d= -f2")
ssh <target> "curl -s -H 'Authorization: Bearer $API_KEY' http://127.0.0.1:8642/v1/models" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d.get(\"data\",d))} models')"

# 5. Content
ssh <target> "du -sh ~/.hermes/state.db && echo 'Skills:' && ls ~/.hermes/skills/ | wc -l"
ssh <target> "cat ~/.hermes/cron/jobs.json 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)), \"cron jobs\")' 2>/dev/null || echo 'No cron jobs'"
```

For a complete automated validation, use `restore-validate.sh` from the vault's deep research.

### Key reference values (sg01 baseline)

| Check | Expected |
|-------|----------|
| state.db | ~427 MB |
| skills/ | ~115 MB |
| HERMES_HOME total | ~2.2 GB (full) |
| `hermes doctor` warnings | Custom provider + optional keys (non-critical) |
| Gateway flags | `--replace --accept-hooks` |