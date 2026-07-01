#!/usr/bin/env node
"use strict";

/**
 * Read-only dev-loop config linter. No writes except optional report dir.
 */

const fs = require("node:fs");
const path = require("node:path");

const SCHEMA_VERSION = "dev-loop-config-lint.v1";
const PRD_LAYERS = new Set(["superpowers", "codestable", "tdd", "manual", "none"]);
const PRD_PIPELINES = new Set(["full", "tdd-first", "single-pass", "debug-only", "manual"]);
const KNOWLEDGE_LAYERS = new Set(["skillwiki", "none"]);
const CI_DISCOVERY = new Set(["runtime", "explicit"]);
const PUBLISH_VIA = new Set(["ci-tag-trigger", "local", "none", ""]);
const PREFLIGHT_LANES = new Set(["work", "captures", "hygiene"]);

function usage() {
  return [
    "Usage: dev-loop-config-lint.js --repo <path> [options]",
    "",
    "Options:",
    "  --format <markdown|json|both>  default: both",
    "  --no-write                       stdout only",
    "  --help",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = { errors: [], format: "both", noWrite: false, repo: "" };
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
    if (arg === "--repo" || arg === "--format") {
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) {
        opts.errors.push(`${arg} requires a value`);
        continue;
      }
      i += 1;
      if (arg === "--repo") opts.repo = path.resolve(value);
      else opts.format = value;
    }
  }
  if (!opts.repo && !opts.help) opts.repo = process.cwd();
  return opts;
}

function readText(p) {
  return fs.readFileSync(p, "utf8");
}

function exists(p) {
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
  while ((m = re.exec(text)) !== null) blocks.push(m[1]);
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

function mergeBlocks(blocks) {
  const merged = {};
  for (const b of blocks) Object.assign(merged, parseSimpleYaml(b));
  return merged;
}

function vaultFromRaw(raw) {
  if (!raw) return "";
  const m = raw.match(/knowledge_backends:\s*\n[\s\S]*?skillwiki:\s*\n[\s\S]*?vault:\s*(\S+)/);
  if (m) return m[1].replace(/"/g, "");
  const legacy = raw.match(/^vault:\s*(\S+)/m);
  return legacy ? legacy[1].replace(/"/g, "") : "";
}

function parseListFromBlock(raw, key) {
  if (!raw) return [];
  const re = new RegExp(`${key}:\\s*\\n([\\s\\S]*?)(?=\\n[a-z_]+:|\\n## |$)`, "m");
  const m = raw.match(re);
  if (!m) return [];
  const items = [];
  for (const line of m[1].split(/\r?\n/)) {
    const item = line.match(/^\s*-\s+"?([^"]+)"?\s*$/);
    if (item) items.push(item[1]);
  }
  return items;
}

function parseReleasePolicy(raw) {
  const block = raw.match(/release_policy:\s*\n([\s\S]*?)(?=\n## |\n```)/);
  if (!block) return null;
  const text = block[1];
  return {
    auto_bump: /auto_bump:\s*true/.test(text),
    trigger_globs: parseListFromBlock(`trigger_globs:\n${text}`, "trigger_globs").length
      ? parseListFromBlock(text, "trigger_globs")
      : (() => {
          const items = [];
          let inT = false;
          for (const line of text.split(/\r?\n/)) {
            if (/trigger_globs:/.test(line)) inT = true;
            else if (/skip_globs:/.test(line)) inT = false;
            else if (inT) {
              const item = line.match(/^\s*-\s+"?([^"]+)"?\s*$/);
              if (item) items.push(item[1]);
            }
          }
          return items;
        })(),
  };
}

function parsePreflight(raw) {
  const block = raw.match(/preflight:\s*\n([\s\S]*?)(?=\n## |\n```)/);
  if (!block) return null;
  const text = block[1];
  const limit = text.match(/default_limit:\s*(\d+)/);
  const lanes = [];
  let inLanes = false;
  for (const line of text.split(/\r?\n/)) {
    if (/default_lanes:/.test(line)) inLanes = true;
    else if (inLanes && /^\s{2}[a-z_]/.test(line) && !/^\s+-/.test(line)) inLanes = false;
    if (inLanes) {
      const item = line.match(/^\s*-\s*(\w+)/);
      if (item) lanes.push(item[1]);
    }
  }
  const behavior = text.match(/unattended_not_ready_behavior:\s*(\S+)/);
  return {
    default_limit: limit ? Number(limit[1]) : null,
    default_lanes: lanes,
    unattended_not_ready_behavior: behavior ? behavior[1] : null,
  };
}

function lint(repo) {
  const configPath = path.join(repo, ".claude", "dev-loop.config.md");
  const templatePath = path.join(repo, "skills", "dev-loop", "templates", "project-config.md");
  const findings = [];
  const infos = [];

  if (!exists(configPath)) {
    findings.push({
      severity: "error",
      code: "missing_config",
      message: "Missing .claude/dev-loop.config.md — copy from skills/dev-loop/templates/project-config.md",
    });
    return { configPath, flat: {}, findings, infos, overall: "blocked" };
  }

  const raw = readText(configPath);
  const flat = mergeBlocks(extractYamlBlocks(raw));
  const vault = flat.vault || vaultFromRaw(raw);

  if (!flat.slug) {
    findings.push({ severity: "error", code: "missing_slug", message: "slug is required in Identity block" });
  }
  if (!flat.release_branch) {
    findings.push({ severity: "error", code: "missing_release_branch", message: "release_branch is required" });
  }
  if (flat.prd_layer && !PRD_LAYERS.has(flat.prd_layer)) {
    findings.push({
      severity: "error",
      code: "invalid_prd_layer",
      message: `prd_layer must be one of: ${[...PRD_LAYERS].join(", ")}`,
    });
  }
  if (flat.prd_pipeline && !PRD_PIPELINES.has(flat.prd_pipeline)) {
    findings.push({
      severity: "error",
      code: "invalid_prd_pipeline",
      message: `prd_pipeline must be one of: ${[...PRD_PIPELINES].join(", ")}`,
    });
  }
  if (flat.knowledge_layer && !KNOWLEDGE_LAYERS.has(flat.knowledge_layer)) {
    findings.push({
      severity: "error",
      code: "invalid_knowledge_layer",
      message: `knowledge_layer must be skillwiki or none`,
    });
  }
  if (flat.knowledge_layer === "skillwiki" && !vault) {
    findings.push({
      severity: "error",
      code: "missing_vault",
      message: "knowledge_layer skillwiki requires knowledge_backends.skillwiki.vault or legacy vault",
    });
  }
  if (flat.knowledge_layer === "skillwiki" && vault && vault !== "auto" && !exists(vault)) {
    findings.push({
      severity: "warn",
      code: "vault_path_missing",
      message: `Configured vault path does not exist on disk: ${vault}`,
    });
  }
  if (flat.ci_discovery && !CI_DISCOVERY.has(flat.ci_discovery)) {
    findings.push({
      severity: "error",
      code: "invalid_ci_discovery",
      message: "ci_discovery must be runtime or explicit",
    });
  }
  if (flat.ci_configured === true && flat.ci_discovery === "explicit") {
    const checks = parseListFromBlock(raw, "required_checks");
    if (checks.length === 0) {
      findings.push({
        severity: "warn",
        code: "empty_required_checks",
        message: "ci_discovery explicit with ci_configured true but required_checks is empty",
      });
    }
  }
  const preflight = parsePreflight(raw);
  if (preflight) {
    if (preflight.default_limit !== null && (!Number.isInteger(preflight.default_limit) || preflight.default_limit < 1)) {
      findings.push({
        severity: "error",
        code: "invalid_preflight_limit",
        message: "preflight.default_limit must be a positive integer",
      });
    }
    for (const lane of preflight.default_lanes) {
      if (!PREFLIGHT_LANES.has(lane)) {
        findings.push({
          severity: "error",
          code: "invalid_preflight_lane",
          message: `Unknown preflight lane: ${lane}`,
        });
      }
    }
    if (preflight.unattended_not_ready_behavior && preflight.unattended_not_ready_behavior !== "skip") {
      findings.push({
        severity: "warn",
        code: "unattended_behavior",
        message: `unattended_not_ready_behavior=${preflight.unattended_not_ready_behavior} — only skip is documented for /goal`,
      });
    }
  }
  const release = parseReleasePolicy(raw);
  if (release && release.auto_bump && release.trigger_globs.length === 0) {
    findings.push({
      severity: "error",
      code: "auto_bump_no_triggers",
      message: "release_policy.auto_bump true requires non-empty trigger_globs",
    });
  }
  if (release && release.auto_bump && flat.bump_script) {
    const bumpPath = path.join(repo, flat.bump_script.replace(/^\.\//, ""));
    if (!exists(bumpPath)) {
      findings.push({
        severity: "error",
        code: "missing_bump_script",
        message: `bump_script not found: ${flat.bump_script}`,
      });
    }
  }
  if (flat.publish_via && !PUBLISH_VIA.has(flat.publish_via)) {
    findings.push({
      severity: "warn",
      code: "unknown_publish_via",
      message: `publish_via=${flat.publish_via} — expected ci-tag-trigger, local, or none`,
    });
  }
  if (flat.publish_via && flat.publish_via !== "none" && !release) {
    infos.push({
      code: "publish_without_release_policy",
      message: "publish_via set but release_policy block absent — auto-bump at PUSH will not run",
    });
  }
  const e2e = parseListFromBlock(raw, "e2e_scripts");
  for (const script of e2e) {
    const cmd = script.replace(/^bash\s+/, "").trim();
    const scriptPath = path.join(repo, cmd);
    if (!exists(scriptPath)) {
      findings.push({
        severity: "warn",
        code: "missing_e2e_script",
        message: `e2e_scripts entry not found: ${script}`,
      });
    }
  }
  if (!exists(templatePath)) {
    infos.push({ code: "template_missing", message: "project-config template not found in repo (skipped structural compare)" });
  } else if (vaultFromRaw(raw) && !raw.includes("knowledge_backends:") && raw.includes("vault:")) {
    infos.push({
      code: "legacy_vault_alias",
      message: "Using top-level vault alias — prefer knowledge_backends.skillwiki.vault: auto for portability",
    });
  }

  const errors = findings.filter((f) => f.severity === "error").length;
  const warns = findings.filter((f) => f.severity === "warn").length;
  let overall = "healthy";
  if (errors > 0) overall = "blocked";
  else if (warns > 0) overall = "degraded";

  return { configPath, templatePath, flat, vault, findings, infos, overall };
}

function buildJson(repo, result) {
  return {
    schema_version: SCHEMA_VERSION,
    generated_at: new Date().toISOString(),
    read_only: true,
    project: { slug: result.flat.slug || path.basename(repo), repo },
    overall: {
      state: result.overall,
      errors: result.findings.filter((f) => f.severity === "error").length,
      warnings: result.findings.filter((f) => f.severity === "warn").length,
    },
    config_path: result.configPath,
    findings: result.findings,
    infos: result.infos,
    recommendations: result.findings
      .filter((f) => f.severity === "error")
      .slice(0, 5)
      .map((f) => f.message),
  };
}

function renderMd(json) {
  const lines = [
    `# Dev Loop Config Lint — ${json.project.slug}`,
    "",
    `## Summary`,
    `- State: **${json.overall.state}**`,
    `- Errors: ${json.overall.errors}, Warnings: ${json.overall.warnings}`,
    `- Config: ${json.config_path}`,
    "",
    "## Findings",
  ];
  if (!json.findings.length) lines.push("- (none)");
  else for (const f of json.findings) lines.push(`- [${f.severity}] ${f.code}: ${f.message}`);
  if (json.infos.length) {
    lines.push("", "## Info");
    for (const i of json.infos) lines.push(`- ${i.code}: ${i.message}`);
  }
  lines.push("");
  return lines.join("\n");
}

function writeArtifacts(repo, json, md, noWrite) {
  if (noWrite) return {};
  const stamp = json.generated_at.replace(/[:.]/g, "-").slice(0, 19);
  const dir = path.join(repo, ".claude", "dev-loop", "lint");
  fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, `${stamp}-config-lint`);
  fs.writeFileSync(`${base}.json`, `${JSON.stringify(json, null, 2)}\n`);
  fs.writeFileSync(`${base}.md`, md);
  return { jsonPath: `${base}.json`, mdPath: `${base}.md` };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    process.stdout.write(`${usage()}\n`);
    return 0;
  }
  if (opts.errors.length) {
    process.stderr.write(`${opts.errors.join("\n")}\n`);
    return 2;
  }
  const result = lint(opts.repo);
  const json = buildJson(opts.repo, result);
  const md = renderMd(json);
  const paths = writeArtifacts(opts.repo, json, md, opts.noWrite);
  if (opts.format === "markdown") process.stdout.write(md);
  else process.stdout.write(`${JSON.stringify(json, null, 2)}\n`);
  if (!opts.noWrite && paths.jsonPath) {
    process.stderr.write(`config-lint: wrote ${paths.mdPath} and ${paths.jsonPath}\n`);
  }
  return json.overall.state === "blocked" ? 1 : 0;
}

process.exitCode = main();