#!/usr/bin/env node
"use strict";

/**
 * Read-only dev-loop status probe. No vault writes, git commits, pushes, or PRs.
 * Writes reports only under .claude/dev-loop/status/ in the target repo.
 */

const { spawnSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const SCHEMA_VERSION = "dev-loop-status.v1";

function usage() {
  return [
    "Usage: dev-loop-status.js --repo <path> [options]",
    "",
    "Options:",
    "  --format <markdown|json|both>   Output format (default: both)",
    "  --project <slug>                Project slug (default: from config or dirname)",
    "  --vault <path>                  Vault path override",
    "  --intensity <normal|high>       Intensity hint (default: normal)",
    "  --preview-mode <core|prep|investigate|status>  Simulated next mode (default: core)",
    "  --orchestration <attended|goal> Unattended /goal simulation (default: attended)",
    "  --no-write                      Print to stdout only; do not write .claude/dev-loop/status/",
    "  --help                          Show this help",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = {
    errors: [],
    format: "both",
    intensity: "normal",
    noWrite: false,
    orchestration: "attended",
    previewMode: "core",
    project: "",
    repo: "",
    vault: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help") {
      opts.help = true;
      continue;
    }
    if (arg === "--no-write") {
      opts.noWrite = true;
      continue;
    }
    const needs = [
      "--repo",
      "--format",
      "--project",
      "--vault",
      "--intensity",
      "--preview-mode",
      "--orchestration",
    ];
    if (needs.includes(arg)) {
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) {
        opts.errors.push(`${arg} requires a value`);
        continue;
      }
      i += 1;
      if (arg === "--repo") opts.repo = path.resolve(value);
      else if (arg === "--format") opts.format = value;
      else if (arg === "--project") opts.project = value;
      else if (arg === "--vault") opts.vault = value;
      else if (arg === "--intensity") opts.intensity = value;
      else if (arg === "--preview-mode") opts.previewMode = value;
      else if (arg === "--orchestration") opts.orchestration = value;
    }
  }

  if (!opts.repo && !opts.help) {
    opts.repo = process.cwd();
  }
  return opts;
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function fileExists(p) {
  try {
    fs.accessSync(p, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function extractYamlBlocks(text) {
  const blocks = [];
  const re = /```ya?ml\n([\s\S]*?)```/gi;
  let m;
  while ((m = re.exec(text)) !== null) {
    blocks.push(m[1]);
  }
  return blocks;
}

function parseSimpleYaml(text) {
  const data = {};
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const match = trimmed.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    const key = match[1];
    let val = match[2].trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (val === "true") data[key] = true;
    else if (val === "false") data[key] = false;
    else if (/^\d+$/.test(val)) data[key] = Number(val);
    else data[key] = val;
  }
  return data;
}

function mergeConfigBlocks(blocks) {
  const merged = {};
  for (const block of blocks) {
    Object.assign(merged, parseSimpleYaml(block));
  }
  return merged;
}

function loadDevLoopConfig(repo) {
  const configPath = path.join(repo, ".claude", "dev-loop.config.md");
  if (!fileExists(configPath)) {
    return { configPath, flat: {}, raw: null };
  }
  const raw = readText(configPath);
  const flat = mergeConfigBlocks(extractYamlBlocks(raw));
  return { configPath, flat, raw };
}

function resolveSkillwikiPath() {
  const r = spawnSync("skillwiki", ["path"], { encoding: "utf8", timeout: 15000 });
  if (r.status !== 0 || !r.stdout.trim()) return "";
  const out = r.stdout.trim();
  try {
    const j = JSON.parse(out);
    if (j.data && typeof j.data.path === "string") return j.data.path;
    if (typeof j.path === "string") return j.path;
  } catch {
    if (!out.startsWith("{")) return out;
  }
  return "";
}

function vaultFromConfigRaw(raw) {
  if (!raw) return "";
  const m = raw.match(/knowledge_backends:\s*\n[\s\S]*?skillwiki:\s*\n[\s\S]*?vault:\s*(\S+)/);
  if (m) return m[1].replace(/"/g, "");
  const legacy = raw.match(/^vault:\s*(\S+)/m);
  return legacy ? legacy[1].replace(/"/g, "") : "";
}

function resolveVault(repo, flat, vaultOverride, configRaw) {
  if (vaultOverride) {
    return { path: vaultOverride, configured: true, resolved: fileExists(vaultOverride), warning: null };
  }
  const layer = flat.knowledge_layer || "";
  if (layer === "none") {
    return { path: null, configured: false, resolved: false, warning: "knowledge_layer: none" };
  }
  let configuredPath = flat.vault || vaultFromConfigRaw(configRaw) || "";
  if (!configuredPath) {
    configuredPath = resolveSkillwikiPath();
    if (!configuredPath) {
      const fallback = path.join(os.homedir(), "wiki");
      if (fileExists(path.join(fallback, "SCHEMA.md")) && fileExists(path.join(fallback, "projects"))) {
        return {
          path: fallback,
          configured: true,
          resolved: true,
          warning: "vault: auto could not resolve via skillwiki path; using validated ~/wiki fallback",
        };
      }
      return {
        path: null,
        configured: true,
        resolved: false,
        warning: "vault could not be resolved (skillwiki path failed, no ~/wiki fallback)",
      };
    }
  }
  if (configuredPath === "auto") {
    configuredPath = resolveSkillwikiPath() || configuredPath;
  }
  return {
    path: configuredPath || null,
    configured: true,
    resolved: configuredPath ? fileExists(configuredPath) : false,
    warning: configuredPath && !fileExists(configuredPath) ? `configured vault path missing: ${configuredPath}` : null,
  };
}

function globMatch(relPath, pattern) {
  const norm = relPath.split(path.sep).join("/");
  const esc = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(
    `^${esc.replace(/\*\*/g, "§§").replace(/\*/g, "[^/]*").replace(/§§/g, ".*").replace(/\?/g, ".")}$`,
  );
  return re.test(norm);
}

function anyGlobMatch(file, patterns) {
  if (!patterns || patterns.length === 0) return false;
  return patterns.some((pattern) => globMatch(file, pattern));
}

function gitLines(repo, args) {
  const r = spawnSync("git", args, { cwd: repo, encoding: "utf8", timeout: 30000 });
  if (r.status !== 0) return [];
  return r.stdout
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
}

function parseReleasePolicyFromConfig(raw) {
  if (!raw) return null;
  const m = raw.match(/release_policy:\s*\n([\s\S]*?)(?=\n```|\n## |\n[a-z_]+:)/i);
  if (!m) return null;
  const block = m[1];
  const policy = { auto_bump: /auto_bump:\s*true/.test(block) };
  const tg = [];
  const sg = [];
  let inTrigger = false;
  let inSkip = false;
  for (const line of block.split(/\r?\n/)) {
    if (/trigger_globs:/.test(line)) inTrigger = true;
    else if (/skip_globs:/.test(line)) {
      inTrigger = false;
      inSkip = true;
    } else if (/^\s{2}[a-z_]/.test(line) && !/^\s+-/.test(line)) {
      inTrigger = false;
      inSkip = false;
    }
    const item = line.match(/^\s+-\s+"?([^"]+)"?\s*$/);
    if (item) {
      if (inTrigger) tg.push(item[1]);
      if (inSkip) sg.push(item[1]);
    }
  }
  policy.trigger_globs = tg;
  policy.skip_globs = sg;
  return policy;
}

function parseBrowserVerificationFromConfig(raw) {
  if (!raw) return null;
  const m = raw.match(/browser_verification:\s*\n([\s\S]*?)(?=\n```|\n## |\n[a-z_]+:)/i);
  if (!m) return null;
  const block = m[1];
  const enabled = /enabled:\s*true/.test(block);
  const triggers = [];
  let inTrigger = false;
  for (const line of block.split(/\r?\n/)) {
    if (/^\s*trigger:\s*$/.test(line)) inTrigger = true;
    else if (/^\s{2}[a-z_]/.test(line) && !/^\s+-/.test(line)) {
      inTrigger = false;
    }
    const item = line.match(/^\s+-\s+"?([^"]+)"?\s*$/);
    if (item && inTrigger) triggers.push(item[1]);
  }
  return { enabled, trigger: triggers };
}

function parseMergePolicyFromConfig(raw) {
  const defaults = {
    strategy: "repo-policy",
    auto_merge: false,
    merge_method: "squash",
    require_work_item_approval: true,
  };
  if (!raw) return defaults;
  const block = raw.match(/^merge_policy:\s*\n((?:[ \t]+.*(?:\n|$))*)/m);
  if (!block) return defaults;
  const text = block[1];
  const scalar = (key) => {
    const match = text.match(new RegExp(`^\\s+${key}:\\s*([^#\\n]+)`, "m"));
    return match ? match[1].trim().replace(/^['"]|['"]$/g, "") : "";
  };
  const bool = (key, fallback) => {
    const value = scalar(key);
    if (value === "true") return true;
    if (value === "false") return false;
    return fallback;
  };
  const configuredStrategy = scalar("strategy") || defaults.strategy;
  return {
    strategy: configuredStrategy === "branch-policy" ? "repo-policy" : configuredStrategy,
    auto_merge: bool("auto_merge", defaults.auto_merge),
    merge_method: scalar("merge_method") || defaults.merge_method,
    require_work_item_approval: bool(
      "require_work_item_approval",
      defaults.require_work_item_approval,
    ),
  };
}

function collectChangedFiles(repo) {
  const unstaged = gitLines(repo, ["diff", "--name-only", "HEAD"]);
  const staged = gitLines(repo, ["diff", "--cached", "--name-only"]);
  return [...new Set([...unstaged, ...staged])];
}

function browserVerifyPreview(repo, configRaw, missingOptional) {
  const cfg = parseBrowserVerificationFromConfig(configRaw);
  if (!cfg) {
    return { would_run: false, reason: "browser_verification absent or disabled in config" };
  }
  if (!cfg.enabled) {
    return { would_run: false, reason: "browser_verification.enabled is false" };
  }
  const triggers = cfg.trigger || [];
  if (triggers.length === 0) {
    return { would_run: false, reason: "browser_verification.trigger empty — gate skipped" };
  }
  const changed = collectChangedFiles(repo);
  const matched = changed.filter((file) => anyGlobMatch(file, triggers));
  if (matched.length === 0) {
    return {
      would_run: false,
      reason: "no changed files match browser_verification.trigger globs",
    };
  }
  const needsPlaywright = missingOptional.some((d) => /playwright/i.test(d));
  if (needsPlaywright) {
    return {
      would_run: false,
      reason: "trigger matched but playwright-cli driver dep missing (degraded)",
      matched_files: matched.slice(0, 10),
    };
  }
  return {
    would_run: true,
    reason: `would run BROWSER-VERIFY for ${matched.length} matching file(s)`,
    matched_files: matched.slice(0, 10),
  };
}

function releasePreview(repo, flat, configRaw) {
  const publishVia = flat.publish_via || "";
  const policy = parseReleasePolicyFromConfig(configRaw) || null;
  if (!publishVia || publishVia === "none") {
    return { would_publish: false, reason: "publish_via unset or none" };
  }
  if (!policy) {
    return {
      would_publish: false,
      reason: "publish_via set but release_policy block absent — manual bump expected before PUSH",
    };
  }
  if (!policy.auto_bump) {
    return { would_publish: false, reason: "release_policy.auto_bump is false — PUSH only after manual bump" };
  }
  const triggerGlobs = policy.trigger_globs || [];
  const skipGlobs = policy.skip_globs || [];
  if (triggerGlobs.length === 0) {
    return { would_publish: false, reason: "auto_bump true but trigger_globs empty — no bump would fire" };
  }
  const lastTag = gitLines(repo, ["describe", "--tags", "--abbrev=0"])[0] || "";
  const range = lastTag ? `${lastTag}..HEAD` : "HEAD";
  const changed = gitLines(repo, ["diff", "--name-only", range]);
  const uniqueChanged = [...new Set(changed)];
  if (uniqueChanged.length === 0) {
    return { would_publish: false, reason: "no changed files since last tag/HEAD" };
  }
  const triggered = uniqueChanged.filter((f) => anyGlobMatch(f, triggerGlobs));
  if (triggered.length === 0) {
    return { would_publish: false, reason: "no changed files match trigger_globs" };
  }
  const allSkipped = uniqueChanged.every((f) => anyGlobMatch(f, skipGlobs));
  if (allSkipped) {
    return { would_publish: false, reason: "all changed files match skip_globs" };
  }
  return {
    would_publish: true,
    reason: `would invoke bump_script after ${triggered.length} trigger_glob match(es)`,
    matched_files: triggered.slice(0, 20),
  };
}

function parseFrontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0] !== "---") return {};
  const end = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
  if (end === -1) return {};
  const data = {};
  for (let index = 1; index < end; index += 1) {
    const line = lines[index];
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    const key = match[1];
    const rawValue = match[2].trim();
    if (rawValue === "true") data[key] = true;
    else if (rawValue === "false") data[key] = false;
    else if ((rawValue.startsWith('"') && rawValue.endsWith('"')) || (rawValue.startsWith("'") && rawValue.endsWith("'"))) {
      data[key] = rawValue.slice(1, -1);
    } else data[key] = rawValue;
  }
  return data;
}

function readinessCheck(fm) {
  const missing = [];
  if (fm.automation_ready !== true) missing.push("automation_ready");
  if (fm.human_questions_resolved !== true) missing.push("human_questions_resolved");
  if (fm.spec_preflight_approved !== true) missing.push("spec_preflight_approved");
  if (fm.plan_preflight_approved !== true) missing.push("plan_preflight_approved");
  if (fm.preflight_state !== "ready") missing.push("preflight_state:ready");
  return { ready: missing.length === 0, missing };
}

function listWorkReadiness(vault, project) {
  const workRoot = path.join(vault, "projects", project, "work");
  const items = [];
  if (!fileExists(workRoot)) return items;
  for (const entry of fs.readdirSync(workRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith("_")) continue;
    const specPath = path.join(workRoot, entry.name, "spec.md");
    if (!fileExists(specPath)) continue;
    const fm = parseFrontmatter(readText(specPath));
    const status = fm.status || "";
    if (!["planned", "in-progress", "in_progress"].includes(status)) continue;
    const readiness = readinessCheck(fm);
    items.push({
      id: entry.name,
      status,
      title: fm.title || entry.name,
      priority: fm.priority || "",
      unattended_ready: readiness.ready,
      missing_readiness: readiness.missing,
      merge_auto_approved: fm.merge_auto_approved === true,
    });
  }
  return items;
}

function probeSkillRef(ref, repo) {
  const clean = ref.replace(/"/g, "");
  const parts = clean.split(":");
  const plugin = parts.length > 1 ? parts[0] : "";
  const name = parts.length > 1 ? parts[1] : parts[0];
  if (plugin === "dev-loop" && repo) {
    const agentPath = path.join(repo, "skills", "dev-loop", "agents", `${name}.md`);
    if (fileExists(agentPath)) return true;
  }
  const home = os.homedir();
  const candidates = [
    path.join(home, ".claude", "skills", plugin, name, "SKILL.md"),
    path.join(home, ".claude", "skills", name, "SKILL.md"),
    path.join(home, ".agents", "skills", name, "SKILL.md"),
  ];
  if (fileExists(candidates[0]) || fileExists(candidates[1]) || fileExists(candidates[2])) return true;
  const cacheRoots = [
    path.join(home, ".claude", "plugins", "cache"),
    path.join(home, ".codex", "plugins", "cache"),
  ];
  for (const root of cacheRoots) {
    if (!fileExists(root)) continue;
    const stack = [root];
    while (stack.length) {
      const dir = stack.pop();
      for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, ent.name);
        if (ent.isDirectory()) stack.push(full);
        else if (ent.name === "SKILL.md" && full.includes(name)) return true;
      }
    }
  }
  return false;
}

function probeDependencies(repo) {
  const manifestPath = path.join(repo, "skills", "dev-loop", "dependencies.yaml");
  if (!fileExists(manifestPath)) {
    return { dep_status: "unknown", missing_required: [], missing_optional: [], note: "dependencies.yaml not found" };
  }
  const text = readText(manifestPath);
  const missingRequired = [];
  const missingOptional = [];
  const reqSection = text.split(/^optional:/m)[0];
  const optSection = text.split(/^optional:/m)[1] || "";
  for (const line of reqSection.split(/\r?\n/)) {
    const m = line.match(/^\s+ref:\s*(\S+)/);
    if (m && !probeSkillRef(m[1], repo)) missingRequired.push(m[1]);
  }
  for (const line of optSection.split(/\r?\n/)) {
    const m = line.match(/^\s+ref:\s*(\S+)/);
    if (m && !probeSkillRef(m[1], repo)) missingOptional.push(m[1]);
  }
  let dep_status = "healthy";
  if (missingRequired.length > 0) dep_status = "broken";
  else if (missingOptional.length > 0) dep_status = "degraded";
  return { dep_status, missing_required: missingRequired, missing_optional: missingOptional };
}

function readLastDoctor() {
  const p = path.join(os.homedir(), ".claude", "dev-loop", "last-doctor.json");
  if (!fileExists(p)) return { present: false, data: null };
  try {
    return { present: true, data: JSON.parse(readText(p)) };
  } catch {
    return { present: true, data: null, parse_error: true };
  }
}

function readPluginVersion(repo) {
  const manifest = path.join(repo, "skills", "dev-loop", ".claude-plugin", "plugin.json");
  if (!fileExists(manifest)) return "";
  try {
    const j = JSON.parse(readText(manifest));
    return typeof j.version === "string" ? j.version : "";
  } catch {
    return "";
  }
}

function hashFileShort(filePath) {
  return createHash("sha256").update(readText(filePath)).digest("hex").slice(0, 16);
}

function resolveCachedDevLoopSkill(repo) {
  const version = readPluginVersion(repo);
  const home = os.homedir();
  const candidates = [];
  if (version) {
    candidates.push(
      path.join(home, ".claude", "plugins", "cache", "karlorz-agent-skills", "dev-loop", version, "skills", "dev-loop", "SKILL.md"),
      path.join(home, ".claude", "plugins", "cache", "karlorz-agent-skills", "dev-loop", version, "SKILL.md"),
      path.join(home, ".codex", "plugins", "cache", "karlorz-agent-skills", "dev-loop", version, "skills", "dev-loop", "SKILL.md"),
      path.join(home, ".codex", "plugins", "cache", "karlorz-agent-skills", "dev-loop", version, "SKILL.md"),
    );
  }
  const versionRoots = [
    path.join(home, ".claude", "plugins", "cache", "karlorz-agent-skills", "dev-loop"),
    path.join(home, ".codex", "plugins", "cache", "karlorz-agent-skills", "dev-loop"),
  ];
  for (const root of versionRoots) {
    if (!fileExists(root)) continue;
    for (const ent of fs.readdirSync(root, { withFileTypes: true })) {
      if (!ent.isDirectory()) continue;
      candidates.push(path.join(root, ent.name, "skills", "dev-loop", "SKILL.md"));
      candidates.push(path.join(root, ent.name, "SKILL.md"));
    }
  }
  let best = null;
  for (const p of candidates) {
    if (!fileExists(p)) continue;
    const mtime = fs.statSync(p).mtimeMs;
    if (!best || mtime > best.mtime) best = { path: p, mtime };
  }
  return best ? best.path : null;
}

function skillCacheDrift(repo) {
  const sourceCandidates = [
    path.join(repo, "skills", "dev-loop", "skills", "dev-loop", "SKILL.md"),
    path.join(repo, "skills", "dev-loop", "SKILL.md"),
  ];
  const source = sourceCandidates.find(fileExists);
  if (!source) return { state: "unknown", detail: "source SKILL.md not in repo" };
  const sourceHash = hashFileShort(source);
  const cachePath = resolveCachedDevLoopSkill(repo);
  if (!cachePath) {
    return { state: "unknown", detail: "no cached dev-loop SKILL.md found", source_hash: sourceHash };
  }
  const cacheHash = hashFileShort(cachePath);
  if (cacheHash === sourceHash) {
    return { state: "in_sync", source_hash: sourceHash, cache_hash: cacheHash, cache_path: cachePath };
  }
  return {
    state: "drifted_stale",
    detail: "source SKILL.md differs from plugin cache — run sync-plugin-cache.sh and /reload-plugins",
    source_hash: sourceHash,
    cache_hash: cacheHash,
    cache_path: cachePath,
  };
}

function runPreflightInventory(repo, vault, project) {
  const helper = path.join(repo, "skills", "dev-loop", "scripts", "preflight-inventory.js");
  if (!fileExists(helper) || !vault) {
    return { error: "preflight helper or vault unavailable", candidates: [], skipped: [] };
  }
  const args = [
    helper,
    "--project",
    project,
    "--vault",
    vault,
    "--repo",
    repo,
    "--limit",
    "10",
    "--lane",
    "work",
    "--lane",
    "captures",
  ];
  const r = spawnSync(process.execPath, args, { encoding: "utf8", timeout: 120000, maxBuffer: 10 * 1024 * 1024 });
  if (r.status !== 0) {
    return { error: r.stderr || "preflight-inventory failed", candidates: [], skipped: [] };
  }
  try {
    return JSON.parse(r.stdout);
  } catch {
    return { error: "invalid preflight JSON", candidates: [], skipped: [] };
  }
}

function pipelineSteps(flat) {
  const pipeline = flat.prd_pipeline || "full";
  const map = {
    full: ["spec", "plan", "execute", "review", "merge", "save"],
    "tdd-first": ["plan", "execute", "review", "merge"],
    "single-pass": ["execute", "review", "merge"],
    "debug-only": ["execute", "merge"],
    manual: [],
  };
  return map[pipeline] || map.full;
}

function buildReport(opts) {
  const repo = opts.repo;
  const cfg = loadDevLoopConfig(repo);
  const flat = cfg.flat;
  const slug = opts.project || flat.slug || path.basename(repo);
  const releaseBranch = flat.release_branch || "main";
  const vaultInfo = resolveVault(repo, flat, opts.vault, cfg.raw);
  const knowledgeLayer = flat.knowledge_layer || (vaultInfo.resolved ? "skillwiki" : "none");
  const backendCaps =
    knowledgeLayer === "skillwiki" && vaultInfo.resolved
      ? ["query_vault", "create_work_item", "save_retro", "lint_vault", "audit_vault"]
      : [];

  const depsInline = probeDependencies(repo);
  const lastDoctor = readLastDoctor();
  const compactCount =
    lastDoctor.data && (typeof lastDoctor.data.compact_count === "number" || lastDoctor.data.compact_count === null)
      ? lastDoctor.data.compact_count
      : null;
  const depStatus = lastDoctor.data?.dep_status || depsInline.dep_status;
  const drift = skillCacheDrift(repo);

  const blockers = [];
  if (depsInline.missing_required.length > 0) {
    blockers.push({ code: "missing_required_deps", detail: depsInline.missing_required.join(", ") });
  }
  if (depStatus === "broken") {
    blockers.push({ code: "dep_status_broken", detail: "dependency probe classified broken" });
  }
  if (drift.state === "drifted_stale") {
    blockers.push({ code: "skill_cache_drift", detail: drift.detail });
  }
  if (compactCount !== null && compactCount >= 4) {
    blockers.push({ code: "compact_pressure", detail: `auto-compact fired ${compactCount}x — fresh session recommended` });
  }
  if (opts.previewMode === "prep" && !backendCaps.includes("query_vault")) {
    blockers.push({ code: "prep_requires_vault", detail: "prep mode requires query_vault" });
  }
  if (opts.previewMode === "investigate" && !backendCaps.includes("query_vault")) {
    blockers.push({ code: "investigate_requires_vault", detail: "investigate mode requires query_vault" });
  }

  const inventory =
    vaultInfo.resolved && vaultInfo.path ? runPreflightInventory(repo, vaultInfo.path, slug) : { candidates: [], errors: ["no vault"] };

  const workReadiness = vaultInfo.resolved && vaultInfo.path ? listWorkReadiness(vaultInfo.path, slug) : [];

  const claimableAttended = (inventory.candidates || []).filter((c) => c.lane === "work" || c.lane === "captures");
  const unattendedReady = workReadiness.filter((w) => w.unattended_ready);
  const readinessSkips = workReadiness
    .filter((w) => !w.unattended_ready)
    .map((w) => ({ id: w.id, status: w.status, missing: w.missing_readiness }));

  const unclaimedCaptures = (inventory.candidates || []).filter((c) => c.lane === "captures");

  let nextAction = "core";
  let wouldPick = null;
  if (blockers.length > 0) nextAction = "blocked";
  else if (opts.previewMode === "prep") nextAction = "prep";
  else if (opts.previewMode === "investigate") nextAction = "investigate";
  else if (opts.previewMode === "status") nextAction = "status";
  else if (opts.orchestration === "goal") {
    if (unattendedReady.length > 0) {
      nextAction = "core";
      wouldPick = unattendedReady[0].id;
    } else {
      nextAction = "idle";
    }
  } else if (claimableAttended.length > 0) {
    nextAction = "core";
    wouldPick = claimableAttended[0].id;
  } else {
    nextAction = "idle";
  }

  const branch = gitLines(repo, ["rev-parse", "--abbrev-ref", "HEAD"])[0] || "unknown";
  const onRelease = branch === releaseBranch;
  const ciConfigured = flat.ci_configured === true;
  const release = releasePreview(repo, flat, cfg.raw);
  const browserVerify = browserVerifyPreview(repo, cfg.raw, depsInline.missing_optional);
  const mergePolicy = parseMergePolicyFromConfig(cfg.raw);
  const selectedWork = workReadiness.find((work) => work.id === wouldPick);
  const workItemApproved = selectedWork?.merge_auto_approved === true;
  const routeBlocked = mergePolicy.strategy === "pull-request" && onRelease;
  const wouldCreatePr = !routeBlocked && !onRelease;
  const wouldPushDirect = !routeBlocked && !wouldCreatePr;
  let mergeReason = `repo-policy on release_branch ${releaseBranch}`;
  if (routeBlocked) {
    mergeReason = `merge_policy requires a feature branch before creating a PR to ${releaseBranch}`;
  } else if (wouldCreatePr) {
    mergeReason = `feature branch → PR to ${releaseBranch}`;
  }
  const autoMergeFailedGates = [];
  if (routeBlocked) autoMergeFailedGates.push("merge_route");
  if (!wouldCreatePr) autoMergeFailedGates.push("pull_request");
  if (!mergePolicy.auto_merge) autoMergeFailedGates.push("repository_auto_merge");
  if (mergePolicy.require_work_item_approval && !workItemApproved) {
    autoMergeFailedGates.push("work_item_approval");
  }
  // Status is a pre-execution preview and does not claim a CI result. The
  // runtime MERGE gate may remove this only for an exact `healthy` result.
  autoMergeFailedGates.push("ci_health:healthy");

  let overallState = "healthy";
  if (blockers.length > 0) overallState = "blocked";
  else if (depStatus === "degraded" || depsInline.missing_optional.length > 0 || vaultInfo.warning) {
    overallState = "degraded";
  }

  const recommendations = [];
  if (drift.state === "drifted_stale") recommendations.push("Run `/reload-plugins` then re-run `/dev-loop status`.");
  if (readinessSkips.length > 0 && opts.orchestration === "goal") {
    recommendations.push(`Run \`/dev-loop prep --limit 5\` for project ${slug} to resolve unattended readiness skips.`);
  }
  if (nextAction === "idle") {
    recommendations.push("No claimable work — next core cycle would run IDLE DISCOVERY (maintenance + research-worker).");
  }
  if (depsInline.missing_optional.length > 0) {
    recommendations.push(`Optional deps missing (degraded): ${depsInline.missing_optional.slice(0, 3).join(", ")}`);
  }
  if (recommendations.length === 0) {
    recommendations.push(wouldPick ? `Run \`/dev-loop\` to pick ${wouldPick}` : "Re-run `/dev-loop status` before a write cycle");
  }

  const generatedAt = new Date().toISOString();
  const json = {
    schema_version: SCHEMA_VERSION,
    generated_at: generatedAt,
    read_only: true,
    writes_executed: false,
    project: { slug, repo, release_branch: releaseBranch },
    overall: {
      state: overallState,
      next_action: nextAction,
      reason: blockers[0]?.detail || (wouldPick ? `Would pick work item ${wouldPick}` : "No claimable work in preview"),
    },
    mode: {
      requested: "status",
      intensity: opts.intensity,
      preview_mode: opts.previewMode,
      orchestration: opts.orchestration,
      args: [],
    },
    caps: {
      backend: backendCaps,
      prd_layer: flat.prd_layer || "superpowers",
      prd_pipeline: flat.prd_pipeline || "full",
      orchestration: opts.orchestration === "goal" ? ["goal_context", "non_interactive_goal"] : [],
      dispatch_mode: "unknown",
    },
    health: {
      dep_status: depStatus,
      missing_required: depsInline.missing_required,
      missing_optional: depsInline.missing_optional,
      compact_count: compactCount,
      last_doctor_present: lastDoctor.present,
      skill_cache: drift,
      vault: vaultInfo,
    },
    work_preview: {
      claimable_attended: claimableAttended.map((c) => ({
        id: c.id,
        lane: c.lane,
        status: c.status,
        priority: c.priority,
      })),
      claimable_unattended: unattendedReady.map((w) => w.id),
      readiness_skips: readinessSkips,
      unclaimed_transcripts: unclaimedCaptures.map((c) => c.id),
      uncited_raw: [],
      inventory_errors: inventory.errors || (inventory.error ? [inventory.error] : []),
    },
    pipeline_preview: {
      would_pick: wouldPick,
      steps: pipelineSteps(flat),
      browser_verify: browserVerify,
      ci_gate: {
        would_run: ciConfigured,
        reason: ciConfigured ? `ci_configured: true` : "ci_configured false or absent",
      },
      merge: {
        strategy: mergePolicy.strategy,
        would_create_pr: wouldCreatePr,
        would_push_direct: wouldPushDirect,
        route_blocked: routeBlocked,
        current_branch: branch,
        reason: mergeReason,
        auto_merge_configured: mergePolicy.auto_merge,
        merge_method: mergePolicy.merge_method,
        require_work_item_approval: mergePolicy.require_work_item_approval,
        work_item_approved: workItemApproved,
        required_ci_state: "healthy",
        observed_ci_state: "unknown",
        auto_merge_eligible: false,
        failed_gates: autoMergeFailedGates,
      },
      release,
    },
    idle_preview: {
      would_run: nextAction === "idle",
      research_worker: nextAction === "idle",
      deep_research: opts.intensity === "high",
      reason:
        nextAction === "idle"
          ? opts.intensity === "high"
            ? "IDLE DISCOVERY with research-worker; deep-research eligible at high intensity"
            : "IDLE DISCOVERY with research-worker; deep-research off at normal intensity"
          : "not idle — core/prep/investigate path",
    },
    blockers,
    recommendations: recommendations.slice(0, 5),
    config_path: cfg.configPath,
  };

  return { json, slug };
}

function renderMarkdown(json) {
  const lines = [];
  lines.push(`# Dev Loop Status — ${json.project.slug}`);
  lines.push("");
  lines.push("## Summary");
  lines.push(`- Overall state: **${json.overall.state}**`);
  lines.push(`- Next action: **${json.overall.next_action}**`);
  lines.push(`- Reason: ${json.overall.reason}`);
  lines.push(`- Read-only: ${json.read_only} (no vault/git/PR/release writes executed)`);
  lines.push("");
  lines.push("## Mode Parse");
  lines.push("- Requested mode: status (`doctor` is an alias in skill dispatch; distinct from REFRESH doctor-worker)");
  lines.push(`- Effective intensity: ${json.mode.intensity}`);
  lines.push(`- Preview mode: ${json.mode.preview_mode}`);
  lines.push(`- Orchestration simulation: ${json.mode.orchestration}`);
  lines.push("");
  lines.push("## Config Resolution");
  lines.push(`- Config path: ${json.config_path || "(missing)"}`);
  lines.push(`- release_branch: ${json.project.release_branch}`);
  lines.push(`- BACKEND_CAPS: ${json.caps.backend.join(", ") || "(none)"}`);
  lines.push(`- prd_layer: ${json.caps.prd_layer}, pipeline: ${json.caps.prd_pipeline}`);
  lines.push("");
  lines.push("## Dependency / Environment Health");
  lines.push(`- dep_status: ${json.health.dep_status}`);
  lines.push(`- missing required: ${json.health.missing_required.join(", ") || "(none)"}`);
  lines.push(`- missing optional: ${json.health.missing_optional.join(", ") || "(none)"}`);
  lines.push(`- compact_count: ${json.health.compact_count === null ? "unknown" : json.health.compact_count}`);
  lines.push(`- skill cache: ${json.health.skill_cache.state}`);
  if (json.health.skill_cache.detail) lines.push(`  - ${json.health.skill_cache.detail}`);
  lines.push(`- vault resolved: ${json.health.vault.resolved} (${json.health.vault.path || "n/a"})`);
  if (json.health.vault.warning) lines.push(`- vault warning: ${json.health.vault.warning}`);
  lines.push("");
  lines.push("## Claimable Work Preview");
  for (const c of json.work_preview.claimable_attended.slice(0, 8)) {
    lines.push(`- ${c.id} (${c.lane})`);
  }
  if (json.work_preview.claimable_attended.length === 0) lines.push("- (none from inventory)");
  lines.push(`- Unattended ready: ${json.work_preview.claimable_unattended.join(", ") || "(none)"}`);
  if (json.work_preview.readiness_skips.length) {
    lines.push("- Readiness skips:");
    for (const s of json.work_preview.readiness_skips.slice(0, 8)) {
      lines.push(`  - ${s.id}: ${s.missing.join(", ")}`);
    }
  }
  lines.push("");
  lines.push("## What `/dev-loop` Would Do Next");
  lines.push(`- Would pick: ${json.pipeline_preview.would_pick || "none"}`);
  lines.push(`- Steps: ${json.pipeline_preview.steps.join(" → ") || "(manual)"}`);
  lines.push(
    `- Browser verification: ${json.pipeline_preview.browser_verify.would_run ? "yes" : "no"} — ${json.pipeline_preview.browser_verify.reason}`,
  );
  lines.push(`- CI gate: ${json.pipeline_preview.ci_gate.would_run} — ${json.pipeline_preview.ci_gate.reason}`);
  lines.push(
    `- PR vs direct push: ${json.pipeline_preview.merge.would_create_pr ? "would open PR" : "would push direct"} — ${json.pipeline_preview.merge.reason}`,
  );
  lines.push(
    `- Auto-merge: ${json.pipeline_preview.merge.auto_merge_eligible ? "eligible" : "not eligible"} — ${json.pipeline_preview.merge.failed_gates.join(", ") || "all gates satisfied"}`,
  );
  lines.push(`- Release/publish: ${json.pipeline_preview.release.would_publish} — ${json.pipeline_preview.release.reason}`);
  lines.push("");
  lines.push("## Idle Discovery Preview");
  lines.push(`- Would idle maintenance run: ${json.idle_preview.would_run ? "yes" : "no"}`);
  lines.push(`- Research-worker scope: ${json.idle_preview.research_worker ? "likely" : "no"}`);
  lines.push(`- Deep-research: ${json.idle_preview.deep_research ? "eligible (high)" : "off"}`);
  if (json.idle_preview.reason) lines.push(`- Note: ${json.idle_preview.reason}`);
  lines.push("");
  lines.push("## Blockers");
  if (!json.blockers.length) lines.push("- (none)");
  else for (const b of json.blockers) lines.push(`- ${b.code}: ${b.detail}`);
  lines.push("");
  lines.push("## Recommendations");
  for (const r of json.recommendations) lines.push(`- ${r}`);
  lines.push("");
  return lines.join("\n");
}

function writeArtifacts(repo, json, md, noWrite) {
  if (noWrite) return { mdPath: null, jsonPath: null };
  const stamp = json.generated_at.replace(/[:.]/g, "-").slice(0, 19);
  const dir = path.join(repo, ".claude", "dev-loop", "status");
  fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, `${stamp}-status`);
  const jsonPath = `${base}.json`;
  const mdPath = `${base}.md`;
  fs.writeFileSync(jsonPath, `${JSON.stringify(json, null, 2)}\n`);
  fs.writeFileSync(mdPath, md);
  return { mdPath, jsonPath };
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
  const { json } = buildReport(opts);
  const md = renderMarkdown(json);
  const paths = writeArtifacts(opts.repo, json, md, opts.noWrite);

  if (opts.format === "markdown") {
    process.stdout.write(md);
  } else {
    process.stdout.write(`${JSON.stringify(json, null, 2)}\n`);
  }

  if (!opts.noWrite && paths.jsonPath) {
    process.stderr.write(`status: wrote ${paths.mdPath} and ${paths.jsonPath}\n`);
  }
  return json.overall.state === "blocked" ? 1 : 0;
}

process.exitCode = main();
