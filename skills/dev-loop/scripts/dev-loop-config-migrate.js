#!/usr/bin/env node
"use strict";

/**
 * Read-only vault config migration advisor (legacy top-level vault → knowledge_backends).
 */

const fs = require("node:fs");
const path = require("node:path");

const SCHEMA_VERSION = "dev-loop-config-migrate.v1";

function usage() {
  return [
    "Usage: dev-loop-config-migrate.js --repo <path> [options]",
    "",
    "Options:",
    "  --format markdown|json|both   default: both",
    "  --no-write                    stdout only",
    "  --help",
  ].join("\n");
}

function parseArgs(argv) {
  const opts = { format: "both", noWrite: false, repo: "", errors: [] };
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
      const v = argv[i + 1];
      if (!v || v.startsWith("--")) {
        opts.errors.push(`${arg} requires a value`);
        continue;
      }
      i += 1;
      if (arg === "--repo") opts.repo = path.resolve(v);
      else opts.format = v;
    }
  }
  if (!opts.repo && !opts.help) opts.repo = process.cwd();
  return opts;
}

function extractYamlBlocks(text) {
  const blocks = [];
  const re = /```ya?ml\n([\s\S]*?)```/gi;
  let m;
  while ((m = re.exec(text)) !== null) blocks.push(m[1]);
  return blocks;
}

function readConfig(repo) {
  const configPath = path.join(repo, ".claude", "dev-loop.config.md");
  if (!fs.existsSync(configPath)) {
    return { configPath, missing: true, raw: "", flat: {} };
  }
  const raw = fs.readFileSync(configPath, "utf8");
  const flat = {};
  for (const inner of extractYamlBlocks(raw)) {
    for (const line of inner.split(/\r?\n/)) {
      const m = line.trim().match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
      if (!m || line.trim().startsWith("#")) continue;
      let val = m[2].trim().replace(/^["']|["']$/g, "");
      flat[m[1]] = val === "true" ? true : val === "false" ? false : val;
    }
  }
  return { configPath, missing: false, raw, flat };
}

function detectVaultShape(raw) {
  const legacyMatch = raw.match(/^vault:\s*(\S+)/m);
  const legacy = legacyMatch ? legacyMatch[1].replace(/["']/g, "") : null;
  const nestedMatch = raw.match(/knowledge_backends:\s*\n[\s\S]*?skillwiki:\s*\n[\s\S]*?vault:\s*(\S+)/);
  const nested = nestedMatch ? nestedMatch[1].replace(/["']/g, "") : null;
  const hasBlock = /knowledge_backends:/.test(raw);
  return { legacy, nested, hasBlock };
}

function advise(shape, flat) {
  const recs = [];
  let state = "unknown";
  let suggestedYaml = "";

  if (!shape.legacy && !shape.nested && !shape.hasBlock) {
    state = "no_vault_configured";
    recs.push("Add `knowledge_backends.skillwiki.vault: auto` when using skillwiki (see project-config template).");
    suggestedYaml = [
      "knowledge_backends:",
      "  skillwiki:",
      "    vault: auto",
    ].join("\n");
  } else if (shape.legacy && !shape.hasBlock) {
    state = "legacy_top_level_only";
    recs.push("Move top-level `vault` under `knowledge_backends.skillwiki.vault`.");
    recs.push("Prefer `vault: auto` for portable resolution via `skillwiki path`.");
    const v = shape.legacy === "auto" ? "auto" : shape.legacy;
    suggestedYaml = [
      "# Remove top-level: vault: ...",
      "knowledge_backends:",
      "  skillwiki:",
      `    vault: ${v}`,
    ].join("\n");
  } else if (shape.legacy && shape.hasBlock && shape.nested) {
    if (shape.legacy !== shape.nested) {
      state = "conflicting_vault_paths";
      recs.push(`Top-level vault (${shape.legacy}) differs from nested (${shape.nested}) — pick one source of truth.`);
      recs.push("Delete top-level `vault:` after aligning nested `knowledge_backends.skillwiki.vault`.");
    } else {
      state = "redundant_legacy_and_nested";
      recs.push("Nested vault is already set — remove redundant top-level `vault:` line.");
    }
    suggestedYaml = [
      "knowledge_backends:",
      "  skillwiki:",
      `    vault: ${shape.nested}`,
    ].join("\n");
  } else if (!shape.legacy && shape.hasBlock && shape.nested) {
    state = "modern_nested_only";
    recs.push("Config already uses knowledge_backends.skillwiki.vault — no migration required.");
    if (shape.nested !== "auto" && flat.knowledge_layer !== "none") {
      recs.push("Consider `vault: auto` unless this machine must pin an absolute path.");
    }
  } else if (shape.legacy && shape.hasBlock && !shape.nested) {
    state = "legacy_with_empty_nested";
    recs.push("Add `vault:` under `knowledge_backends.skillwiki` and remove top-level alias.");
    suggestedYaml = [
      "knowledge_backends:",
      "  skillwiki:",
      `    vault: ${shape.legacy}`,
    ].join("\n");
  }

  const overall =
    state === "conflicting_vault_paths"
      ? "blocked"
      : state === "legacy_top_level_only" || state === "redundant_legacy_and_nested" || state === "legacy_with_empty_nested"
        ? "degraded"
        : "healthy";

  return { state, overall, recommendations: recs, suggested_yaml: suggestedYaml };
}

function buildReport(repo) {
  const cfg = readConfig(repo);
  if (cfg.missing) {
    return {
      schema_version: SCHEMA_VERSION,
      read_only: true,
      writes_executed: false,
      config_path: cfg.configPath,
      overall: { state: "blocked", reason: "missing config" },
      vault_shape: null,
      migration: { state: "missing_config", recommendations: ["Create .claude/dev-loop.config.md from template"] },
    };
  }
  const shape = detectVaultShape(cfg.raw);
  const migration = advise(shape, cfg.flat);
  return {
    schema_version: SCHEMA_VERSION,
    read_only: true,
    writes_executed: false,
    generated_at: new Date().toISOString(),
    config_path: cfg.configPath,
    vault_shape: shape,
    overall: { state: migration.overall, reason: migration.state },
    migration,
  };
}

function renderMd(json) {
  const lines = [
    "# Dev Loop Config Migration Advisor",
    "",
    `- Overall: **${json.overall.state}** (${json.migration?.state || json.overall.reason})`,
    `- Config: ${json.config_path}`,
    `- Read-only: ${json.read_only}`,
    "",
    "## Vault shape",
  ];
  if (json.vault_shape) {
    lines.push(`- Top-level legacy \`vault:\`: ${json.vault_shape.legacy || "(none)"}`);
    lines.push(`- \`knowledge_backends.skillwiki.vault\`: ${json.vault_shape.nested || "(none)"}`);
  }
  lines.push("", "## Recommendations");
  for (const r of json.migration?.recommendations || []) lines.push(`- ${r}`);
  if (json.migration?.suggested_yaml) {
    lines.push("", "## Suggested YAML fragment", "```yaml", json.migration.suggested_yaml, "```");
  }
  return lines.join("\n");
}

function writeArtifacts(repo, json, md, noWrite) {
  if (noWrite) return { mdPath: null, jsonPath: null };
  const stamp = json.generated_at.replace(/[:.]/g, "-").slice(0, 19);
  const dir = path.join(repo, ".claude", "dev-loop", "migrate");
  fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, `${stamp}-migrate`);
  fs.writeFileSync(`${base}.json`, `${JSON.stringify(json, null, 2)}\n`);
  fs.writeFileSync(`${base}.md`, md);
  return { mdPath: `${base}.md`, jsonPath: `${base}.json` };
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
  const json = buildReport(opts.repo);
  const md = renderMd(json);
  writeArtifacts(opts.repo, json, md, opts.noWrite);
  if (opts.format === "markdown") process.stdout.write(md);
  else process.stdout.write(`${JSON.stringify(json, null, 2)}\n`);
  return json.overall.state === "blocked" ? 1 : 0;
}

process.exitCode = main();