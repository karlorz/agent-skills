#!/usr/bin/env bash
# Deprecated Claude-only development helper.
#
# Versioned plugin caches are immutable distribution artifacts. This script
# intentionally performs no copying, deletion, directory creation, or cache
# replacement. Use the supported platform installer/update flow instead.

set -euo pipefail

cat >&2 <<'EOF'
sync-plugin-cache.sh is deprecated and performs no writes.

For Codex:
  1. If the declared version is already released, advance it when the
     distributable payload changes.
  2. Run: codex plugin add dev-loop@karlorz-agent-skills --json
  3. Verify the returned version/path and source/cache hashes.
  4. Start a new Codex chat or CLI session.

For Claude Code:
  1. If the declared version is already released, advance it when the
     distributable payload changes.
  2. Run: claude plugin update dev-loop@karlorz-agent-skills
  3. Verify hashes, then restart Claude Code.

Do not copy files into an existing versioned cache and do not delete session
history as a refresh mechanism.
EOF

exit 2
