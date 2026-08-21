#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/skills/dev-loop/scripts/dev-loop-isolation-landing.js"

fail() {
  printf 'test-dev-loop-isolation-landing: %s\n' "$1" >&2
  exit 1
}

[[ -f "$HELPER" ]] || fail "missing skills/dev-loop/scripts/dev-loop-isolation-landing.js"

node - "$HELPER" <<'NODE'
"use strict";

const assert = require("node:assert/strict");
const helperPath = process.argv[2];
const {
  parseMergePolicy,
  parseWorktreePolicy,
  resolveIsolationPlan,
  resolveLandingRoute,
  LANDING_ROUTES,
  ISOLATION_ACTIONS,
  ISOLATION_REASONS,
} = require(helperPath);

assert.deepEqual(
  [...LANDING_ROUTES],
  ["attended-menu", "pull-request", "local-merge-then-push"]
);

assert.deepEqual(
  [...ISOLATION_ACTIONS],
  ["create", "skip"]
);

assert.deepEqual(
  [...ISOLATION_REASONS],
  ["already-isolated", "disabled", "detached"]
);

// --- parseMergePolicy unit tests ---
// allow_local_merge absent -> false
{
  const emptyPolicy = parseMergePolicy({});
  assert.equal(emptyPolicy.allow_local_merge, false);
  assert.equal(emptyPolicy.strategy, "repo-policy");
  assert.equal(emptyPolicy.auto_merge, false);
  assert.equal(emptyPolicy.merge_method, "squash");
  assert.equal(emptyPolicy.require_work_item_approval, true);

  const undefPolicy = parseMergePolicy(undefined);
  assert.equal(undefPolicy.allow_local_merge, false);

  const explicitFalse = parseMergePolicy({ merge_policy: { allow_local_merge: false } });
  assert.equal(explicitFalse.allow_local_merge, false);

  const explicitTrue = parseMergePolicy({ merge_policy: { allow_local_merge: true } });
  assert.equal(explicitTrue.allow_local_merge, true);

  // normalizes strategy branch-policy -> repo-policy
  const branchPolicy = parseMergePolicy({ merge_policy: { strategy: "branch-policy" } });
  assert.equal(branchPolicy.strategy, "repo-policy");
}

// --- parseWorktreePolicy unit tests ---
// worktree_policy.enabled absent -> true
{
  const emptyPolicy = parseWorktreePolicy({});
  assert.equal(emptyPolicy.enabled, true);

  const undefPolicy = parseWorktreePolicy(undefined);
  assert.equal(undefPolicy.enabled, true);

  const explicitFalse = parseWorktreePolicy({ worktree_policy: { enabled: false } });
  assert.equal(explicitFalse.enabled, false);

  const explicitTrue = parseWorktreePolicy({ worktree_policy: { enabled: true } });
  assert.equal(explicitTrue.enabled, true);
}

// --- resolveLandingRoute unit tests ---
// Matrix from brief:
// 1. allow_local_merge: false / absent -> pull-request or current PR route
// 2. allow_local_merge: true + attended -> attended-menu
// 3. allow_local_merge: true + unattended + merge_auto_approved: false -> pull-request
// 4. allow_local_merge: true + unattended + merge_auto_approved: true + repo-policy -> local-merge-then-push
{
  // Absent / false allow_local_merge
  assert.equal(
    resolveLandingRoute({
      allow_local_merge: false,
      orchestration: "attended",
      merge_auto_approved: true,
      strategy: "repo-policy",
    }),
    "pull-request"
  );

  assert.equal(
    resolveLandingRoute({
      allow_local_merge: false,
      orchestration: "goal",
      merge_auto_approved: true,
      strategy: "repo-policy",
    }),
    "pull-request"
  );

  // allow_local_merge: true + attended -> attended-menu
  assert.equal(
    resolveLandingRoute({
      allow_local_merge: true,
      orchestration: "attended",
      merge_auto_approved: false,
      strategy: "repo-policy",
    }),
    "attended-menu"
  );

  assert.equal(
    resolveLandingRoute({
      allow_local_merge: true,
      orchestration: "attended",
      merge_auto_approved: true,
      strategy: "repo-policy",
    }),
    "attended-menu"
  );

  // allow_local_merge: true + unattended + merge_auto_approved: false -> pull-request
  assert.equal(
    resolveLandingRoute({
      allow_local_merge: true,
      orchestration: "goal", // or unattended: true
      merge_auto_approved: false,
      strategy: "repo-policy",
    }),
    "pull-request"
  );

  assert.equal(
    resolveLandingRoute({
      allow_local_merge: true,
      unattended: true,
      merge_auto_approved: false,
      strategy: "repo-policy",
    }),
    "pull-request"
  );

  // allow_local_merge: true + unattended + merge_auto_approved: true + repo-policy -> local-merge-then-push
  assert.equal(
    resolveLandingRoute({
      allow_local_merge: true,
      orchestration: "goal",
      merge_auto_approved: true,
      strategy: "repo-policy",
    }),
    "local-merge-then-push"
  );

  assert.equal(
    resolveLandingRoute({
      allow_local_merge: true,
      unattended: true,
      merge_auto_approved: true,
      strategy: "repo-policy",
    }),
    "local-merge-then-push"
  );

  // allow_local_merge: true + unattended + merge_auto_approved: true + pull-request -> pull-request (strategy pull-request stays PR)
  assert.equal(
    resolveLandingRoute({
      allow_local_merge: true,
      orchestration: "goal",
      merge_auto_approved: true,
      strategy: "pull-request",
    }),
    "pull-request"
  );
}

// --- resolveIsolationPlan unit tests ---
// - worktree_policy.enabled absent -> true (create)
// - worktree_policy.enabled: false -> isolation skipped (reason: disabled)
// - already-linked-worktree -> isolation skipped (reason: already-isolated)
// - detached HEAD -> isolation skipped (reason: detached)
{
  // default enabled -> action: create
  assert.deepEqual(
    resolveIsolationPlan({
      worktree_enabled: true,
      is_linked_worktree: false,
      is_detached: false,
    }),
    { action: "create", reason: null }
  );

  // worktree_policy.enabled: false -> action: skip, reason: disabled
  assert.deepEqual(
    resolveIsolationPlan({
      worktree_enabled: false,
      is_linked_worktree: false,
      is_detached: false,
    }),
    { action: "skip", reason: "disabled" }
  );

  // already linked worktree -> action: skip, reason: already-isolated
  assert.deepEqual(
    resolveIsolationPlan({
      worktree_enabled: true,
      is_linked_worktree: true,
      is_detached: false,
    }),
    { action: "skip", reason: "already-isolated" }
  );

  // detached HEAD -> action: skip, reason: detached
  assert.deepEqual(
    resolveIsolationPlan({
      worktree_enabled: true,
      is_linked_worktree: false,
      is_detached: true,
    }),
    { action: "skip", reason: "detached" }
  );

  // detached takes precedence or handled cleanly
  assert.deepEqual(
    resolveIsolationPlan({
      worktree_enabled: false,
      is_linked_worktree: false,
      is_detached: true,
    }),
    { action: "skip", reason: "disabled" }
  );
}

process.stdout.write("test-dev-loop-isolation-landing: all checks passed\n");
NODE
