#!/usr/bin/env node
"use strict";

/**
 * Typed verification configuration + capability-driven agent dispatch resolver.
 *
 * Pure decision functions over repository config and platform capability maps.
 * Does not spawn agents; consumers invoke the returned actions with their
 * platform tools.
 */

const fs = require("node:fs");
const path = require("node:path");
const { parseDevLoopConfig } = require("./dev-loop-config-schema.js");

const SCHEMA_VERSION = "dev-loop-verification-dispatch.v1";

/** Built-in platform capability profiles (non-Claude platforms must not require Claude-only tools). */
const PLATFORM_CAPABILITIES = {
  claude: {
    spawn: "Agent",
    wait: "TaskOutput",
    cleanup: "none",
    model_default: "sonnet",
    isolation: "none",
    tools: ["Agent", "TaskOutput", "Skill"],
  },
  codex: {
    spawn: "spawn_agent",
    wait: "wait_agent",
    cleanup: "close_agent",
    model_default: null,
    isolation: "worktree",
    tools: ["spawn_agent", "wait_agent", "close_agent"],
  },
  grok: {
    spawn: "spawn_subagent",
    wait: "get_command_or_subagent_output",
    cleanup: "kill_command_or_subagent",
    model_default: null,
    isolation: "worktree",
    tools: ["spawn_subagent", "get_command_or_subagent_output", "kill_command_or_subagent"],
  },
};

function usage() {
  return [
    "Usage: dev-loop-verification-dispatch.js --repo <path> [options]",
    "",
    "Options:",
    "  --format <json|markdown>     Output format (default: json)",
    "  --platform <name>            Resolve dispatch for one platform",
    "  --help                       Show this help",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = { errors: [], format: "json", repo: "", platform: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help") {
      opts.help = true;
      continue;
    }
    if (arg === "--format" || arg === "--repo" || arg === "--platform") {
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) {
        opts.errors.push(`${arg} requires a value`);
        continue;
      }
      i += 1;
      if (arg === "--format") opts.format = value;
      else if (arg === "--repo") opts.repo = value;
      else opts.platform = value;
      continue;
    }
    opts.errors.push(`unknown argument: ${arg}`);
  }
  if (!opts.help && !opts.repo) opts.errors.push("--repo is required");
  if (!["json", "markdown"].includes(opts.format)) opts.errors.push("--format must be json or markdown");
  return opts;
}

function loadConfig(repo) {
  const configPath = path.join(repo, ".claude", "dev-loop.config.md");
  if (!fs.existsSync(configPath)) {
    return { missing: true, config: {}, configPath, parser: { errors: [], ok: true } };
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

/**
 * Normalize a verification entry into { kind: 'command'|'script', ... }.
 * Strings default to scripts (historical e2e_scripts list of paths/commands).
 * Objects may set type/kind or use command/script keys.
 */
function normalizeVerificationEntry(entry, defaultTimeout) {
  if (typeof entry === "string") {
    const trimmed = entry.trim();
    // Heuristic: paths ending in known script extensions or starting with ./ or scripts/
    const looksLikeScript =
      /\.(sh|js|mjs|cjs|py|ts)$/.test(trimmed) ||
      trimmed.startsWith("./") ||
      trimmed.startsWith("scripts/") ||
      trimmed.startsWith("bash scripts/");
    if (looksLikeScript) {
      return {
        kind: "script",
        path: trimmed.replace(/^bash\s+/, ""),
        run: trimmed,
        timeout_seconds: defaultTimeout,
      };
    }
    return {
      kind: "command",
      command: trimmed,
      timeout_seconds: defaultTimeout,
    };
  }
  if (!entry || typeof entry !== "object") {
    return { kind: "invalid", error: "entry must be string or object", timeout_seconds: defaultTimeout };
  }
  const timeout =
    Number.isInteger(entry.timeout_seconds) && entry.timeout_seconds > 0
      ? entry.timeout_seconds
      : defaultTimeout;
  const kind = (entry.kind || entry.type || "").toLowerCase();
  if (kind === "command" || entry.command) {
    const command = entry.command || entry.run || entry.cmd;
    if (typeof command !== "string" || !command.trim()) {
      return { kind: "invalid", error: "command entry missing command string", timeout_seconds: timeout };
    }
    return { kind: "command", command: command.trim(), timeout_seconds: timeout, cwd: entry.cwd || null };
  }
  if (kind === "script" || entry.script || entry.path) {
    const scriptPath = entry.script || entry.path || entry.run;
    if (typeof scriptPath !== "string" || !scriptPath.trim()) {
      return { kind: "invalid", error: "script entry missing path", timeout_seconds: timeout };
    }
    return {
      kind: "script",
      path: scriptPath.trim(),
      run: entry.run || scriptPath.trim(),
      timeout_seconds: timeout,
      cwd: entry.cwd || null,
    };
  }
  return { kind: "invalid", error: "unknown verification entry shape", timeout_seconds: timeout };
}

function resolveVerification(config) {
  const block = config.verification || {};
  const defaultTimeout =
    Number.isInteger(block.timeout_seconds) && block.timeout_seconds > 0
      ? block.timeout_seconds
      : 600;
  const required = block.required !== false;
  const allowFailure = block.allow_failure === true;

  const commands = [];
  const scripts = [];
  const errors = [];

  for (const raw of block.commands || []) {
    const n = normalizeVerificationEntry(
      typeof raw === "string" ? { kind: "command", command: raw } : raw,
      defaultTimeout,
    );
    if (n.kind === "invalid") errors.push(n);
    else if (n.kind === "command") commands.push(n);
    else scripts.push(n);
  }
  for (const raw of block.scripts || []) {
    const n = normalizeVerificationEntry(
      typeof raw === "string" ? { kind: "script", path: raw } : raw,
      defaultTimeout,
    );
    if (n.kind === "invalid") errors.push(n);
    else if (n.kind === "script") scripts.push(n);
    else commands.push(n);
  }

  // Legacy e2e_scripts: treat as scripts/commands via string heuristic
  for (const raw of config.e2e_scripts || []) {
    const n = normalizeVerificationEntry(raw, defaultTimeout);
    if (n.kind === "invalid") errors.push(n);
    else if (n.kind === "script") scripts.push(n);
    else commands.push(n);
  }

  return {
    default_timeout_seconds: defaultTimeout,
    required,
    allow_failure: allowFailure,
    commands,
    scripts,
    entries: [...commands, ...scripts],
    errors,
  };
}

function mergeCapabilities(platformName, configDispatch) {
  const base = PLATFORM_CAPABILITIES[platformName]
    ? { ...PLATFORM_CAPABILITIES[platformName] }
    : null;
  const configured = configDispatch?.platforms?.[platformName] || {};
  const top = configDispatch || {};

  const spawn = configured.spawn || top.spawn || base?.spawn || null;
  const wait = configured.wait || top.wait || base?.wait || null;
  const cleanup = configured.cleanup || top.cleanup || base?.cleanup || "none";
  const model = configured.model || top.model || base?.model_default || null;
  const isolation = configured.isolation || top.isolation || base?.isolation || "none";
  const tools = configured.capabilities || base?.tools || [];

  return {
    platform: platformName,
    known: Boolean(base),
    spawn,
    wait,
    cleanup,
    model,
    isolation,
    tools: Array.isArray(tools) ? tools : [],
    requires_claude_tools: false,
  };
}

/**
 * Resolve dispatch plan for a platform. Non-Claude platforms must not require
 * Claude-only tools (Agent, Skill as spawn path).
 */
function resolveDispatch(platformName, config, capabilityOverride) {
  const dispatchCfg = config.dispatch || {};
  let plan = mergeCapabilities(platformName, dispatchCfg);
  if (capabilityOverride && typeof capabilityOverride === "object") {
    plan = {
      ...plan,
      ...capabilityOverride,
      platform: platformName,
      tools: capabilityOverride.tools || plan.tools,
    };
  }

  const claudeOnly = new Set(["Agent", "TaskOutput", "Skill"]);
  const usesClaudeOnly =
    claudeOnly.has(plan.spawn) || claudeOnly.has(plan.wait) || claudeOnly.has(plan.cleanup);

  if (platformName !== "claude" && usesClaudeOnly) {
    return {
      ...plan,
      ok: false,
      requires_claude_tools: true,
      error: `platform ${platformName} must not use Claude-only tools for spawn/wait/cleanup`,
    };
  }

  if (!plan.spawn || !plan.wait) {
    return {
      ...plan,
      ok: false,
      requires_claude_tools: usesClaudeOnly,
      error: `platform ${platformName} missing spawn or wait capability`,
    };
  }

  return {
    ...plan,
    ok: true,
    requires_claude_tools: platformName === "claude" ? usesClaudeOnly : false,
    error: null,
  };
}

function resolveAllPlatforms(config, overrides = {}) {
  const names = new Set([
    ...Object.keys(PLATFORM_CAPABILITIES),
    ...Object.keys(config.dispatch?.platforms || {}),
    ...Object.keys(overrides),
  ]);
  const out = {};
  for (const name of names) {
    out[name] = resolveDispatch(name, config, overrides[name]);
  }
  return out;
}

function buildReport(opts, capabilityOverrides = {}) {
  const cfg = loadConfig(opts.repo);
  const verification = resolveVerification(cfg.config || {});
  const platforms = resolveAllPlatforms(cfg.config || {}, capabilityOverrides);
  const selected = opts.platform ? platforms[opts.platform] || null : null;

  const errors = [...(verification.errors || [])];
  if (opts.platform && !selected) {
    errors.push({ kind: "dispatch", error: `unknown platform: ${opts.platform}` });
  }
  for (const [name, plan] of Object.entries(platforms)) {
    if (plan.ok === false) {
      errors.push({ kind: "dispatch", platform: name, error: plan.error });
    }
  }

  return {
    schema_version: SCHEMA_VERSION,
    generated_at: new Date().toISOString(),
    read_only: true,
    writes_executed: false,
    config_path: cfg.configPath,
    verification,
    dispatch: {
      platforms,
      selected_platform: opts.platform || null,
      selected: selected,
    },
    errors,
    ok: errors.length === 0 && (!selected || selected.ok !== false),
  };
}

function renderMarkdown(json) {
  const lines = [
    "# Dev-loop Verification & Dispatch",
    "",
    `- OK: **${json.ok}**`,
    `- Default timeout: ${json.verification.default_timeout_seconds}s`,
    "",
    "## Verification entries",
  ];
  for (const e of json.verification.entries || []) {
    if (e.kind === "command") {
      lines.push(`- command: \`${e.command}\` (timeout ${e.timeout_seconds}s)`);
    } else {
      lines.push(`- script: \`${e.path}\` (timeout ${e.timeout_seconds}s)`);
    }
  }
  if (!(json.verification.entries || []).length) lines.push("- (none)");
  lines.push("", "## Platforms");
  for (const [name, plan] of Object.entries(json.dispatch.platforms || {})) {
    lines.push(
      `- ${name}: spawn=${plan.spawn} wait=${plan.wait} cleanup=${plan.cleanup} model=${plan.model || "-"} isolation=${plan.isolation} ok=${plan.ok}`,
    );
  }
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
  return json.ok ? 0 : 1;
}

module.exports = {
  SCHEMA_VERSION,
  PLATFORM_CAPABILITIES,
  normalizeVerificationEntry,
  resolveVerification,
  resolveDispatch,
  resolveAllPlatforms,
  buildReport,
  parseArgs,
  loadConfig,
};

if (require.main === module) {
  process.exitCode = main();
}
