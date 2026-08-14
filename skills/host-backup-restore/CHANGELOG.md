# Changelog

All notable changes to this skill are documented in this file.

## [3.7.0] - 2026-08-14

- Add first-class `portfolio-lab` profile and exclusive `portfolio_lab` group (built-in preset, not YAML-only; name reserved against YAML override; selects ONLY `portfolio_lab`; profile/groups selections are never silently overridden and cannot mix with generic host/identity/Caddy/Hermes groups).
- Portfolio Lab backup (retrieval scope): accepts only plaintext `*.portfolio-lab-recovery.tar` archives and an exact `.tar.sha256` sidecar, requires a separately obtained lowercase `--trusted-sha256` before it executes an archive-provided bootstrap, retrieves archive and sidecar with resumable rsync (`--partial-dir`) into an explicit absolute `--dest`, then runs canonical `verify --archive` after a stdlib-tarfile safety gate (exact required regular files; rejects duplicate, traversal, absolute, backslash, drive-prefixed, link, device, FIFO, and sparse members; never full-extracts); source archive creation stays on the source host with canonical `create` (`PORTFOLIO_LAB_PROJECT_DIR=<explicit repo>` selects the `python_runtime.sh` project directory; `--storage-encryption-attested`); no automatic cloud transfer and no invented `backup` CLI surface.
- Portfolio Lab restore: requires the same independently trusted `--trusted-sha256` before its archive-provided bootstrap is executed, plus explicit `--target-mode dev|prod` + `--app-dir`/`--web-root`; transfers archive + sidecar, compares both the sidecar and trusted digest to archive bytes on target, safely extracts only the bootstrap to controlled staging, runs canonical `verify --archive` on the target BEFORE canonical `restore`, cleans staging after failures, and retains staging after success for the printed manual activation command; it never restores credentials, identities, Caddy config/cert data, or agent state; production activation is never automatic.
- Fail closed on silently-ignored flags: portfolio-lab backup rejects generic flags (`--user`, `--hermes-tier`, `--redetect`, `--research`, `--save-profile`, `--db-user`, `--db-pass`); portfolio-lab restore forwards `--user` (target becomes user@host) and rejects `--db-user`/`--db-pass`/`--allow-cross-distro`; `--dry-run` performs no ssh/rsync calls.

## [3.6.4] - 2026-08-10

- explicit SSH/Tailscale identity restore for post-reinstall hosts, with safety snapshots, ca-certificates handling, and SSH validation.
