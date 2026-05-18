---
status: archived
archived_date: 2026-05-17
reason: >
  Absorbed into host-backup-restore as scripts/hermes/ module.
  Hermes backup/restore operations now handled by:
  - scripts/hermes/remote-backup.sh
  - scripts/hermes/remote-restore.sh
  - scripts/hermes/discover-hermes.sh
  - scripts/hermes/pre-inspect.sh
  - scripts/hermes/restore-validate.sh
  - scripts/hermes/prune-backups.sh
  - scripts/hermes/setup-remote-user.sh
  - scripts/hermes/setup-remote-cron.sh
  - scripts/hermes/setup-nonroot-hermes.sh
superseded_by: host-backup-restore (skills/host-backup-restore/)
version: last standalone version
---

# hermes-remote-backup (archived)

This skill has been absorbed into `host-backup-restore` as a `scripts/hermes/` module.

## Script Map

| Original path | New path |
|---------------|----------|
| scripts/discover-remote.sh | scripts/hermes/discover-hermes.sh |
| scripts/remote-backup.sh | scripts/hermes/remote-backup.sh |
| scripts/remote-restore.sh | scripts/hermes/remote-restore.sh |
| scripts/pre-inspect.sh | scripts/hermes/pre-inspect.sh |
| scripts/restore-validate.sh | scripts/hermes/restore-validate.sh |
| scripts/prune-backups.sh | scripts/hermes/prune-backups.sh |
| scripts/setup-remote-user.sh | scripts/hermes/setup-remote-user.sh |
| scripts/setup-remote-cron.sh | scripts/hermes/setup-remote-cron.sh |
| scripts/setup-nonroot-hermes.sh | scripts/hermes/setup-nonroot-hermes.sh |
| scripts/host-backup-cli.sh | Replaced by host-backup-restore CLI + profile system |
| scripts/host-restore-cli.sh | Replaced by host-backup-restore restore CLI |
| scripts/test-workflow.sh | Replaced by host-backup-restore test-restore.sh |
