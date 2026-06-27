#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ACTIVE_STATUSES = new Set(["planned", "in-progress", "in_progress"]);
const DONE_STATUSES = new Set(["completed", "complete", "abandoned"]);
const CAPTURE_KINDS = new Set(["task", "bug"]);
const SKIPPED_CAPTURE_KINDS = new Set(["idea", "note"]);
const IMPLEMENTED_WITHOUT_CLOSURE_FINDING = "possibly_implemented_without_closure";
const REPO_INDEX_IGNORED_DIRS = new Set([
  ".git",
  "coverage",
  "dist",
  "node_modules",
  "tmp",
  "vendor",
]);
const REPO_INDEX_MAX_FILE_BYTES = 512 * 1024;
const GENERIC_IMPLEMENTATION_TERMS = new Set([
  "agent",
  "bug",
  "capture",
  "captures",
  "change",
  "code",
  "cli/app",
  "docs",
  "dev-loop",
  "feature",
  "file",
  "fix",
  "issue",
  "local",
  "project",
  "repo",
  "review",
  "skill",
  "task",
  "test",
  "tests",
  "update",
  "work",
  "agent-skills",
]);
const repoIndexCache = new Map();

function usage() {
  return [
    "Usage: preflight-inventory.js --project <slug> --vault <path> --repo <path> [options]",
    "",
    "Options:",
    "  --limit <n>              Candidate limit when --all is not set (default: 5)",
    "  --all                    Return all matching candidates",
    "  --all-projects           Scan every projects/<slug>/work directory; --project becomes optional",
    "  --lane <lane>            Restrict to work, captures, or hygiene; repeatable or comma-separated",
    "  --work <slug>            Restrict to one work folder/slug",
    "  --help                   Show this help",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = {
    all: false,
    allProjects: false,
    errors: [],
    lanes: new Set(["work", "captures", "hygiene"]),
    limit: 5,
    project: "",
    repo: "",
    vault: "",
    work: "",
  };

  let lanesWereSet = false;

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help") {
      opts.help = true;
      continue;
    }
    if (arg === "--all") {
      opts.all = true;
      continue;
    }
    if (arg === "--all-projects") {
      opts.allProjects = true;
      continue;
    }
    if (arg === "--project" || arg === "--vault" || arg === "--repo" || arg === "--limit" || arg === "--work") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        opts.errors.push(`${arg} requires a value`);
        continue;
      }
      index += 1;
      if (arg === "--limit") {
        const parsed = Number.parseInt(value, 10);
        if (!Number.isInteger(parsed) || parsed < 1) {
          opts.errors.push("--limit must be a positive integer");
        } else {
          opts.limit = parsed;
        }
      } else {
        opts[arg.slice(2)] = value;
      }
      continue;
    }
    if (arg === "--lane") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        opts.errors.push("--lane requires a value");
        continue;
      }
      index += 1;
      if (!lanesWereSet) {
        opts.lanes = new Set();
        lanesWereSet = true;
      }
      for (const lane of value.split(",")) {
        const trimmed = lane.trim();
        if (!["work", "captures", "hygiene"].includes(trimmed)) {
          opts.errors.push(`unsupported lane: ${trimmed}`);
        } else {
          opts.lanes.add(trimmed);
        }
      }
      continue;
    }
    opts.errors.push(`unknown argument: ${arg}`);
  }

  for (const required of ["vault", "repo"]) {
    if (!opts[required]) {
      opts.errors.push(`--${required} is required`);
    }
  }
  if (!opts.allProjects && !opts.project) {
    opts.errors.push("--project is required");
  }

  opts.vault = opts.vault ? path.resolve(opts.vault) : "";
  opts.repo = opts.repo ? path.resolve(opts.repo) : "";

  return opts;
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function listDirSafe(dirPath) {
  try {
    return fs.readdirSync(dirPath, { withFileTypes: true });
  } catch {
    return [];
  }
}

function cleanScalar(value) {
  const trimmed = String(value ?? "").trim();
  if (!trimmed) return "";
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseFrontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0] !== "---") return { data: {}, bodyStart: 0 };

  const end = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
  if (end === -1) return { data: {}, bodyStart: 0 };

  const data = {};
  for (let index = 1; index < end; index += 1) {
    const line = lines[index];
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;

    const key = match[1];
    const rawValue = match[2];
    if (rawValue.trim() === "") {
      const values = [];
      let cursor = index + 1;
      while (cursor < end) {
        const item = lines[cursor].match(/^\s*-\s*(.*)$/);
        if (!item) break;
        values.push(cleanScalar(item[1]));
        cursor += 1;
      }
      if (values.length > 0) {
        data[key] = values;
        index = cursor - 1;
      } else {
        data[key] = "";
      }
    } else {
      data[key] = cleanScalar(rawValue);
    }
  }

  return { data, bodyStart: end + 1 };
}

function bodyText(text, parsed) {
  return text.split(/\r?\n/).slice(parsed.bodyStart).join("\n");
}

function sha256(filePath) {
  return createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function relPath(vault, filePath) {
  return path.relative(vault, filePath).split(path.sep).join("/");
}

function listProjectSlugs(vault) {
  const projectsRoot = path.join(vault, "projects");
  return listDirSafe(projectsRoot)
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith(".") && !entry.name.startsWith("_"))
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
}

function dedupeSkipped(skipped) {
  const seen = new Set();
  const deduped = [];
  for (const item of skipped) {
    const key = [
      item.path ?? "",
      item.reason ?? "",
      item.project ?? "",
      item.kind ?? "",
      item.id ?? "",
      item.status ?? "",
    ].join("\0");
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(item);
  }
  return deduped;
}

function runSkillwikiValidate(filePath) {
  const result = spawnSync("skillwiki", ["validate", filePath], { encoding: "utf8" });
  const stdout = result.stdout ? result.stdout.trim() : "";
  const stderr = result.stderr ? result.stderr.trim() : "";

  if (result.error) {
    return {
      available: false,
      code: null,
      errors: [result.error.message],
      raw: result.error.message,
      schema: null,
      valid: false,
    };
  }

  let parsed = null;
  if (stdout.startsWith("{")) {
    try {
      parsed = JSON.parse(stdout);
    } catch {
      parsed = null;
    }
  }

  return {
    available: true,
    code: result.status,
    errors: parsed?.data?.errors ?? [],
    raw: stdout || stderr,
    schema: parsed?.data?.schema ?? null,
    valid: parsed?.data?.valid === true,
  };
}

function gitMatches(repo, terms) {
  const matches = [];
  const seen = new Set();

  for (const term of terms.filter(Boolean)) {
    if (seen.has(term)) continue;
    seen.add(term);

    const result = spawnSync("git", ["-C", repo, "log", "--oneline", "-30", "--grep", term], {
      encoding: "utf8",
    });
    if (result.status !== 0 || !result.stdout.trim()) continue;

    for (const line of result.stdout.trim().split(/\r?\n/)) {
      matches.push(line);
    }
  }

  return [...new Set(matches)];
}

function normalizeImplementationTerm(value) {
  return String(value ?? "")
    .trim()
    .replace(/^[`"'\s]+/, "")
    .replace(/[`"',;:!?().\]\[\s]+$/, "")
    .replace(/\s+/g, " ");
}

function isUsefulImplementationTerm(term) {
  const normalized = normalizeImplementationTerm(term);
  const lower = normalized.toLowerCase();
  if (normalized.length < 4 || normalized.length > 80) return false;
  if (/^[0-9._:/-]+$/.test(normalized)) return false;
  if (GENERIC_IMPLEMENTATION_TERMS.has(lower)) return false;
  return /[:/._-]/.test(normalized);
}

function extractImplementationTerms(body) {
  const terms = [];
  const seen = new Set();
  const addTerm = (value) => {
    const normalized = normalizeImplementationTerm(value);
    const key = normalized.toLowerCase();
    if (!isUsefulImplementationTerm(normalized) || seen.has(key)) return;
    seen.add(key);
    terms.push(normalized);
  };

  for (const match of body.matchAll(/`([^`]+)`/g)) {
    addTerm(match[1]);
  }

  for (const match of body.matchAll(/[A-Za-z0-9][A-Za-z0-9:_./-]{3,}/g)) {
    addTerm(match[0]);
  }

  return terms.slice(0, 20);
}

function listRepoFiles(repo, dir = repo) {
  const files = [];
  for (const entry of listDirSafe(dir)) {
    const filePath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!REPO_INDEX_IGNORED_DIRS.has(entry.name)) {
        files.push(...listRepoFiles(repo, filePath));
      }
      continue;
    }

    if (!entry.isFile()) continue;

    try {
      const stats = fs.statSync(filePath);
      if (stats.size > REPO_INDEX_MAX_FILE_BYTES) continue;
      const text = fs.readFileSync(filePath, "utf8");
      if (text.includes("\0")) continue;
      files.push({
        path: path.relative(repo, filePath).split(path.sep).join("/"),
        text,
        lowerText: text.toLowerCase(),
      });
    } catch {
      // Ignore unreadable or binary files; inventory must stay best-effort.
    }
  }
  return files;
}

function repoIndex(repo) {
  const resolved = path.resolve(repo);
  if (!repoIndexCache.has(resolved)) {
    repoIndexCache.set(resolved, listRepoFiles(resolved));
  }
  return repoIndexCache.get(resolved);
}

function matchingLines(file, term, limit = 2) {
  const lines = [];
  const needle = term.toLowerCase();
  for (const [index, line] of file.text.split(/\r?\n/).entries()) {
    if (!line.toLowerCase().includes(needle)) continue;
    lines.push(`${file.path}:${index + 1}:${line.trim()}`);
    if (lines.length >= limit) break;
  }
  return lines;
}

function repoEvidence(repo, terms) {
  const evidence = [];
  for (const term of terms) {
    const needle = term.toLowerCase();
    let matchesForTerm = 0;
    for (const file of repoIndex(repo)) {
      if (!file.lowerText.includes(needle)) continue;
      evidence.push({
        term,
        path: file.path,
        lines: matchingLines(file, term),
      });
      matchesForTerm += 1;
      if (matchesForTerm >= 3) break;
    }
  }
  return evidence;
}

function isAuditTrailFile(relativePath) {
  const normalized = relativePath.toLowerCase();
  return (
    normalized === ".claude-plugin/marketplace.json" ||
    normalized.endsWith("/plugin.json") ||
    normalized.endsWith("/dependencies.yaml") ||
    normalized.includes("/test") ||
    normalized.startsWith("scripts/test") ||
    normalized.includes("release") ||
    normalized.includes("manifest") ||
    normalized.includes("marketplace")
  );
}

function implementedCaptureEvidence(opts, body) {
  const terms = extractImplementationTerms(body);
  if (terms.length < 2) return null;

  const matches = repoEvidence(opts.repo, terms);
  const matchedTerms = [...new Set(matches.map((match) => match.term))];
  if (matchedTerms.length < 2) return null;

  const git = gitMatches(opts.repo, matchedTerms);
  const relevantFiles = [...new Set(matches.map((match) => match.path))];
  const auditFiles = relevantFiles.filter(isAuditTrailFile);
  if (git.length === 0 && auditFiles.length === 0) return null;

  return {
    confidence: "strong",
    finding: IMPLEMENTED_WITHOUT_CLOSURE_FINDING,
    terms: matchedTerms,
    git_matches: git.slice(0, 10),
    repo_matches: matches.slice(0, 10),
    relevant_files: relevantFiles.slice(0, 10),
    audit_files: auditFiles.slice(0, 10),
    rationale: "Multiple body-derived implementation terms matched the repo with commit or audit-file evidence; route to hygiene for human closure review.",
  };
}

function candidateBase(opts, fields) {
  const absolutePath = fields.absolute_path ?? "";
  const frontmatter = fields.frontmatter ?? {};
  const title = frontmatter.title || fields.id;

  const base = {
    id: fields.id,
    lane: fields.lane,
    path: absolutePath ? relPath(opts.vault, absolutePath) : fields.path,
    absolute_path: absolutePath,
    kind: frontmatter.kind || fields.kind || "",
    lanes: fields.lanes ?? [fields.lane],
    priority: frontmatter.priority || fields.priority || "",
    project: frontmatter.project || `[[${opts.project}]]`,
    project_slug: fields.project_slug || opts.project,
    repairable: fields.repairable === true,
    sha256: absolutePath && fs.existsSync(absolutePath) ? sha256(absolutePath) : "",
    status: frontmatter.status || fields.status || "",
    title,
    valid: fields.valid === true,
    validation: fields.validation ?? null,
    findings: fields.findings ?? [],
    git_matches: [],
  };

  if (fields.implemented_evidence) {
    base.implemented_evidence = fields.implemented_evidence;
  }

  return base;
}

function workTerms(candidate) {
  return [...new Set([candidate.id, candidate.title, candidate.name].filter(Boolean))];
}

function readWorkItems(opts) {
  const workRoot = path.join(opts.vault, "projects", opts.project, "work");
  const candidates = [];
  const skipped = [];
  const activeCloses = new Set();

  for (const entry of listDirSafe(workRoot).filter((item) => item.isDirectory() && !item.name.startsWith("_"))) {
    const id = entry.name;
    const dirPath = path.join(workRoot, id);
    const specPath = path.join(dirPath, "spec.md");
    const planPath = path.join(dirPath, "plan.md");
    const hasSpec = fs.existsSync(specPath);
    const hasPlan = fs.existsSync(planPath);
    const primaryPath = hasSpec ? specPath : hasPlan ? planPath : "";
    const findings = [];

    if (!hasSpec) findings.push("missing_spec");
    if (!hasPlan) findings.push("missing_plan");

    if (!primaryPath) {
      candidates.push(candidateBase(opts, {
        id,
        lane: "hygiene",
        path: relPath(opts.vault, dirPath),
        status: "",
        valid: false,
        repairable: true,
        findings: ["missing_spec", "missing_plan"],
      }));
      continue;
    }

    const parsed = parseFrontmatter(readText(primaryPath));
    const frontmatter = parsed.data;
    const status = frontmatter.status || "";
    const validation = runSkillwikiValidate(primaryPath);
    const itemFindings = [...findings];
    if (status === "in_progress") itemFindings.push("legacy_status_in_progress");
    if (validation.available !== false && !validation.valid) itemFindings.push("validation_failed");
    const common = {
      absolute_path: primaryPath,
      frontmatter,
      id,
      validation,
      findings: itemFindings,
    };

    for (const closed of Array.isArray(frontmatter.closes) ? frontmatter.closes : []) {
      if (closed) activeCloses.add(closed);
    }

    if (ACTIVE_STATUSES.has(status)) {
      const hasRepairableFindings = itemFindings.length > 0;
      candidates.push(candidateBase(opts, {
        ...common,
        lane: "work",
        lanes: hasRepairableFindings ? ["work", "hygiene"] : ["work"],
        repairable: hasRepairableFindings,
        valid: validation.valid && !hasRepairableFindings,
      }));
      continue;
    }

    if (status === "proposed") {
      candidates.push(candidateBase(opts, {
        ...common,
        lane: "work",
        repairable: true,
        valid: false,
        findings: [...findings, "legacy_status_proposed"],
      }));
      continue;
    }

    if (DONE_STATUSES.has(status)) {
      skipped.push({
        id,
        lane: "work",
        path: relPath(opts.vault, primaryPath),
        project_slug: opts.project,
        reason: status === "abandoned" ? "abandoned" : "completed",
        status,
      });
      continue;
    }

    candidates.push(candidateBase(opts, {
      ...common,
      lane: "hygiene",
      repairable: true,
      valid: false,
      findings: [...findings, status ? `unsupported_status:${status}` : "missing_status"],
    }));
  }

  return { activeCloses, candidates, skipped };
}

function readCaptures(opts, activeCloses) {
  const transcriptRoot = path.join(opts.vault, "raw", "transcripts");
  const candidates = [];
  const skipped = [];

  for (const entry of listDirSafe(transcriptRoot).filter((item) => item.isFile() && item.name.endsWith(".md"))) {
    const filePath = path.join(transcriptRoot, entry.name);
    const text = readText(filePath);
    const parsed = parseFrontmatter(text);
    const frontmatter = parsed.data;
    const kind = frontmatter.kind || "";
    const project = frontmatter.project || "";
    const relativePath = relPath(opts.vault, filePath);

    if (activeCloses.has(relativePath)) {
      skipped.push({ id: entry.name, lane: "captures", path: relativePath, reason: "already_claimed" });
      continue;
    }

    if (!CAPTURE_KINDS.has(kind)) {
      skipped.push({
        id: entry.name,
        kind,
        lane: "captures",
        path: relativePath,
        project_slug: opts.project,
        reason: SKIPPED_CAPTURE_KINDS.has(kind) ? "non_executable_capture_kind" : "unsupported_capture_kind",
      });
      continue;
    }

    if (project !== `[[${opts.project}]]`) {
      skipped.push({
        id: entry.name,
        kind,
        lane: "captures",
        path: relativePath,
        project,
        project_slug: opts.project,
        reason: project ? "project_mismatch" : "missing_project",
      });
      continue;
    }

    const implementedEvidence = implementedCaptureEvidence(opts, bodyText(text, parsed));
    if (implementedEvidence) {
      candidates.push(candidateBase(opts, {
        absolute_path: filePath,
        frontmatter,
        id: entry.name.replace(/\.md$/, ""),
        lane: "hygiene",
        kind,
        repairable: true,
        valid: true,
        findings: [IMPLEMENTED_WITHOUT_CLOSURE_FINDING],
        implemented_evidence: implementedEvidence,
      }));
      continue;
    }

    candidates.push(candidateBase(opts, {
      absolute_path: filePath,
      frontmatter,
      id: entry.name.replace(/\.md$/, ""),
      lane: "captures",
      kind,
      repairable: true,
      valid: true,
    }));
  }

  return { candidates, skipped };
}

function score(candidate) {
  const status = candidate.status;
  const priority = candidate.priority;
  if (candidate.lane === "work" && (status === "in-progress" || status === "in_progress")) return 10;
  if (candidate.lane === "work" && priority === "high" && status === "planned") return 20;
  if (candidate.findings.length > 0 && candidate.lane === "work") return 30;
  if (candidate.lane === "captures") return 40;
  if (candidate.lane === "work" && priority === "medium" && status === "planned") return 50;
  if (candidate.lane === "work" && priority === "low" && status === "planned") return 60;
  if (candidate.lane === "hygiene") return 70;
  return 80;
}

function filterAndSelect(opts, candidates) {
  const filtered = candidates
    .map((candidate) => {
      if (opts.lanes.has(candidate.lane)) return candidate;
      const matchingLane = candidate.lanes.find((lane) => opts.lanes.has(lane));
      return matchingLane ? { ...candidate, lane: matchingLane } : null;
    })
    .filter(Boolean)
    .filter((candidate) => {
      if (!opts.work) return true;
      const target = opts.work.replace(/\/$/, "");
      return candidate.id === target || candidate.path.includes(`/work/${target}/`) || candidate.path.endsWith(`/work/${target}`);
    })
    .sort((a, b) => {
      const scoreDiff = score(a) - score(b);
      if (scoreDiff !== 0) return scoreDiff;
      return a.id.localeCompare(b.id);
    });

  const selected = opts.all ? filtered : filtered.slice(0, opts.limit);
  for (const candidate of selected) {
    candidate.git_matches = gitMatches(opts.repo, workTerms(candidate));
  }
  return { selected, total: filtered.length };
}

function readProjectInventory(opts, project) {
  const projectOpts = { ...opts, project };
  const work = readWorkItems(projectOpts);
  const captures = readCaptures(projectOpts, work.activeCloses);
  const candidates = [...work.candidates, ...captures.candidates];
  const skipped = [...work.skipped, ...captures.skipped];
  return {
    candidates,
    project,
    skipped,
    summary: {
      slug: project,
      candidates: candidates.length,
      selected: 0,
      skipped: skipped.length,
    },
  };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    process.stdout.write(`${usage()}\n`);
    return 0;
  }

  const output = {
    candidates: [],
    errors: [...opts.errors],
    project: opts.allProjects ? null : opts.project,
    projects: [],
    repo: opts.repo,
    scope: {
      all: opts.all,
      all_projects: opts.allProjects,
      lanes: [...opts.lanes],
      limit: opts.limit,
      work: opts.work || null,
    },
    skipped: [],
    totals: {
      selected: 0,
      unfiltered_candidates: 0,
      filtered_candidates: 0,
      projects: 0,
      skipped: 0,
    },
    vault: opts.vault,
  };

  if (opts.errors.length > 0) {
    process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
    return 2;
  }

  const projectSlugs = opts.allProjects ? listProjectSlugs(opts.vault) : [opts.project];
  const projectInventories = projectSlugs.map((project) => readProjectInventory(opts, project));
  const allCandidates = projectInventories.flatMap((inventory) => inventory.candidates);
  const allSkipped = projectInventories.flatMap((inventory) => inventory.skipped);
  const { selected, total } = filterAndSelect(opts, allCandidates);

  for (const inventory of projectInventories) {
    inventory.summary.selected = selected.filter((candidate) => candidate.project_slug === inventory.project).length;
  }

  output.candidates = selected;
  output.projects = opts.allProjects ? projectInventories.map((inventory) => inventory.summary) : [];
  output.skipped = opts.allProjects ? dedupeSkipped(allSkipped) : allSkipped;
  output.totals = {
    selected: selected.length,
    unfiltered_candidates: allCandidates.length,
    filtered_candidates: total,
    projects: projectSlugs.length,
    skipped: output.skipped.length,
  };

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  return 0;
}

process.exitCode = main();
