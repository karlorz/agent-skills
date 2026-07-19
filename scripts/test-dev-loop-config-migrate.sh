#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATE_JS="$ROOT/skills/dev-loop/scripts/dev-loop-config-migrate.js"
fail() { printf 'test-dev-loop-config-migrate: %s\n' "$1" >&2; exit 1; }
[[ -f "$MIGRATE_JS" ]] || fail "missing migrate script"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/dev-loop.config.md" <<'CFG'
# test
```yaml
slug: mig-test
release_branch: main
knowledge_layer: skillwiki
vault: /old/wiki/path
```
CFG
OUT="$(node "$MIGRATE_JS" --repo "$TMP" --format json --no-write 2>/dev/null)" || fail "migrate failed"
echo "$OUT" | node -e '
const j = JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-config-migrate.v1") throw new Error("schema");
if (j.read_only !== true) throw new Error("read_only");
if (j.migration.state !== "legacy_top_level_only") throw new Error("expected legacy_top_level_only got "+j.migration.state);
process.stdout.write("ok-legacy\n");
'

cat > "$TMP/.claude/dev-loop.config.md" <<'CFG'
---
name: migration fixture
---

```yaml
slug: mig-test
release_branch: main
knowledge_layer: skillwiki
vault: /old/wiki/path
```

```yaml
knowledge_backends:
  skillwiki:
    vault: /new/wiki/path
```
CFG
OUT_CONFLICT="$(node "$MIGRATE_JS" --repo "$TMP" --format json --no-write 2>/dev/null)" || true
echo "$OUT_CONFLICT" | node -e '
const j = JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.migration.state !== "conflicting_vault_paths") throw new Error(`state: ${JSON.stringify(j)}`);
if (j.vault_shape.legacy !== "/old/wiki/path" || j.vault_shape.nested !== "/new/wiki/path") throw new Error("typed vault values");
if (!Number.isInteger(j.vault_shape.legacy_line) || !Number.isInteger(j.vault_shape.nested_line)) throw new Error("vault provenance");
if (j.writes_executed !== false) throw new Error("migration must remain read-only");
process.stdout.write("ok-conflict-provenance\n");
'

OUT_UNAVAILABLE="$(DEV_LOOP_CONFIG_PYTHON=/definitely/missing/python node "$MIGRATE_JS" --repo "$TMP" --format json --no-write 2>/dev/null)" || true
echo "$OUT_UNAVAILABLE" | node -e '
const j = JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.overall.state !== "blocked" || j.migration.state !== "invalid_config") throw new Error(`must fail closed: ${JSON.stringify(j)}`);
if (!(j.parser_errors || []).some((item) => item.code === "parser_unavailable")) throw new Error("parser capability error missing");
process.stdout.write("ok-parser-unavailable\n");
'
printf 'test-dev-loop-config-migrate: all checks passed\n'
