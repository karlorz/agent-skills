#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATE_JS="$ROOT/skills/dev-loop/scripts/dev-loop-config-migrate.js"
fail() { printf 'test-dev-loop-config-migrate: %s\n' "$1" >&2; exit 1; }
[[ -f "$MIGRATE_JS" ]] || fail "missing migrate script"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
# test
```yaml
slug: mig-test
release_branch: main
knowledge_layer: skillwiki
vault: /old/wiki/path
```
EOF
OUT="$(node "$MIGRATE_JS" --repo "$TMP" --format json --no-write 2>/dev/null)" || fail "migrate failed"
echo "$OUT" | node -e '
const j = JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-config-migrate.v1") throw new Error("schema");
if (j.read_only !== true) throw new Error("read_only");
if (j.migration.state !== "legacy_top_level_only") throw new Error("expected legacy_top_level_only got "+j.migration.state);
process.stdout.write("ok-legacy\n");
'
printf 'test-dev-loop-config-migrate: all checks passed\n'