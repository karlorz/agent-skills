#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_JS="$ROOT/skills/dev-loop/scripts/dev-loop-status.js"

fail() {
  printf 'test-dev-loop-status: %s\n' "$1" >&2
  exit 1
}

[[ -f "$STATUS_JS" ]] || fail "missing dev-loop-status.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
# test

```yaml
slug: test-none
release_branch: main
knowledge_layer: none
prd_layer: manual
publish_via: none
```
EOF

git -C "$TMP" init -q
git -C "$TMP" config user.email "test@test"
git -C "$TMP" config user.name "test"
echo x > "$TMP/README.md"
git -C "$TMP" add README.md
git -C "$TMP" commit -q -m "init"
git -C "$TMP" branch -M main

OUT="$(node "$STATUS_JS" --repo "$TMP" --project test-none --format json --no-write 2>/dev/null)" || fail "status script failed on none layer"

echo "$OUT" | node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(0, "utf8"));
if (j.schema_version !== "dev-loop-status.v1") throw new Error("bad schema");
if (j.read_only !== true || j.writes_executed !== false) throw new Error("read_only contract");
if (j.project.slug !== "test-none") throw new Error("slug");
if (j.pipeline_preview.merge.strategy !== "repo-policy") throw new Error("repo-policy must be canonical");
if (j.pipeline_preview.merge.auto_merge_configured !== false) throw new Error("auto merge must default off");
if (j.pipeline_preview.merge.auto_merge_eligible !== false) throw new Error("auto merge must fail closed");
if ((j.pipeline_preview.merge.failed_gates || []).includes("ci_configured")) throw new Error("CI configuration is not merge authority");
process.stdout.write("ok-none-layer\n");
'

VAULT="$TMP/wiki"
mkdir -p "$VAULT/projects/agent-skills/work/2026-07-01-ready"
mkdir -p "$VAULT/projects/agent-skills/work/2026-07-01-skip"
cat > "$VAULT/SCHEMA.md" <<'EOF'
# schema
## Layers
- `concepts/`
EOF

cat > "$VAULT/projects/agent-skills/work/2026-07-01-ready/spec.md" <<'EOF'
---
title: Ready item
status: planned
automation_ready: true
human_questions_resolved: true
spec_preflight_approved: true
plan_preflight_approved: true
preflight_state: ready
merge_auto_approved: true
---
EOF

cat > "$VAULT/projects/agent-skills/work/2026-07-01-skip/spec.md" <<'EOF'
---
title: Skip item
status: planned
---
EOF

cat > "$TMP/.claude/dev-loop.config.md" <<EOF
\`\`\`yaml
slug: agent-skills
release_branch: main
knowledge_layer: skillwiki
vault: $VAULT
ci_configured: true
merge_policy:
  strategy: pull-request
  auto_merge: true
  merge_method: squash
  require_work_item_approval: true
\`\`\`
EOF

OUT2="$(node "$STATUS_JS" --repo "$TMP" --vault "$VAULT" --project agent-skills --format json --no-write --orchestration goal 2>/dev/null)" || fail "vault status failed"

echo "$OUT2" | node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(0, "utf8"));
const skips = j.work_preview.readiness_skips || [];
if (!skips.some((s) => s.id.includes("skip"))) throw new Error("expected readiness skip");
const ready = j.work_preview.claimable_unattended || [];
if (!ready.some((id) => id.includes("ready"))) throw new Error("expected unattended ready");
const merge = j.pipeline_preview.merge;
if (merge.auto_merge_configured !== true) throw new Error("expected explicit auto-merge config");
if (merge.work_item_approved !== true) throw new Error("expected selected work-item approval");
if (merge.route_blocked !== true) throw new Error("pull-request policy on release branch must block route");
if (merge.would_create_pr !== false || merge.would_push_direct !== false) throw new Error("blocked route must not claim PR or push");
if (merge.auto_merge_eligible !== false) throw new Error("unknown CI health must fail closed");
if (!(merge.failed_gates || []).includes("ci_health:healthy")) throw new Error("expected exact healthy CI gate");
process.stdout.write("ok-readiness\n");
'

BEFORE="$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -v 'dev-loop/status' || true)"
node "$STATUS_JS" --repo "$ROOT" --project agent-skills --format json --no-write >/dev/null 2>&1 || true
AFTER="$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -v 'dev-loop/status' || true)"
if [[ "$BEFORE" != "$AFTER" ]]; then
  fail "status run mutated tracked git state"
fi

HUD_JS="$ROOT/skills/dev-loop/scripts/dev-loop-status-hud.js"
[[ -f "$HUD_JS" ]] || fail "missing dev-loop-status-hud.js"

OUT_HUD="$(node "$HUD_JS" --repo "$TMP" --project test-none --probe --format json 2>/dev/null)" || fail "hud probe failed"
echo "$OUT_HUD" | node -e '
const j = JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-status-hud.v1") throw new Error("hud schema");
if (j.read_only !== true) throw new Error("hud read_only");
process.stdout.write("ok-hud\n");
'

printf 'test-dev-loop-status: all checks passed\n'
