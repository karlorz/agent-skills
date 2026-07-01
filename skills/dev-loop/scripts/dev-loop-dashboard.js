#!/usr/bin/env node
"use strict";

/**
 * Read-only operator dashboard: aggregates newest dev-loop session artifacts
 * (status, config-lint, migrate) plus ~/.claude/dev-loop/last-doctor.json.
 */

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const SCHEMA_VERSION = "dev-loop-dashboard.v1";

function usage() {
  return [
    "Usage: dev-loop-dashboard.js --repo <path> [options]",
    "",
    "Options:",
    "  --format markdown|json|both   default: both",
    "  --no-write                    stdout only",
    "  --refresh                     Run status/lint/migrate probes (--no-write) if artifacts missing",
    "  --project <slug>              For --refresh status probe",
    "  --help",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = {
    errors: [],
    format: "both",
    noWrite: false,
    refresh: false,
    project: "",
    repo: "",
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
    if (arg === "--refresh") {
      opts.refresh = true;
      continue;
    }
    if (arg === "--repo" || arg === "--format" || arg === "--project") {
      const v = argv[i + 1];
      if (!v || v.startsWith("--")) {
        opts.errors.push(`${arg} requires a value`);
        continue;
      }
      i += 1;
      if (arg === "--repo") opts.repo = path.resolve(v);
      else if (arg === "--format") opts.format = v;
      else opts.project = v;
    }
  }
  if (!opts.repo && !opts.help) opts.repo = process.cwd();
  return opts;
}

function newestJsonInDir(dir, suffix) {
  if (!fs.existsSync(dir)) return null;
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(suffix))
    .map((f) => ({ f, t: fs.statSync(path.join(dir, f)).mtimeMs }))
    .sort((a, b) => b.t - a.t);
  if (!files.length) return null;
  return path.join(dir, files[0].f);
}

function readJsonFile(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return { present: false, path: filePath, data: null };
  try {
    const data = JSON.parse(fs.readFileSync(filePath, "utf8"));
    return { present: true, path: filePath, data };
  } catch (e) {
    return { present: false, path: filePath, error: e.message, data: null };
  }
}

function readDoctorHud() {
  const p = path.join(os.homedir(), ".claude", "dev-loop", "last-doctor.json");
  return readJsonFile(p);
}

function runRefresh(repo, project) {
  const scripts = path.join(__dirname);
  const common = { encoding: "utf8", maxBuffer: 12 * 1024 * 1024 };
  const probes = [
    ["dev-loop-status.js", ["--repo", repo, "--format", "json", "--no-write", ...(project ? ["--project", project] : [])]],
    ["dev-loop-config-lint.js", ["--repo", repo, "--format", "json", "--no-write"]],
    ["dev-loop-config-migrate.js", ["--repo", repo, "--format", "json", "--no-write"]],
  ];
  const errors = [];
  for (const [name, args] of probes) {
    const r = spawnSync(process.execPath, [path.join(scripts, name), ...args], common);
    if (r.status !== 0 && r.status !== 1) errors.push(`${name}: ${r.stderr || "failed"}`);
  }
  return errors;
}

function worstState(states) {
  if (states.includes("blocked")) return "blocked";
  if (states.includes("degraded")) return "degraded";
  if (states.every((s) => s === "healthy" || s === "unknown")) return states.some((s) => s === "healthy") ? "healthy" : "unknown";
  return "unknown";
}

function buildDashboard(repo, opts) {
  const base = path.join(repo, ".claude", "dev-loop");

  if (opts.refresh) {
    const need =
      !newestJsonInDir(path.join(base, "status"), "-status.json") ||
      !newestJsonInDir(path.join(base, "lint"), "-config-lint.json") ||
      !newestJsonInDir(path.join(base, "migrate"), "-migrate.json");
    if (need) runRefresh(repo, opts.project);
  }

  const status = readJsonFile(newestJsonInDir(path.join(base, "status"), "-status.json"));
  const lint = readJsonFile(newestJsonInDir(path.join(base, "lint"), "-config-lint.json"));
  const migrate = readJsonFile(newestJsonInDir(path.join(base, "migrate"), "-migrate.json"));
  const doctor = readDoctorHud();

  const slices = [];
  if (status.present && status.data) {
    slices.push({
      id: "status",
      state: status.data.overall?.state || "unknown",
      summary: `${status.data.overall?.next_action || "?"} — ${status.data.overall?.reason || ""}`.slice(0, 120),
      generated_at: status.data.generated_at,
      path: status.path,
    });
  } else slices.push({ id: "status", state: "unknown", summary: "no status artifact — run /dev-loop status", path: null });

  if (lint.present && lint.data) {
    slices.push({
      id: "config_lint",
      state: lint.data.overall?.state || "unknown",
      summary: `errors ${lint.data.overall?.errors ?? "?"} warnings ${lint.data.overall?.warnings ?? "?"}`,
      generated_at: lint.data.generated_at,
      path: lint.path,
    });
  } else slices.push({ id: "config_lint", state: "unknown", summary: "no lint artifact — run /dev-loop config-lint", path: null });

  if (migrate.present && migrate.data) {
    slices.push({
      id: "config_migrate",
      state: migrate.data.overall?.state || "unknown",
      summary: migrate.data.migration?.state || migrate.data.overall?.reason,
      generated_at: migrate.data.generated_at,
      path: migrate.path,
    });
  } else {
    slices.push({ id: "config_migrate", state: "unknown", summary: "no migrate artifact — run config-migrate.js", path: null });
  }

  if (doctor.present && doctor.data) {
    slices.push({
      id: "doctor_hud",
      state: doctor.data.dep_status === "broken" ? "blocked" : doctor.data.dep_status === "degraded" ? "degraded" : "healthy",
      summary: `dep ${doctor.data.dep_status || "?"} compact ${doctor.data.compact_count ?? "?"}`,
      generated_at: doctor.data.cycle_ts || null,
      path: doctor.path,
    });
  } else {
    slices.push({ id: "doctor_hud", state: "unknown", summary: "no last-doctor.json — run a dev-loop REFRESH cycle", path: null });
  }

  const overall = worstState(slices.map((s) => s.state));

  return {
    schema_version: SCHEMA_VERSION,
    generated_at: new Date().toISOString(),
    read_only: true,
    writes_executed: false,
    project: { repo, slug: status.data?.project?.slug || lint.data?.project?.slug || path.basename(repo) },
    overall: { state: overall, slices: slices.length },
    slices,
    vault_retros: { note: "Vault retros/CI not aggregated in v1 — use status pipeline_preview and external CI tools" },
  };
}

function renderMd(json) {
  const lines = [
    `# Dev Loop Operator Dashboard — ${json.project.slug}`,
    "",
    `- Overall: **${json.overall.state}**`,
    `- Read-only aggregate (no vault/git writes)`,
    "",
    "| Source | State | Summary |",
    "|--------|-------|---------|",
  ];
  for (const s of json.slices) {
    lines.push(`| ${s.id} | ${s.state} | ${String(s.summary).replace(/\|/g, "/")} |`);
  }
  lines.push("", "## Commands", "- `/dev-loop status`", "- `/dev-loop config-lint`", "- `dev-loop-config-migrate.js --repo .`", "- `dev-loop-status-hud.js --repo .`", "");
  return lines.join("\n");
}

function writeArtifacts(repo, json, md, noWrite) {
  if (noWrite) return {};
  const stamp = json.generated_at.replace(/[:.]/g, "-").slice(0, 19);
  const dir = path.join(repo, ".claude", "dev-loop", "dashboard");
  fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, `${stamp}-dashboard`);
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
  const json = buildDashboard(opts.repo, opts);
  const md = renderMd(json);
  const paths = writeArtifacts(opts.repo, json, md, opts.noWrite);
  if (opts.format === "markdown") process.stdout.write(md);
  else if (opts.format === "both") {
    process.stdout.write(md);
    process.stdout.write(`\n---\n${JSON.stringify(json, null, 2)}\n`);
  } else process.stdout.write(`${JSON.stringify(json, null, 2)}\n`);
  if (!opts.noWrite && paths.jsonPath) process.stderr.write(`dashboard: wrote ${paths.mdPath}\n`);
  return json.overall.state === "blocked" ? 1 : 0;
}

process.exitCode = main();