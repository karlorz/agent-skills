#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

function usage() {
  return "Usage: dev-loop-why-skipped.js --project <slug> --work <folder-slug> [--vault <path>] [--repo <path>] [--json]";
}

function parseArgs(argv) {
  const opts = { errors: [], json: false, project: "", work: "", vault: "", repo: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--help") {
      opts.help = true;
      continue;
    }
    if (a === "--json") {
      opts.json = true;
      continue;
    }
    if (["--project", "--work", "--vault", "--repo"].includes(a)) {
      const v = argv[++i];
      if (!v) opts.errors.push(`${a} requires value`);
      else if (a === "--project") opts.project = v;
      else if (a === "--work") opts.work = v;
      else if (a === "--vault") opts.vault = v;
      else opts.repo = path.resolve(v);
    }
  }
  if (!opts.repo) opts.repo = process.cwd();
  return opts;
}

function readText(p) {
  return fs.readFileSync(p, "utf8");
}

function parseFrontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0] !== "---") return {};
  const end = lines.findIndex((l, i) => i > 0 && l.trim() === "---");
  if (end === -1) return {};
  const data = {};
  for (let i = 1; i < end; i += 1) {
    const m = lines[i].match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    const k = m[1];
    const v = m[2].trim();
    if (v === "true") data[k] = true;
    else if (v === "false") data[k] = false;
    else if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) data[k] = v.slice(1, -1);
    else data[k] = v;
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

function resolveVault(vaultOverride) {
  if (vaultOverride) return vaultOverride;
  const r = spawnSync("skillwiki", ["path"], { encoding: "utf8", timeout: 15000 });
  if (r.status === 0 && r.stdout.trim()) {
    try {
      const j = JSON.parse(r.stdout.trim());
      return j.data?.path || "";
    } catch {
      return r.stdout.trim();
    }
  }
  const fallback = path.join(os.homedir(), "wiki");
  return fs.existsSync(path.join(fallback, "SCHEMA.md")) ? fallback : "";
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    process.stdout.write(`${usage()}\n`);
    return 0;
  }
  if (opts.errors.length || !opts.project || !opts.work) {
    process.stderr.write(`${opts.errors.join("\n") || usage()}\n`);
    return 2;
  }
  const vault = resolveVault(opts.vault);
  if (!vault) {
    process.stderr.write("vault not resolved\n");
    return 2;
  }
  const workDir = path.join(vault, "projects", opts.project, "work", opts.work);
  const specPath = path.join(workDir, "spec.md");
  if (!fs.existsSync(specPath)) {
    process.stderr.write(`spec not found: ${specPath}\n`);
    return 2;
  }
  const fm = parseFrontmatter(readText(specPath));
  const readiness = readinessCheck(fm);
  const helper = path.join(opts.repo, "skills", "dev-loop", "scripts", "preflight-inventory.js");
  let inventory = null;
  if (fs.existsSync(helper)) {
    const r = spawnSync(
      process.execPath,
      [helper, "--project", opts.project, "--vault", vault, "--repo", opts.repo, "--work", opts.work, "--limit", "1"],
      { encoding: "utf8", maxBuffer: 5 * 1024 * 1024 },
    );
    if (r.status === 0) {
      try {
        inventory = JSON.parse(r.stdout);
      } catch {
        inventory = { parse_error: true };
      }
    }
  }
  const candidate = inventory?.candidates?.[0];
  const out = {
    schema_version: "dev-loop-why-skipped.v1",
    read_only: true,
    project: opts.project,
    work: opts.work,
    spec_path: specPath,
    status: fm.status || "",
    unattended_ready: readiness.ready,
    missing_readiness: readiness.missing,
    inventory_lane: candidate?.lane || null,
    inventory_findings: candidate?.findings || [],
    inventory_valid: candidate?.valid ?? null,
  };
  if (opts.json) process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
  else {
    const lines = [
      `# Why skipped — ${opts.work}`,
      "",
      `- Unattended ready: **${readiness.ready}**`,
      `- Work status: ${fm.status || "(missing)"}`,
      readiness.missing.length ? `- Missing gates: ${readiness.missing.join(", ")}` : "- Missing gates: (none)",
    ];
    if (candidate?.findings?.length) lines.push(`- Inventory findings: ${candidate.findings.join(", ")}`);
    lines.push("");
    process.stdout.write(lines.join("\n"));
  }
  return readiness.ready ? 0 : 1;
}

process.exitCode = main();