"use strict";

const LANDING_ROUTES = Object.freeze([
  "attended-menu",
  "pull-request",
  "local-merge-then-push",
]);

const ISOLATION_ACTIONS = Object.freeze([
  "create",
  "skip",
]);

const ISOLATION_REASONS = Object.freeze([
  "already-isolated",
  "disabled",
  "detached",
]);

/**
 * Parses and normalizes merge_policy from raw config.
 * @param {object} [config]
 * @returns {{strategy: string, auto_merge: boolean, merge_method: string, require_work_item_approval: boolean, allow_local_merge: boolean}}
 */
function parseMergePolicy(config) {
  const defaults = {
    strategy: "repo-policy",
    auto_merge: false,
    merge_method: "squash",
    require_work_item_approval: true,
    allow_local_merge: false,
  };
  const policy = config?.merge_policy || {};
  const configuredStrategy = policy.strategy || defaults.strategy;
  return {
    strategy: configuredStrategy === "branch-policy" ? "repo-policy" : configuredStrategy,
    auto_merge: policy.auto_merge ?? defaults.auto_merge,
    merge_method: policy.merge_method || defaults.merge_method,
    require_work_item_approval:
      policy.require_work_item_approval ?? defaults.require_work_item_approval,
    allow_local_merge: policy.allow_local_merge ?? defaults.allow_local_merge,
  };
}

/**
 * Parses and normalizes worktree_policy from raw config.
 * @param {object} [config]
 * @returns {{enabled: boolean}}
 */
function parseWorktreePolicy(config) {
  const defaults = {
    enabled: true,
  };
  const policy = config?.worktree_policy || {};
  return {
    enabled: policy.enabled ?? defaults.enabled,
  };
}

/**
 * Resolves the landing route given merge policy and execution mode context.
 *
 * Rules:
 * - allow_local_merge absent / false -> 'pull-request'
 * - allow_local_merge: true + attended -> 'attended-menu'
 * - allow_local_merge: true + unattended + merge_auto_approved: false -> 'pull-request'
 * - allow_local_merge: true + unattended + merge_auto_approved: true + repo-policy -> 'local-merge-then-push'
 * - otherwise (e.g. strategy !== repo-policy) -> 'pull-request'
 *
 * @param {object} context
 * @param {boolean} [context.allow_local_merge=false]
 * @param {string} [context.orchestration="attended"]
 * @param {boolean} [context.unattended=false]
 * @param {boolean} [context.merge_auto_approved=false]
 * @param {string} [context.strategy="repo-policy"]
 * @returns {"attended-menu"|"pull-request"|"local-merge-then-push"}
 */
function resolveLandingRoute(context = {}) {
  const allowLocalMerge = context.allow_local_merge === true;
  if (!allowLocalMerge) {
    return "pull-request";
  }

  const isUnattended = context.unattended === true || context.orchestration === "goal";
  if (!isUnattended) {
    return "attended-menu";
  }

  const mergeAutoApproved = context.merge_auto_approved === true;
  const strategy = context.strategy || "repo-policy";

  if (mergeAutoApproved && strategy === "repo-policy") {
    return "local-merge-then-push";
  }

  return "pull-request";
}

/**
 * Resolves whether to create an isolated worktree or skip isolation.
 *
 * Rules:
 * - worktree_enabled === false -> skip with reason "disabled"
 * - is_linked_worktree === true -> skip with reason "already-isolated"
 * - is_detached === true -> skip with reason "detached"
 * - otherwise -> create
 *
 * @param {object} context
 * @param {boolean} [context.worktree_enabled=true]
 * @param {boolean} [context.is_linked_worktree=false]
 * @param {boolean} [context.is_detached=false]
 * @returns {{action: "create"|"skip", reason: "already-isolated"|"disabled"|"detached"|null}}
 */
function resolveIsolationPlan(context = {}) {
  const worktreeEnabled = context.worktree_enabled ?? true;
  if (!worktreeEnabled) {
    return { action: "skip", reason: "disabled" };
  }
  if (context.is_linked_worktree === true) {
    return { action: "skip", reason: "already-isolated" };
  }
  if (context.is_detached === true) {
    return { action: "skip", reason: "detached" };
  }
  return { action: "create", reason: null };
}

module.exports = {
  ISOLATION_ACTIONS,
  ISOLATION_REASONS,
  LANDING_ROUTES,
  parseMergePolicy,
  parseWorktreePolicy,
  resolveIsolationPlan,
  resolveLandingRoute,
};
