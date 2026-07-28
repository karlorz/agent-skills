#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const STATUS_SCHEMA = "design-guide-usage-status/v1";
const MARKER_SCHEMA = "design-guide-usage/v1";
const WORK_RELATIVE_PATH = path.join(
  "projects",
  "agent-skills",
  "work",
  "2026-07-28-design-guide-usage-tracking",
  "log.md",
);
const MAX_INPUT_BYTES = 64 * 1024;

class UserError extends Error {}

const STRING_FIELDS = {
  date: 10,
  host: 120,
  project_class: 240,
  task_type: 160,
  helpful_result: 2000,
  friction: 2000,
  proposed_change: 2000,
  verification: 2000,
  follow_up: 1200,
  revision_validation: 2000,
};
const BOOLEAN_FIELDS = [
  "repeated",
  "trigger_context_cost_reviewed",
  "component_structure_compared",
  "accepted_revision",
];
const ALLOWED_FIELDS = new Set([
  ...Object.keys(STRING_FIELDS),
  ...BOOLEAN_FIELDS,
  "trigger",
  "sections_used",
]);
const MARKER_STRING_FIELDS = new Set([
  "id",
  "date",
  "host",
  "project_class",
  "task_type",
  "trigger",
  "revision_validation",
]);
const MARKER_BOOLEAN_FIELDS = new Set([
  "trigger_context_cost_reviewed",
  "component_structure_compared",
  "accepted_revision",
]);
const MARKER_FIELDS = new Set([
  "schema",
  ...MARKER_STRING_FIELDS,
  ...MARKER_BOOLEAN_FIELDS,
]);
const MARKER_STRING_LIMITS = {
  id: 128,
  date: STRING_FIELDS.date,
  host: STRING_FIELDS.host,
  project_class: STRING_FIELDS.project_class,
  task_type: STRING_FIELDS.task_type,
  trigger: 9,
  revision_validation: STRING_FIELDS.revision_validation,
};
const SECRET_PATTERNS = [
  ["private key", /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/i],
  ["bearer token", /(?:authorization\s*:\s*)?bearer\s+[a-z0-9._~+/=-]{16,}/i],
  ["OpenAI-style key", /\bsk-[a-z0-9_-]{20,}\b/i],
  ["GitHub token", /\bgh[pousr]_[a-z0-9]{20,}\b/i],
  ["Slack token", /\bxox[baprs]-[a-z0-9-]{20,}\b/i],
  ["AWS access key", /\bAKIA[0-9A-Z]{16}\b/],
  ["password assignment", /\bpassword\s*[:=]\s*[^\s,;]{8,}/i],
  ["cookie header", /\bcookie\s*:\s*[^\s;=]+=[^\s;]{8,}/i],
];

function usage() {
  return [
    "Usage:",
    "  design-guide-usage.js record --input <json-file|-> [--vault <path>] [--dry-run]",
    "  design-guide-usage.js status [--vault <path>] [--json]",
    "",
    "Record one explicitly reviewed design-guide use or report promotion-review readiness.",
    "The command never scans agent sessions, hooks, shell history, or installed-skill state.",
    "",
    "record input fields:",
    "  date, host, project_class, task_type, trigger (explicit|automatic),",
    "  sections_used[], helpful_result, friction, repeated, proposed_change,",
    "  verification, follow_up, trigger_context_cost_reviewed,",
    "  component_structure_compared, accepted_revision, revision_validation",
    "",
    "Example input:",
    '  {"date":"2026-07-28","host":"macos-dev","project_class":"dashboard",',
    '   "task_type":"new component","trigger":"explicit",',
    '   "sections_used":["Design Tokens"],"helpful_result":"...",',
    '   "friction":"no issue","repeated":false,"proposed_change":"no change",',
    '   "verification":"tests and browser smoke passed","follow_up":"record next use",',
    '   "trigger_context_cost_reviewed":true,"component_structure_compared":true,',
    '   "accepted_revision":false,"revision_validation":""}',
    "",
    "Privacy:",
    "  Likely credentials and authenticating secrets are rejected. Replace them with",
    "  an explicit marker such as [REDACTED:token]. There is no bypass flag.",
    "",
    "Readiness:",
    "  eligible=true opens a human promotion review only. It does not copy, package,",
    "  publish, install, tag, release, or otherwise promote the candidate skill.",
  ].join("\n");
}

function fail(message) {
  throw new UserError(message);
}

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    process.stdout.write(`${usage()}\n`);
    process.exit(argv.length === 0 ? 1 : 0);
  }

  const command = argv[0];
  if (!new Set(["record", "status"]).has(command)) {
    fail(`unknown command: ${command}`);
  }

  const options = {
    command,
    dryRun: false,
    input: "",
    json: false,
    vault: "",
  };

  for (let index = 1; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--dry-run") {
      if (command !== "record") fail("--dry-run is only valid with record");
      options.dryRun = true;
      continue;
    }
    if (arg === "--json") {
      if (command !== "status") fail("--json is only valid with status");
      options.json = true;
      continue;
    }
    if (arg === "--input" || arg === "--vault") {
      const value = argv[index + 1];
      if (!value || (value.startsWith("--") && value !== "-")) {
        fail(`${arg} requires a value`);
      }
      options[arg.slice(2)] = value;
      index += 1;
      continue;
    }
    fail(`unknown argument: ${arg}`);
  }

  if (command === "record" && !options.input) fail("record requires --input <json-file|->");
  if (command === "status" && options.input) fail("--input is only valid with record");
  if (options.vault) options.vault = path.resolve(options.vault);
  return options;
}

function parseSkillwikiPath(output) {
  const trimmed = String(output || "").trim();
  if (!trimmed) return "";
  try {
    const parsed = JSON.parse(trimmed);
    const value = parsed && parsed.data && parsed.data.path;
    return typeof value === "string" ? value : "";
  } catch {
    return trimmed.replace(/\s+\(via .*\)$/, "");
  }
}

function resolveVault(explicitVault) {
  if (explicitVault) return explicitVault;
  const result = spawnSync("skillwiki", ["path"], {
    encoding: "utf8",
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) {
    const detail = String(result.stderr || result.stdout || "").trim();
    fail(`skillwiki path failed${detail ? `: ${detail}` : ""}; pass --vault <path> deliberately`);
  }
  const resolved = parseSkillwikiPath(result.stdout);
  if (!resolved) fail("skillwiki path returned no vault path; pass --vault <path> deliberately");
  return path.resolve(resolved);
}

function targetPath(vault) {
  const vaultRoot = path.resolve(vault);
  const target = path.resolve(vaultRoot, WORK_RELATIVE_PATH);
  const relative = path.relative(vaultRoot, target);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("resolved evidence log escapes the selected vault");
  }
  if (!fs.existsSync(target)) fail(`evidence log not found: ${target}`);
  if (fs.lstatSync(target).isSymbolicLink()) fail(`evidence log must not be a symbolic link: ${target}`);
  const realTarget = fs.realpathSync(target);
  const realRelative = path.relative(fs.realpathSync(vaultRoot), realTarget);
  if (realRelative.startsWith("..") || path.isAbsolute(realRelative)) {
    fail("real evidence log path escapes the selected vault");
  }
  return target;
}

function readBounded(filePath) {
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) fail(`not a regular file: ${filePath}`);
  if (stat.size > MAX_INPUT_BYTES * 16) fail(`file is unexpectedly large: ${filePath}`);
  return fs.readFileSync(filePath, "utf8");
}

function readInput(inputPath) {
  let body;
  if (inputPath === "-") {
    body = fs.readFileSync(0);
  } else {
    const resolved = path.resolve(inputPath);
    const stat = fs.statSync(resolved);
    if (!stat.isFile()) fail(`input is not a regular file: ${resolved}`);
    if (stat.size > MAX_INPUT_BYTES) fail(`input exceeds ${MAX_INPUT_BYTES} bytes`);
    body = fs.readFileSync(resolved);
  }
  if (body.length > MAX_INPUT_BYTES) fail(`input exceeds ${MAX_INPUT_BYTES} bytes`);
  let value;
  try {
    value = JSON.parse(body.toString("utf8"));
  } catch (error) {
    fail(`cannot parse input JSON: ${error.message}`);
  }
  if (!value || Array.isArray(value) || typeof value !== "object") {
    fail("input JSON must be an object");
  }
  return value;
}

function normalizedString(value) {
  return value.trim().split(/\s+/).join(" ");
}

function isRedactionMarker(value) {
  return /^\[REDACTED:[a-z0-9_-]+(?::[a-z0-9_-]+)?\]$/i.test(value.trim());
}

function secretFinding(value) {
  if (isRedactionMarker(value)) return "";
  const withoutRedactions = value.replace(/\[REDACTED:[^\]]+\]/gi, "[redacted]");
  const match = SECRET_PATTERNS.find(([, pattern]) => pattern.test(withoutRedactions));
  return match ? match[0] : "";
}

function assertSafeString(field, value) {
  if (value.includes("<!--") || value.includes("-->")) {
    fail(`${field} contains a forbidden HTML-comment delimiter`);
  }
  const finding = secretFinding(value);
  if (finding) {
    fail(`${field} contains a likely secret (${finding}); replace it with [REDACTED:<kind>]`);
  }
}

function validateDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) fail("date must use YYYY-MM-DD");
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    fail("date must be a real calendar date in YYYY-MM-DD form");
  }
}

function validateEvidence(raw) {
  const unknown = Object.keys(raw).filter((key) => !ALLOWED_FIELDS.has(key));
  if (unknown.length > 0) fail(`unknown input fields: ${unknown.sort().join(", ")}`);

  const evidence = {};
  for (const [field, maxLength] of Object.entries(STRING_FIELDS)) {
    const value = raw[field];
    if (typeof value !== "string") fail(`${field} must be a string`);
    const normalized = normalizedString(value);
    if (field !== "revision_validation" && !normalized) fail(`${field} must not be empty`);
    if (normalized.length > maxLength) fail(`${field} exceeds ${maxLength} characters`);
    assertSafeString(field, normalized);
    evidence[field] = normalized;
  }

  validateDate(evidence.date);
  if (!new Set(["explicit", "automatic"]).has(raw.trigger)) {
    fail("trigger must be one of: explicit, automatic");
  }
  evidence.trigger = raw.trigger;

  if (!Array.isArray(raw.sections_used) || raw.sections_used.length === 0) {
    fail("sections_used must be a non-empty array");
  }
  if (raw.sections_used.length > 20) fail("sections_used must contain at most 20 entries");
  evidence.sections_used = raw.sections_used.map((value, index) => {
    if (typeof value !== "string") fail(`sections_used[${index}] must be a string`);
    const normalized = normalizedString(value);
    if (!normalized) fail(`sections_used[${index}] must not be empty`);
    if (normalized.length > 160) fail(`sections_used[${index}] exceeds 160 characters`);
    assertSafeString(`sections_used[${index}]`, normalized);
    return normalized;
  });

  for (const field of BOOLEAN_FIELDS) {
    if (typeof raw[field] !== "boolean") fail(`${field} must be a boolean`);
    evidence[field] = raw[field];
  }
  if (evidence.accepted_revision && !evidence.revision_validation) {
    fail("revision_validation must describe verification when accepted_revision is true");
  }
  if (!evidence.accepted_revision && evidence.revision_validation) {
    fail("revision_validation must be empty when accepted_revision is false");
  }

  evidence.id = crypto
    .createHash("sha256")
    .update(
      JSON.stringify([
        evidence.date,
        evidence.host,
        evidence.project_class,
        evidence.task_type,
        evidence.trigger,
        evidence.verification,
      ]),
    )
    .digest("hex")
    .slice(0, 20);
  return evidence;
}

function parseMarkers(body) {
  const records = [];
  const seen = new Set();
  const pattern = /<!-- design-guide-usage\/v1 ([^\n]*?) -->/g;
  let match;
  while ((match = pattern.exec(body)) !== null) {
    let record;
    try {
      record = JSON.parse(match[1]);
    } catch (error) {
      fail(`malformed evidence marker at byte ${match.index}: ${error.message}`);
    }
    if (!record || typeof record !== "object" || Array.isArray(record)) {
      fail(`malformed evidence marker at byte ${match.index}: marker JSON must be an object`);
    }
    validateMarker(record, match.index);
    if (seen.has(record.id)) fail(`duplicate evidence marker id in log: ${record.id}`);
    seen.add(record.id);
    records.push(record);
  }

  const markerOpenings = body.match(/<!-- design-guide-usage\/v1 /g) || [];
  if (markerOpenings.length !== records.length) {
    fail("malformed evidence marker: unterminated or multiline marker");
  }
  return records;
}

function validateMarker(record, markerIndex) {
  const malformed = (message) => fail(`malformed evidence marker at byte ${markerIndex}: ${message}`);
  const unknown = Object.keys(record).filter((key) => !MARKER_FIELDS.has(key));
  const missing = [...MARKER_FIELDS].filter((key) => !Object.hasOwn(record, key));
  if (unknown.length > 0) malformed(`unknown fields: ${unknown.sort().join(", ")}`);
  if (missing.length > 0) malformed(`missing fields: ${missing.sort().join(", ")}`);
  if (record.schema !== MARKER_SCHEMA) malformed(`schema must be ${MARKER_SCHEMA}`);

  for (const field of MARKER_STRING_FIELDS) {
    if (typeof record[field] !== "string") malformed(`${field} must be a string`);
    const normalized = normalizedString(record[field]);
    if (record[field] !== normalized) malformed(`${field} must use normalized single-line text`);
    if (field !== "revision_validation" && !normalized) {
      malformed(`${field} must not be empty`);
    }
    if (normalized.length > MARKER_STRING_LIMITS[field]) {
      malformed(`${field} exceeds ${MARKER_STRING_LIMITS[field]} characters`);
    }
    try {
      assertSafeString(field, normalized);
    } catch (error) {
      malformed(error.message);
    }
  }
  if (!/^[a-z0-9][a-z0-9._:-]{0,127}$/i.test(record.id)) {
    malformed("id must use 1-128 safe identifier characters");
  }
  try {
    validateDate(record.date);
  } catch (error) {
    malformed(error.message);
  }
  if (!new Set(["explicit", "automatic"]).has(record.trigger)) {
    malformed("trigger must be one of: explicit, automatic");
  }
  for (const field of MARKER_BOOLEAN_FIELDS) {
    if (typeof record[field] !== "boolean") malformed(`${field} must be a boolean`);
  }
  if (record.accepted_revision && !record.revision_validation.trim()) {
    malformed("revision_validation must describe verification when accepted_revision is true");
  }
  if (!record.accepted_revision && record.revision_validation.trim()) {
    malformed("revision_validation must be empty when accepted_revision is false");
  }
}

function readiness(target, records) {
  const projectClasses = new Set(records.map((record) => record.project_class));
  const taskTypes = new Set(records.map((record) => record.task_type));
  const triggerReviewed = records.some((record) => record.trigger_context_cost_reviewed);
  const structureCompared = records.some((record) => record.component_structure_compared);
  const unvalidatedRevisions = records.filter(
    (record) => record.accepted_revision && !record.revision_validation.trim(),
  ).length;

  const unmet = [
    [records.length === 0, "record_first_meaningful_use"],
    [records.length < 5, "record_more_meaningful_uses"],
    [projectClasses.size < 2, "record_second_project_class"],
    [taskTypes.size < 2, "record_second_task_type"],
    [!triggerReviewed, "review_trigger_and_context_cost"],
    [!structureCompared, "compare_component_structure"],
    [unvalidatedRevisions > 0, "validate_accepted_skill_revisions"],
  ].find(([condition]) => condition);
  const eligible = !unmet;
  const nextAction = unmet ? unmet[1] : "begin_human_promotion_review";

  return {
    schema: STATUS_SCHEMA,
    target,
    counts: {
      uses: records.length,
      project_classes: projectClasses.size,
      task_types: taskTypes.size,
    },
    distinct: {
      project_classes: [...projectClasses].sort(),
      task_types: [...taskTypes].sort(),
    },
    signals: {
      trigger_context_cost_reviewed: triggerReviewed,
      component_structure_compared: structureCompared,
      unvalidated_accepted_revisions: unvalidatedRevisions,
      malformed_markers: 0,
      duplicate_markers: 0,
    },
    thresholds: {
      uses: 5,
      project_classes: 2,
      task_types: 2,
      trigger_context_cost_reviewed: true,
      component_structure_compared: true,
      unvalidated_accepted_revisions: 0,
    },
    eligible,
    next_action: nextAction,
  };
}

function markerRecord(evidence) {
  return {
    schema: MARKER_SCHEMA,
    id: evidence.id,
    date: evidence.date,
    host: evidence.host,
    project_class: evidence.project_class,
    task_type: evidence.task_type,
    trigger: evidence.trigger,
    trigger_context_cost_reviewed: evidence.trigger_context_cost_reviewed,
    component_structure_compared: evidence.component_structure_compared,
    accepted_revision: evidence.accepted_revision,
    revision_validation: evidence.revision_validation,
  };
}

function markerJson(record) {
  return JSON.stringify(record).replace(/</g, "\\u003c").replace(/>/g, "\\u003e");
}

function renderEntry(evidence, record) {
  return [
    `### ${evidence.date} — ${evidence.task_type}`,
    "",
    `<!-- ${MARKER_SCHEMA} ${markerJson(record)} -->`,
    "",
    `- Evidence ID: \`${evidence.id}\``,
    `- Host: \`${evidence.host}\``,
    `- Project or project class: ${evidence.project_class}`,
    `- Task type: ${evidence.task_type}`,
    `- Trigger: ${evidence.trigger}`,
    `- Skill sections used: ${evidence.sections_used.join(", ")}`,
    `- Helpful guidance and observed result: ${evidence.helpful_result}`,
    `- Friction or incorrect assumptions: ${evidence.friction}`,
    `- Repeated observation: ${evidence.repeated ? "yes" : "no"}`,
    `- Proposed skill change: ${evidence.proposed_change}`,
    `- UI or behavior verification: ${evidence.verification}`,
    `- Trigger/context-cost reviewed: ${evidence.trigger_context_cost_reviewed ? "yes" : "no"}`,
    `- Component structure compared: ${evidence.component_structure_compared ? "yes" : "no"}`,
    `- Accepted skill revision: ${evidence.accepted_revision ? "yes" : "no"}`,
    `- Revision validation: ${evidence.revision_validation || "not applicable"}`,
    `- Follow-up: ${evidence.follow_up}`,
    "",
  ].join("\n");
}

function appendAtomically(target, originalBody, nextBody) {
  const lockPath = `${target}.lock`;
  let lockFd;
  let tempPath = "";
  try {
    try {
      lockFd = fs.openSync(lockPath, "wx", 0o600);
    } catch (error) {
      if (error.code === "EEXIST") fail(`lock is already held: ${lockPath}`);
      throw error;
    }
    fs.writeFileSync(lockFd, `${process.pid}\n`, "utf8");
    fs.fsyncSync(lockFd);

    if (
      process.env.DESIGN_GUIDE_USAGE_TESTING === "1" &&
      process.env.DESIGN_GUIDE_USAGE_TEST_FAIL_STAGE === "mutate-target"
    ) {
      fs.appendFileSync(target, "\nexternal concurrent change\n", "utf8");
    }

    const currentBody = readBounded(target);
    if (currentBody !== originalBody) fail("evidence log changed after validation; retry from fresh state");

    tempPath = path.join(
      path.dirname(target),
      `.${path.basename(target)}.${process.pid}.${crypto.randomBytes(6).toString("hex")}.tmp`,
    );
    const mode = fs.statSync(target).mode & 0o777;
    const tempFd = fs.openSync(tempPath, "wx", mode);
    try {
      fs.writeFileSync(tempFd, nextBody, "utf8");
      fs.fsyncSync(tempFd);
    } finally {
      fs.closeSync(tempFd);
    }

    if (
      process.env.DESIGN_GUIDE_USAGE_TESTING === "1" &&
      process.env.DESIGN_GUIDE_USAGE_TEST_FAIL_STAGE === "before-rename"
    ) {
      fail("simulated failure before rename");
    }
    fs.renameSync(tempPath, target);
    tempPath = "";
  } finally {
    if (tempPath) {
      try {
        fs.unlinkSync(tempPath);
      } catch {}
    }
    if (lockFd !== undefined) {
      try {
        fs.closeSync(lockFd);
      } catch {}
      try {
        fs.unlinkSync(lockPath);
      } catch {}
    }
  }
}

function humanStatus(status) {
  const checks = [
    ["uses", status.counts.uses, status.thresholds.uses],
    ["project_classes", status.counts.project_classes, status.thresholds.project_classes],
    ["task_types", status.counts.task_types, status.thresholds.task_types],
  ];
  return [
    `target: ${status.target}`,
    ...checks.map(([label, actual, expected]) => `${label}: ${actual}/${expected}`),
    `trigger_context_cost_reviewed: ${status.signals.trigger_context_cost_reviewed}`,
    `component_structure_compared: ${status.signals.component_structure_compared}`,
    `unvalidated_accepted_revisions: ${status.signals.unvalidated_accepted_revisions}`,
    `eligible: ${status.eligible}`,
    `next_action: ${status.next_action}`,
  ].join("\n");
}

function runStatus(options) {
  const vault = resolveVault(options.vault);
  const target = targetPath(vault);
  const records = parseMarkers(readBounded(target));
  const status = readiness(target, records);
  process.stdout.write(options.json ? `${JSON.stringify(status, null, 2)}\n` : `${humanStatus(status)}\n`);
}

function runRecord(options) {
  const vault = resolveVault(options.vault);
  const target = targetPath(vault);
  const originalBody = readBounded(target);
  const records = parseMarkers(originalBody);
  const evidence = validateEvidence(readInput(options.input));
  if (records.some((record) => record.id === evidence.id)) {
    fail(`duplicate evidence id: ${evidence.id}`);
  }

  const record = markerRecord(evidence);
  const separator = originalBody.endsWith("\n") ? "\n" : "\n\n";
  const renderedEntry = renderEntry(evidence, record);
  const nextBody = `${originalBody}${separator}${renderedEntry}`;
  const nextStatus = readiness(target, [...records, record]);

  if (!options.dryRun) appendAtomically(target, originalBody, nextBody);
  const summary = [
      `recorded: ${!options.dryRun}`,
      `dry_run: ${options.dryRun}`,
      `evidence_id: ${evidence.id}`,
      `target: ${target}`,
      `uses_after: ${nextStatus.counts.uses}`,
      `eligible_after: ${nextStatus.eligible}`,
      `next_action: ${nextStatus.next_action}`,
    ].join("\n");
  process.stdout.write(`${summary}\n${options.dryRun ? `entry_preview:\n${renderedEntry}` : ""}`);
}

function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.command === "status") runStatus(options);
    else runRecord(options);
  } catch (error) {
    if (error instanceof UserError) {
      process.stderr.write(`design-guide-usage: ${error.message}\n`);
      process.exitCode = 1;
      return;
    }
    throw error;
  }
}

main();
