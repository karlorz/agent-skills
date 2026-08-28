#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const CLASSIFICATIONS = [
  "delivered-close-candidate",
  "active-code-work",
  "verification-only",
  "human-gated",
  "stale-or-superseded",
  "unverifiable",
];

function usage() {
  return [
    "Usage: ranked-audit.js --vault <path> [options]",
    "",
    "Options:",
    "  --top <n>                 Maximum ranked candidates (default: 20)",
    "  --project-repos <path>    Project repository metadata YAML",
    "  --host-id <id>            Host identity for repository resolution",
    "  --repo-user <user>        Runtime user for repository resolution",
    "  --now <YYYY-MM-DD>        Deterministic comparison date",
    "  --stale-days <n>          Stale threshold (default: 30)",
    "  --help                    Show this help",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    errors: [],
    hostId: "",
    now: new Date().toISOString().slice(0, 10),
    projectRepos: "",
    repoUser: "",
    staleDays: 30,
    top: 20,
    vault: "",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help") {
      options.help = true;
      continue;
    }
    if (!["--vault", "--top", "--project-repos", "--host-id", "--repo-user", "--now", "--stale-days"].includes(argument)) {
      options.errors.push(`unknown argument: ${argument}`);
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      options.errors.push(`${argument} requires a value`);
      continue;
    }
    index += 1;
    if (argument === "--top" || argument === "--stale-days") {
      const parsed = Number.parseInt(value, 10);
      if (!Number.isInteger(parsed) || parsed < 1) {
        options.errors.push(`${argument} must be a positive integer`);
      } else if (argument === "--top") {
        options.top = parsed;
      } else {
        options.staleDays = parsed;
      }
      continue;
    }
    if (argument === "--project-repos") options.projectRepos = value;
    if (argument === "--host-id") options.hostId = value;
    if (argument === "--repo-user") options.repoUser = value;
    if (argument === "--now") options.now = value;
    if (argument === "--vault") options.vault = value;
  }

  if (options.help) return options;
  if (!options.vault) options.errors.push("--vault is required");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(options.now)) options.errors.push("--now must use YYYY-MM-DD");
  return options;
}

function runInventory(helper, argumentsList) {
  const result = spawnSync(process.execPath, [helper, ...argumentsList], {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || result.stdout.trim() || `preflight inventory exited ${result.status}`);
  }
  return JSON.parse(result.stdout);
}

function workItemState(candidate) {
  const verification = candidate.post_release_verification;
  return {
    automationReady: candidate.automation_ready,
    preflightState: candidate.preflight_state,
    verificationPosture: verification && typeof verification === "object" ? verification.posture : undefined,
    updated: candidate.updated,
  };
}

function ageInDays(now, updated) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(updated || "")) return null;
  const difference = Date.parse(`${now}T00:00:00Z`) - Date.parse(`${updated}T00:00:00Z`);
  return Math.floor(difference / 86_400_000);
}

function evidenceState(specPath) {
  const workDirectory = path.dirname(specPath);
  const evidenceFiles = ["evidence.md", "retro.md"].filter((file) => fs.existsSync(path.join(workDirectory, file)));
  const evidenceText = evidenceFiles.map((file) => fs.readFileSync(path.join(workDirectory, file), "utf8")).join("\n");
  const completedEvidence = /^status:\s*(?:completed|done)\s*$/im.test(evidenceText) || /\bskillwiki work-complete\b/i.test(evidenceText);
  return { completedEvidence, evidenceFiles, evidenceText };
}

function classify(candidate, workItem, repository, evidence, options) {
  const reasons = [];
  const gitMatches = candidate.git_matches || [];
  const ageDays = ageInDays(options.now, workItem.updated);
  const releaseEvidence = /\b(released to production|production (?:deployment|release|smoke)|immutable tag|release tag|tag v?\d)/i.test(evidence.evidenceText);

  if (workItem.verificationPosture === "opt-in") {
    reasons.push("post-release verification posture is opt-in");
    return { classification: "verification-only", reasons };
  }
  if (workItem.automationReady === false || workItem.preflightState === "needs_human") {
    reasons.push("work item records an attended human gate");
    return { classification: "human-gated", reasons };
  }
  if (evidence.evidenceFiles.length > 0 && (gitMatches.length > 0 || releaseEvidence || evidence.completedEvidence)) {
    reasons.push("completion evidence exists with repository, release, or completed evidence proof");
    return { classification: "delivered-close-candidate", reasons };
  }
  if (repository.status !== "resolved") {
    reasons.push(`repository evidence unavailable: ${repository.status}`);
    return { classification: "unverifiable", reasons };
  }
  if (ageDays !== null && ageDays >= options.staleDays && gitMatches.length === 0) {
    reasons.push(`no matching repository evidence and updated ${ageDays} days ago`);
    return { classification: "stale-or-superseded", reasons };
  }
  reasons.push("active lifecycle state with no delivery or human-gate proof");
  return { classification: "active-code-work", reasons };
}

function projectInventoryArgs(options, project) {
  const argumentsList = ["--project", project, "--vault", options.vault, "--all", "--lane", "work"];
  if (options.projectRepos) argumentsList.push("--project-repos", options.projectRepos);
  if (options.hostId) argumentsList.push("--host-id", options.hostId);
  if (options.repoUser) argumentsList.push("--repo-user", options.repoUser);
  return argumentsList;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (options.errors.length > 0) {
    process.stderr.write(`${options.errors.join("\n")}\n\n${usage()}\n`);
    process.exitCode = 2;
    return;
  }

  const helper = path.join(__dirname, "preflight-inventory.js");
  const globalInventory = runInventory(helper, ["--all-projects", "--vault", options.vault, "--all", "--lane", "work"]);
  const selected = globalInventory.candidates.slice(0, options.top);
  const projectCache = new Map();
  const candidates = [];

  for (const baseCandidate of selected) {
    const project = baseCandidate.project_slug;
    if (!projectCache.has(project)) {
      projectCache.set(project, runInventory(helper, projectInventoryArgs(options, project)));
    }
    const projectInventory = projectCache.get(project);
    const enriched = projectInventory.candidates.find((candidate) => candidate.id === baseCandidate.id) || baseCandidate;
    const specPath = path.resolve(options.vault, enriched.path);
    const workItem = workItemState(enriched);
    const evidence = evidenceState(specPath);
    const repository = projectInventory.repo_resolution || { status: "unverifiable" };
    const verdict = classify(enriched, workItem, repository, evidence, options);
    candidates.push({
      id: enriched.id,
      project_slug: project,
      path: enriched.path,
      title: enriched.title,
      status: enriched.status,
      priority: enriched.priority,
      updated: workItem.updated || null,
      classification: verdict.classification,
      reasons: verdict.reasons,
      evidence_files: evidence.evidenceFiles,
      git_matches: enriched.git_matches || [],
      repo_resolution: repository.status,
    });
  }

  const counts = Object.fromEntries(CLASSIFICATIONS.map((classification) => [classification, 0]));
  for (const candidate of candidates) counts[candidate.classification] += 1;

  process.stdout.write(`${JSON.stringify({
    ok: true,
    generated_at: options.now,
    read_only: true,
    writes_executed: false,
    requested_top: options.top,
    selected: candidates.length,
    counts,
    candidates,
  }, null, 2)}\n`);
}

main();
