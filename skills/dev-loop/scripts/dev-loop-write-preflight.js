#!/usr/bin/env node
"use strict";

/**
 * Deterministic git / worktree / task-sandbox write preflight.
 *
 * Read-only: never mutates the repository. Call before MERGE/PUSH/SAVE commits
 * or pushes. Exit 0 only when writes are allowed; non-zero on policy refusal.
 */

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { parseDevLoopConfig } = require("./dev-loop-config-schema.js");

const SCHEMA_VERSION = "dev-loop-write-preflight.v1";

function usage() {
  return [
    "Usage: dev-loop-write-preflight.js --repo <path> [options]",
    "",
    "Options:",
    "  --format <json|markdown>   Output format (default: json)",
    "  --intent <write|commit|push>  Intended mutation (default: write)",
    "  --sandbox-owner <token>    Expected task-sandbox owner token",
    "  --no-write                 Alias for default (preflight never writes)",
    "  --help                     Show this help",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = {
    errors: [],
    format: "json",
    intent: "write",
    repo: "",
    sandboxOwner: "",
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help") {
      opts.help = true;
      continue;
    }
    if (arg === "--no-write") continue;
    if (arg === "--format" || arg === "--intent" || arg === "--repo" || arg === "--sandbox-owner") {
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) {
        opts.errors.push(`${arg} requires a value`);
        continue;
      }
      i += 1;
      if (arg === "--format") opts.format = value;
      else if (arg === "--intent") opts.intent = value;
      else if (arg === "--repo") opts.repo = value;
      else opts.sandboxOwner = value;
      continue;
    }
    opts.errors.push(`unknown argument: ${arg}`);
  }
  if (!opts.help && !opts.repo) opts.errors.push("--repo is required");
  if (!["json", "markdown"].includes(opts.format)) {
    opts.errors.push("--format must be json or markdown");
  }
  if (!["write", "commit", "push"].includes(opts.intent)) {
    opts.errors.push("--intent must be write, commit, or push");
  }
  return opts;
}

function git(repo, args) {
  const r = spawnSync("git", args, {
    cwd: repo,
    encoding: "utf8",
    timeout: 30000,
    env: process.env,
  });
  if (r.error) {
    return { ok: false, code: r.error.code || "spawn_error", stdout: "", stderr: String(r.error.message || r.error) };
  }
  return {
    ok: r.status === 0,
    code: r.status,
    stdout: (r.stdout || "").trim(),
    stderr: (r.stderr || "").trim(),
  };
}

function resolvePhysical(p) {
  try {
    return fs.realpathSync(p);
  } catch {
    return path.resolve(p);
  }
}

function loadConfig(repo) {
  const configPath = path.join(repo, ".claude", "dev-loop.config.md");
  if (!fs.existsSync(configPath)) {
    return { missing: true, config: {}, parser: { errors: [], ok: true }, configPath };
  }
  const parser = parseDevLoopConfig(configPath);
  const invalid = parser.ok === false || (parser.errors || []).length > 0;
  return {
    missing: false,
    configPath,
    config: invalid ? {} : parser.config || {},
    parser,
  };
}

function defaultPolicy(config) {
  const releaseBranch = config.release_branch || "main";
  const branch = config.branch_policy || {};
  const worktree = config.worktree_policy || {};
  const sandbox = config.task_sandbox || {};
  const merge = config.merge_policy || {};
  return {
    release_branch: releaseBranch,
    direct_push_to_release_branch:
      branch.direct_push_to_release_branch === true ||
      merge.strategy === "branch-policy",
    require_feature_branch:
      branch.require_feature_branch === true ||
      merge.strategy === "pull-request" ||
      worktree.required === true,
    feature_branch_pattern: branch.feature_branch_pattern || worktree.feature_branch_pattern || "",
    allow_detached: worktree.allow_detached === true,
    allow_submodules: worktree.allow_submodules !== false,
    sandbox_required: sandbox.required === true,
    sandbox_owner: sandbox.owner || "",
    sandbox_root: sandbox.root || "",
    ownership_file: sandbox.ownership_file || ".dev-loop-sandbox-owner",
  };
}

function matchesFeaturePattern(branch, pattern) {
  if (!pattern) return true;
  // Glob-ish: * only
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
  return new RegExp(`^${escaped}$`).test(branch);
}

function probeGitIdentity(repo) {
  const top = git(repo, ["rev-parse", "--show-toplevel"]);
  if (!top.ok) {
    return {
      ok: false,
      refusals: [{ code: "not_a_git_repo", detail: top.stderr || "git rev-parse --show-toplevel failed" }],
      identity: null,
    };
  }
  const gitDirRaw = git(repo, ["rev-parse", "--git-dir"]);
  const commonRaw = git(repo, ["rev-parse", "--git-common-dir"]);
  const branchRaw = git(repo, ["branch", "--show-current"]);
  const headRaw = git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]);
  const superRaw = git(repo, ["rev-parse", "--show-superproject-working-tree"]);
  const submoduleStatus = git(repo, ["submodule", "status", "--recursive"]);

  const gitDir = gitDirRaw.ok ? resolvePhysical(path.resolve(repo, gitDirRaw.stdout)) : "";
  const commonDir = commonRaw.ok ? resolvePhysical(path.resolve(repo, commonRaw.stdout)) : "";
  const branch = branchRaw.ok ? branchRaw.stdout : "";
  const headName = headRaw.ok ? headRaw.stdout : "";
  const detached = !branch || headName === "HEAD";
  const linkedWorktree = Boolean(gitDir && commonDir && gitDir !== commonDir);
  const superproject = superRaw.ok && superRaw.stdout ? superRaw.stdout : "";
  const inSubmodule = Boolean(superproject);

  let submoduleDirty = false;
  let submoduleLines = [];
  if (submoduleStatus.ok && submoduleStatus.stdout) {
    submoduleLines = submoduleStatus.stdout.split("\n").filter(Boolean);
    // git submodule status: leading space = clean, + = different commit, - = not initialized, U = conflict
    submoduleDirty = submoduleLines.some((line) => line[0] === "+" || line[0] === "-" || line[0] === "U");
  }
  // Also treat dirty submodule working trees (uncommitted content) as blocked for push.
  const submoduleForeach = git(repo, [
    "submodule",
    "foreach",
    "--quiet",
    "git status --porcelain",
  ]);
  if (submoduleForeach.ok && submoduleForeach.stdout.trim()) {
    submoduleDirty = true;
  }

  return {
    ok: true,
    refusals: [],
    identity: {
      toplevel: resolvePhysical(top.stdout),
      git_dir: gitDir,
      common_dir: commonDir,
      linked_worktree: linkedWorktree,
      branch: branch || null,
      head: headName || null,
      detached,
      superproject: superproject || null,
      in_submodule: inSubmodule,
      submodule_status_lines: submoduleLines,
      submodule_dirty: submoduleDirty,
    },
  };
}

function probeSandbox(repo, policy, expectedOwner) {
  const root = policy.sandbox_root
    ? path.isAbsolute(policy.sandbox_root)
      ? policy.sandbox_root
      : path.join(repo, policy.sandbox_root)
    : repo;
  const ownershipPath = path.join(root, policy.ownership_file);
  let recorded = null;
  if (fs.existsSync(ownershipPath)) {
    try {
      const raw = fs.readFileSync(ownershipPath, "utf8").trim();
      try {
        const parsed = JSON.parse(raw);
        recorded = parsed.owner || parsed.token || raw;
      } catch {
        recorded = raw;
      }
    } catch {
      recorded = null;
    }
  }
  const expected = expectedOwner || policy.sandbox_owner || "";
  return {
    root,
    ownership_file: ownershipPath,
    ownership_present: fs.existsSync(ownershipPath),
    recorded_owner: recorded,
    expected_owner: expected || null,
    matches: expected ? recorded === expected : recorded !== null || !policy.sandbox_required,
  };
}

function evaluateWritePermission(identity, policy, sandbox, intent) {
  const refusals = [];
  const permissions = {
    may_write: true,
    may_commit: true,
    may_push: true,
    may_create_pr: true,
  };

  if (identity.detached && !policy.allow_detached) {
    refusals.push({
      code: "detached_head",
      detail: "detached HEAD / externally-managed sandbox — commit in place only; refuse push/PR",
    });
    permissions.may_push = false;
    permissions.may_create_pr = false;
  }

  if (identity.in_submodule && !policy.allow_submodules) {
    refusals.push({
      code: "submodule_checkout",
      detail: `repository is a submodule of ${identity.superproject}`,
    });
    permissions.may_write = false;
    permissions.may_commit = false;
    permissions.may_push = false;
    permissions.may_create_pr = false;
  }

  if (identity.submodule_dirty) {
    refusals.push({
      code: "submodule_dirty",
      detail: "git submodule status reports dirty, missing, or conflicted submodules",
    });
    permissions.may_push = false;
  }

  const onRelease =
    identity.branch !== null && identity.branch === policy.release_branch;

  if (onRelease && !policy.direct_push_to_release_branch) {
    refusals.push({
      code: "release_branch_write_refused",
      detail: `policy forbids commit/push on release branch ${policy.release_branch}`,
    });
    permissions.may_commit = false;
    permissions.may_push = false;
  }

  if (policy.require_feature_branch && !identity.detached) {
    if (!identity.branch) {
      refusals.push({
        code: "feature_branch_required",
        detail: "repository policy requires a named feature branch before writes",
      });
      permissions.may_commit = false;
      permissions.may_push = false;
    } else if (onRelease) {
      refusals.push({
        code: "feature_branch_required",
        detail: `on release branch ${policy.release_branch}; switch to a feature branch`,
      });
      permissions.may_commit = false;
      permissions.may_push = false;
    } else if (!matchesFeaturePattern(identity.branch, policy.feature_branch_pattern)) {
      refusals.push({
        code: "feature_branch_pattern_mismatch",
        detail: `branch ${identity.branch} does not match ${policy.feature_branch_pattern}`,
      });
      permissions.may_commit = false;
      permissions.may_push = false;
    }
  }

  if (policy.sandbox_required) {
    if (!sandbox.ownership_present) {
      refusals.push({
        code: "sandbox_ownership_missing",
        detail: `missing sandbox ownership file ${sandbox.ownership_file}`,
      });
      permissions.may_write = false;
      permissions.may_commit = false;
      permissions.may_push = false;
    } else if (sandbox.expected_owner && !sandbox.matches) {
      refusals.push({
        code: "sandbox_ownership_mismatch",
        detail: `expected owner ${sandbox.expected_owner}, found ${sandbox.recorded_owner || "(empty)"}`,
      });
      permissions.may_write = false;
      permissions.may_commit = false;
      permissions.may_push = false;
    }
  }

  let allowed = permissions.may_write;
  if (intent === "commit") allowed = permissions.may_write && permissions.may_commit;
  if (intent === "push") {
    allowed = permissions.may_write && permissions.may_commit && permissions.may_push;
  }

  return { allowed, permissions, refusals };
}

function buildReport(opts) {
  const cfg = loadConfig(opts.repo);
  const policy = defaultPolicy(cfg.config || {});
  const probed = probeGitIdentity(opts.repo);
  if (!probed.ok) {
    return {
      schema_version: SCHEMA_VERSION,
      generated_at: new Date().toISOString(),
      read_only: true,
      writes_executed: false,
      intent: opts.intent,
      allowed: false,
      exit_reason: "not_a_git_repo",
      policy,
      identity: null,
      sandbox: null,
      permissions: {
        may_write: false,
        may_commit: false,
        may_push: false,
        may_create_pr: false,
      },
      refusals: probed.refusals,
      config_path: cfg.configPath,
      config_parser_errors: cfg.parser?.errors || [],
    };
  }

  const sandbox = probeSandbox(opts.repo, policy, opts.sandboxOwner);
  const decision = evaluateWritePermission(probed.identity, policy, sandbox, opts.intent);

  return {
    schema_version: SCHEMA_VERSION,
    generated_at: new Date().toISOString(),
    read_only: true,
    writes_executed: false,
    intent: opts.intent,
    allowed: decision.allowed,
    exit_reason: decision.allowed ? "ok" : (decision.refusals[0]?.code || "refused"),
    policy,
    identity: probed.identity,
    sandbox: {
      root: sandbox.root,
      ownership_file: sandbox.ownership_file,
      ownership_present: sandbox.ownership_present,
      recorded_owner: sandbox.recorded_owner,
      expected_owner: sandbox.expected_owner,
      matches: sandbox.matches,
    },
    permissions: decision.permissions,
    refusals: decision.refusals,
    config_path: cfg.configPath,
    config_parser_errors: (cfg.parser?.errors || []).map((e) => ({
      code: e.code,
      message: e.message,
      path: e.path || null,
      line: e.line ?? null,
    })),
  };
}

function renderMarkdown(json) {
  const lines = [
    "# Dev-loop Write Preflight",
    "",
    `- Allowed: **${json.allowed}**`,
    `- Intent: ${json.intent}`,
    `- Exit reason: ${json.exit_reason}`,
    "",
    "## Git identity",
  ];
  if (!json.identity) {
    lines.push("- (unavailable)");
  } else {
    lines.push(`- Branch: ${json.identity.branch || "(detached)"}`);
    lines.push(`- Detached: ${json.identity.detached}`);
    lines.push(`- Linked worktree: ${json.identity.linked_worktree}`);
    lines.push(`- git-dir: ${json.identity.git_dir}`);
    lines.push(`- common-dir: ${json.identity.common_dir}`);
    lines.push(`- Submodule: ${json.identity.in_submodule}`);
    lines.push(`- Submodule dirty: ${json.identity.submodule_dirty}`);
  }
  lines.push("", "## Permissions");
  for (const [k, v] of Object.entries(json.permissions || {})) {
    lines.push(`- ${k}: ${v}`);
  }
  lines.push("", "## Refusals");
  if (!json.refusals?.length) lines.push("- (none)");
  else for (const r of json.refusals) lines.push(`- \`${r.code}\`: ${r.detail}`);
  lines.push("");
  return lines.join("\n");
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    process.stdout.write(`${usage()}\n`);
    return 0;
  }
  if (opts.errors.length > 0) {
    process.stderr.write(`${opts.errors.join("\n")}\n`);
    return 2;
  }
  const json = buildReport(opts);
  if (opts.format === "markdown") process.stdout.write(renderMarkdown(json));
  else process.stdout.write(`${JSON.stringify(json, null, 2)}\n`);
  return json.allowed ? 0 : 1;
}

module.exports = {
  SCHEMA_VERSION,
  buildReport,
  evaluateWritePermission,
  defaultPolicy,
  matchesFeaturePattern,
  probeGitIdentity,
  probeSandbox,
  loadConfig,
  parseArgs,
};

if (require.main === module) {
  process.exitCode = main();
}
