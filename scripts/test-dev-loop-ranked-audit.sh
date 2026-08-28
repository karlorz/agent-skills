#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/skills/dev-loop/scripts/ranked-audit.js"

fail() {
  printf 'test-dev-loop-ranked-audit: %s\n' "$1" >&2
  exit 1
}

write_spec() {
  local dir="$1" title="$2" status="$3" priority="$4" updated="$5" extra="${6:-}"
  mkdir -p "$dir"
  cat > "$dir/spec.md" <<EOF
---
title: "$title"
name: "$(basename "$dir")"
kind: feature
status: $status
priority: $priority
project: "[[${7:-alpha}]]"
created: 2026-01-01
updated: $updated
started: 2026-01-01
$extra
---

# $title
EOF
  cat > "$dir/plan.md" <<EOF
---
title: "Plan — $title"
name: "$(basename "$dir")-plan"
kind: feature
status: $status
priority: $priority
project: "[[${7:-alpha}]]"
created: 2026-01-01
updated: $updated
started: 2026-01-01
---

# Plan — $title
EOF
}

init_repo() {
  local repo="$1" remote="$2" message="$3"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "ranked-audit@example.invalid"
  git -C "$repo" config user.name "Ranked Audit Test"
  printf '# fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "$message"
  git -C "$repo" remote add origin "$remote"
}

assert_json() {
  local json="$1"
  node - "$json" <<'NODE'
const data = JSON.parse(process.argv[2]);
const assert = (condition, message) => {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
};
const byId = new Map(data.candidates.map((candidate) => [candidate.id, candidate]));
assert(data.read_only === true, "ranked audit must report read_only=true");
assert(data.writes_executed === false, "ranked audit must report writes_executed=false");
assert(byId.get("2026-08-01-delivered").classification === "delivered-close-candidate", "delivered item classification mismatch");
assert(byId.get("2026-08-02-verification").classification === "verification-only", "verification-only classification mismatch");
assert(byId.get("2026-08-03-human").classification === "human-gated", "human-gated classification mismatch");
assert(byId.get("2026-08-04-active").classification === "active-code-work", "active work classification mismatch");
assert(byId.get("2026-01-01-stale").classification === "stale-or-superseded", "stale classification mismatch");
assert(byId.get("2026-08-05-unverifiable").classification === "unverifiable", "unverifiable classification mismatch");
assert(byId.get("2026-01-02-old-unverifiable").classification === "unverifiable", "old unresolved work must remain unverifiable");
assert(byId.get("2026-08-07-release-pending").classification === "active-code-work", "pending release prose must not imply delivery");
assert(!byId.has("2026-08-06-completed"), "completed work must be excluded from ranked audit");
assert(data.counts["verification-only"] === 1, "classification counts missing verification-only");
NODE
}

[ -f "$HELPER" ] || fail "missing helper: ${HELPER#$ROOT/}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VAULT="$TMP_DIR/wiki"
REPOS="$TMP_DIR/repos"
mkdir -p "$VAULT/projects/alpha/work" "$VAULT/projects/beta/work" "$VAULT/projects/gamma/work"

init_repo "$REPOS/alpha" "https://github.com/karlorz/alpha.git" "feat: deliver Delivered Feature"
init_repo "$REPOS/beta" "https://github.com/karlorz/beta.git" "chore: maintain beta"

write_spec "$VAULT/projects/alpha/work/2026-08-01-delivered" "Delivered Feature" in-progress high 2026-08-28 "" alpha
cat > "$VAULT/projects/alpha/work/2026-08-01-delivered/evidence.md" <<'EOF'
# Evidence

- Released to production and covered by immutable tag v1.2.3.
EOF

write_spec "$VAULT/projects/alpha/work/2026-08-02-verification" "Verification Follow-up" in-progress high 2026-08-28 $'post_release_verification:\n  posture: opt-in\n  triggers:\n    - matching-regression-report\n    - explicit-user-request\n    - relevant-code-or-release-change' alpha
write_spec "$VAULT/projects/alpha/work/2026-08-03-human" "Human Gate" in-progress high 2026-08-28 $'automation_ready: false\npreflight_state: needs_human' alpha
write_spec "$VAULT/projects/alpha/work/2026-08-04-active" "Active Feature" in-progress high 2026-08-28 "" alpha
write_spec "$VAULT/projects/beta/work/2026-01-01-stale" "Stale Feature" planned medium 2026-01-01 "" beta
write_spec "$VAULT/projects/gamma/work/2026-08-05-unverifiable" "Unverifiable Feature" in-progress high 2026-08-28 "" gamma
write_spec "$VAULT/projects/gamma/work/2026-01-02-old-unverifiable" "Old Unverifiable Feature" planned high 2026-01-02 "" gamma
write_spec "$VAULT/projects/alpha/work/2026-08-06-completed" "Completed Feature" completed high 2026-08-28 "completed: 2026-08-28" alpha
write_spec "$VAULT/projects/alpha/work/2026-08-07-release-pending" "Pending Release" in-progress high 2026-08-28 "" alpha
cat > "$VAULT/projects/alpha/work/2026-08-07-release-pending/evidence.md" <<'EOF'
# Evidence

- Packaging complete; release remains pending.
EOF

PROJECT_REPOS="$VAULT/projects/llm-wiki/architecture/project-repos.yaml"
mkdir -p "$(dirname "$PROJECT_REPOS")"
cat > "$PROJECT_REPOS" <<EOF
schema_version: 1
coordinator_project: llm-wiki
hosts:
  test-host:
    users:
      test-user:
        workspace_roots:
          - $REPOS
projects:
  alpha:
    remote_urls:
      - https://github.com/karlorz/alpha.git
  beta:
    remote_urls:
      - https://github.com/karlorz/beta.git
  gamma:
    repo_names:
      - missing-gamma
EOF

hash_before="$(find "$VAULT" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"
json="$(node "$HELPER" --vault "$VAULT" --top 20 --project-repos "$PROJECT_REPOS" --host-id test-host --repo-user test-user --now 2026-08-28)"
hash_after="$(find "$VAULT" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"

[ "$hash_before" = "$hash_after" ] || fail "ranked audit mutated the vault"
assert_json "$json"

printf 'test-dev-loop-ranked-audit: ok\n'
