#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFLIGHT="$ROOT/skills/dev-loop/scripts/dev-loop-write-preflight.js"
fail() { printf 'test-dev-loop-write-preflight: %s\n' "$1" >&2; exit 1; }
[[ -f "$PREFLIGHT" ]] || fail "missing dev-loop-write-preflight.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -b main >/dev/null 2>&1
  git -C "$dir" config user.email "preflight@example.com"
  git -C "$dir" config user.name "Preflight Test"
  printf 'base\n' >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -m "init" >/dev/null
}

# --- Feature branch OK ---
FEATURE="$TMP/feature"
init_repo "$FEATURE"
mkdir -p "$FEATURE/.claude"
cat >"$FEATURE/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: preflight-fixture
release_branch: main
branch_policy:
  require_feature_branch: true
  feature_branch_pattern: "feat/*"
  direct_push_to_release_branch: false
merge_policy:
  strategy: pull-request
```
EOF
git -C "$FEATURE" checkout -b feat/ok >/dev/null 2>&1
OUT="$(node "$PREFLIGHT" --repo "$FEATURE" --intent commit --format json)"
echo "$OUT" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-write-preflight.v1") throw new Error("schema");
if (j.allowed !== true) throw new Error(`feature branch must allow: ${JSON.stringify(j)}`);
if (!j.identity || j.identity.branch !== "feat/ok") throw new Error("branch identity");
if (j.identity.detached !== false) throw new Error("not detached");
if (!j.permissions.may_commit) throw new Error("may_commit");
process.stdout.write("ok-feature-branch\n");
'
set +e
node "$PREFLIGHT" --repo "$FEATURE" --intent commit --format json >/dev/null
FEAT_EXIT=$?
set -e
[[ "$FEAT_EXIT" -eq 0 ]] || fail "feature branch exit must be 0"

# --- Release branch refuse when policy forbids ---
RELEASE="$TMP/release"
init_repo "$RELEASE"
mkdir -p "$RELEASE/.claude"
cat >"$RELEASE/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: preflight-fixture
release_branch: main
branch_policy:
  require_feature_branch: true
  direct_push_to_release_branch: false
merge_policy:
  strategy: pull-request
```
EOF
set +e
OUT_REL="$(node "$PREFLIGHT" --repo "$RELEASE" --intent commit --format json)"
REL_EXIT=$?
set -e
[[ "$REL_EXIT" -eq 1 ]] || fail "release branch commit must exit 1, got $REL_EXIT"
echo "$OUT_REL" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.allowed !== false) throw new Error("release must refuse");
if (!j.refusals.some((r) => r.code === "release_branch_write_refused" || r.code === "feature_branch_required")) {
  throw new Error(`missing release refusal: ${JSON.stringify(j.refusals)}`);
}
if (j.permissions.may_commit !== false) throw new Error("may_commit must be false on release");
process.stdout.write("ok-release-refuse\n");
'

# --- Detached HEAD ---
DETACH="$TMP/detach"
init_repo "$DETACH"
mkdir -p "$DETACH/.claude"
cat >"$DETACH/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: preflight-fixture
release_branch: main
worktree_policy:
  allow_detached: false
branch_policy:
  direct_push_to_release_branch: true
```
EOF
HEAD_SHA="$(git -C "$DETACH" rev-parse HEAD)"
git -C "$DETACH" checkout --detach "$HEAD_SHA" >/dev/null 2>&1
set +e
OUT_DET="$(node "$PREFLIGHT" --repo "$DETACH" --intent push --format json)"
DET_EXIT=$?
set -e
[[ "$DET_EXIT" -eq 1 ]] || fail "detached push must exit 1, got $DET_EXIT"
echo "$OUT_DET" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.identity.detached !== true) throw new Error("must detect detached");
if (!j.refusals.some((r) => r.code === "detached_head")) throw new Error(`missing detached: ${JSON.stringify(j.refusals)}`);
if (j.permissions.may_push !== false) throw new Error("may_push must be false when detached");
if (j.permissions.may_commit !== true) throw new Error("local commit should still be allowed");
process.stdout.write("ok-detached-head\n");
'

# --- Linked worktree identity ---
WT_MAIN="$TMP/wt-main"
init_repo "$WT_MAIN"
mkdir -p "$WT_MAIN/.claude"
cat >"$WT_MAIN/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: preflight-fixture
release_branch: main
branch_policy:
  direct_push_to_release_branch: true
```
EOF
WT_LINK="$TMP/wt-link"
git -C "$WT_MAIN" worktree add -b feat/worktree "$WT_LINK" >/dev/null 2>&1
cp -R "$WT_MAIN/.claude" "$WT_LINK/.claude"
OUT_WT="$(node "$PREFLIGHT" --repo "$WT_LINK" --intent commit --format json)"
echo "$OUT_WT" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.identity.linked_worktree !== true) throw new Error(`expected linked worktree: ${JSON.stringify(j.identity)}`);
if (j.identity.git_dir === j.identity.common_dir) throw new Error("git-dir should differ from common-dir");
if (j.identity.branch !== "feat/worktree") throw new Error("worktree branch");
if (j.allowed !== true) throw new Error("named worktree should allow commit");
process.stdout.write("ok-linked-worktree\n");
'

# --- Submodule dirty (content change inside submodule) ---
SUPER="$TMP/super"
SUB="$TMP/submod"
init_repo "$SUB"
init_repo "$SUPER"
mkdir -p "$SUPER/.claude"
cat >"$SUPER/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: preflight-fixture
release_branch: main
worktree_policy:
  allow_submodules: true
branch_policy:
  direct_push_to_release_branch: true
```
EOF
git -C "$SUPER" -c protocol.file.allow=always submodule add "$SUB" vendor/sub >/dev/null 2>&1
git -C "$SUPER" commit -m "add submodule" >/dev/null 2>&1
printf 'dirty\n' >>"$SUPER/vendor/sub/README.md"
set +e
OUT_SUB="$(node "$PREFLIGHT" --repo "$SUPER" --intent push --format json)"
SUB_EXIT=$?
set -e
[[ "$SUB_EXIT" -eq 1 ]] || fail "dirty submodule push must exit 1, got $SUB_EXIT"
echo "$OUT_SUB" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.allowed !== false) throw new Error("dirty submodule must refuse push");
if (!j.refusals.some((r) => r.code === "submodule_dirty")) {
  throw new Error(`expected submodule_dirty: ${JSON.stringify(j)}`);
}
if (j.identity.submodule_dirty !== true) throw new Error("identity.submodule_dirty");
process.stdout.write("ok-submodule-dirty\n");
'

# --- Sandbox ownership miss ---
SAND="$TMP/sandbox"
init_repo "$SAND"
mkdir -p "$SAND/.claude"
cat >"$SAND/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: preflight-fixture
release_branch: main
task_sandbox:
  required: true
  owner: agent-alpha
  ownership_file: ".dev-loop-sandbox-owner"
branch_policy:
  direct_push_to_release_branch: true
```
EOF
set +e
OUT_SB="$(node "$PREFLIGHT" --repo "$SAND" --intent write --format json --sandbox-owner agent-alpha)"
SB_EXIT=$?
set -e
[[ "$SB_EXIT" -eq 1 ]] || fail "missing sandbox ownership must exit 1, got $SB_EXIT"
echo "$OUT_SB" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.allowed !== false) throw new Error("sandbox miss must refuse");
if (!j.refusals.some((r) => r.code === "sandbox_ownership_missing")) {
  throw new Error(`missing sandbox refusal: ${JSON.stringify(j.refusals)}`);
}
process.stdout.write("ok-sandbox-miss\n");
'

printf 'agent-alpha\n' >"$SAND/.dev-loop-sandbox-owner"
OUT_SOK="$(node "$PREFLIGHT" --repo "$SAND" --intent write --format json --sandbox-owner agent-alpha)"
echo "$OUT_SOK" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.allowed !== true) throw new Error(`sandbox match must allow: ${JSON.stringify(j)}`);
if (j.sandbox.matches !== true) throw new Error("sandbox.matches");
process.stdout.write("ok-sandbox-match\n");
'

printf 'agent-beta\n' >"$SAND/.dev-loop-sandbox-owner"
set +e
OUT_SM="$(node "$PREFLIGHT" --repo "$SAND" --intent commit --format json --sandbox-owner agent-alpha)"
SM_EXIT=$?
set -e
[[ "$SM_EXIT" -eq 1 ]] || fail "sandbox mismatch must exit 1"
echo "$OUT_SM" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (!j.refusals.some((r) => r.code === "sandbox_ownership_mismatch")) {
  throw new Error(`missing mismatch: ${JSON.stringify(j.refusals)}`);
}
process.stdout.write("ok-sandbox-mismatch\n");
'

# zero false allows: release branch must not report allowed for push
set +e
node "$PREFLIGHT" --repo "$RELEASE" --intent push --format json >/dev/null
PUSH_EXIT=$?
set -e
[[ "$PUSH_EXIT" -eq 1 ]] || fail "release push must refuse"

printf 'test-dev-loop-write-preflight: all checks passed\n'
