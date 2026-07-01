#!/usr/bin/env node
"use strict";

/**
 * Read-only HUD helper for terminal statuslines (ccstatusline, tmux, polls).
 * Reads the newest dev-loop-status.v1 JSON under .claude/dev-loop/status/
 * or an explicit --file path. Does not run status probes unless --probe is set.
 */

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

function usage() {
  return [
    "Usage: dev-loop-status-hud.js --repo <path> [options]",
    "",
    "Options:",
    "  --file <path>     Use this status JSON instead of newest under repo",
    "  --format oneline|json   Output (default: oneline)",
    "  --probe           If no artifact, run dev-loop-status.js --no-write --format json",
    "  --project <slug>  Passed to --probe",
    "  --help",
    "",
    "Oneline example: dev-loop: degraded · idle · agent-skills",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = { format: "oneline", probe: false, project: "", repo: "", file: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help") {
      opts.help = true;
      continue;
    }
    if (arg === "--probe") {
      opts.probe = true;
      continue;
    }
    if (arg === "--repo" || arg === "--file" || arg === "--format" || arg === "--project") {
      const v = argv[i + 1];
      if (!v || v.startsWith("--")) throw new Error(`${arg} requires a value`);
      i += 1;
      if (arg === "--repo") opts.repo = path.resolve(v);
      else if (arg === "--file") opts.file = path.resolve(v);
      else if (arg === "--format") opts.format = v;
      else if (arg === "--project") opts.project = v;
    }
  }
  if (!opts.repo && !opts.file) throw new Error("--repo or --file is required");
  return opts;
}

function newestStatusJson(repo) {
  const dir = path.join(repo, ".claude", "dev-loop", "status");
  if (!fs.existsSync(dir)) return null;
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith("-status.json"))
    .map((f) => ({ f, m: fs.statSync(path.join(dir, f)).mtimeMs }))
    .sort((a, b) => b.m - a.m);
  if (!files.length) return null;
  return path.join(dir, files[0].f);
}

function readStatus(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  const j = JSON.parse(raw);
  if (j.schema_version !== "dev-loop-status.v1") {
    throw new Error(`unsupported schema: ${j.schema_version}`);
  }
  return { json: j, filePath };
}

function runProbe(repo, project) {
  const script = path.join(__dirname, "dev-loop-status.js");
  const args = ["--repo", repo, "--format", "json", "--no-write"];
  if (project) args.push("--project", project);
  const r = spawnSync(process.execPath, [script, ...args], {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (r.status !== 0 && r.status !== 1) {
    throw new Error(r.stderr || "status probe failed");
  }
  const j = JSON.parse(r.stdout);
  return { json: j, filePath: null };
}

function oneline(j) {
  const state = j.overall?.state || "unknown";
  const next = j.overall?.next_action || "unknown";
  const slug = j.project?.slug || "?";
  return `dev-loop: ${state} · ${next} · ${slug}`;
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    process.stderr.write(`${e.message}\n${usage()}\n`);
    return 2;
  }
  if (opts.help) {
    process.stdout.write(`${usage()}\n`);
    return 0;
  }

  let payload;
  try {
    if (opts.file) {
      payload = readStatus(opts.file);
    } else {
      const newest = newestStatusJson(opts.repo);
      if (newest) payload = readStatus(newest);
      else if (opts.probe) payload = runProbe(opts.repo, opts.project);
      else {
        process.stdout.write("dev-loop: (no status artifact — run /dev-loop status)\n");
        return 0;
      }
    }
  } catch (e) {
    process.stderr.write(`dev-loop-status-hud: ${e.message}\n`);
    return 2;
  }

  const { json, filePath } = payload;
  if (opts.format === "json") {
    process.stdout.write(
      `${JSON.stringify({
        schema_version: "dev-loop-status-hud.v1",
        read_only: true,
        source: filePath,
        state: json.overall?.state,
        next_action: json.overall?.next_action,
        slug: json.project?.slug,
        generated_at: json.generated_at,
      })}\n`,
    );
  } else {
    process.stdout.write(`${oneline(json)}\n`);
  }
  return json.overall?.state === "blocked" ? 1 : 0;
}

process.exitCode = main();