#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {
  compareSupportedSemver,
  parseSupportedSemver,
} = require("../skills/dev-loop/scripts/dev-loop-version.js");

function usage() {
  return [
    "Usage: check-plugin-release-drift.js [--repo <path>] [--skill <name>]",
    "",
    "Fail when a released plugin version has a different current payload.",
    "The check is read-only and compares Git objects, never filesystem mtimes.",
  ].join("\n");
}

function fail(message) {
  process.stderr.write(`check-plugin-release-drift: ${message}\n`);
  process.exit(1);
}

function parseArgs(argv) {
  const opts = { repo: process.cwd(), skill: "dev-loop" };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      process.stdout.write(`${usage()}\n`);
      process.exit(0);
    }
    if (arg === "--repo" || arg === "--skill") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${arg} requires a value`);
      opts[arg.slice(2)] = value;
      index += 1;
      continue;
    }
    fail(`unknown argument: ${arg}`);
  }
  opts.repo = path.resolve(opts.repo);
  return opts;
}

function runGit(repo, args, { allowStatus = [] } = {}) {
  const result = spawnSync("git", ["-C", repo, ...args], {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.status === 0 || allowStatus.includes(result.status)) return result;
  const detail = (result.stderr || result.stdout || "").trim();
  fail(`git ${args.join(" ")} failed${detail ? `: ${detail}` : ""}`);
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`cannot read ${label}: ${error.message}`);
  }
}

function gitJson(repo, objectPath, label) {
  const result = runGit(repo, ["show", objectPath]);
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`cannot parse ${label} from ${objectPath}: ${error.message}`);
  }
}

function marketplaceEntry(manifest, skill, label) {
  const matches = Array.isArray(manifest.plugins)
    ? manifest.plugins.filter((plugin) => plugin && plugin.name === skill)
    : [];
  if (matches.length !== 1) {
    fail(`${label} must contain exactly one '${skill}' entry (found ${matches.length})`);
  }
  return matches[0];
}

function parseSemver(value, label) {
  const parsed = parseSupportedSemver(value);
  if (!parsed) fail(`${label} is not valid X.Y.Z or X.Y.Z-beta.N semver: '${value}'`);
  return parsed;
}

function validatedManifestSet({ claude, codex, marketplacePlugin }, label) {
  const versions = [claude.version, codex.version, marketplacePlugin.version];
  if (new Set(versions).size !== 1 || versions.some((value) => typeof value !== "string" || !value)) {
    fail(
      `${label} manifest versions disagree: Claude=${versions[0] || "<missing>"} ` +
        `Codex=${versions[1] || "<missing>"} marketplace=${versions[2] || "<missing>"}`,
    );
  }
  parseSemver(versions[0], `${label} manifest version`);
  return { version: versions[0], marketplacePlugin };
}

function currentVersions(repo, skill) {
  const pluginRoot = path.join(repo, "skills", skill);
  const claudePath = path.join(pluginRoot, ".claude-plugin", "plugin.json");
  const codexPath = path.join(pluginRoot, ".codex-plugin", "plugin.json");
  const marketplacePath = path.join(repo, ".claude-plugin", "marketplace.json");

  for (const required of [claudePath, codexPath, marketplacePath]) {
    if (!fs.existsSync(required)) fail(`required manifest missing: ${path.relative(repo, required)}`);
  }

  const claude = readJson(claudePath, path.relative(repo, claudePath));
  const codex = readJson(codexPath, path.relative(repo, codexPath));
  const marketplace = readJson(marketplacePath, path.relative(repo, marketplacePath));
  const marketplacePlugin = marketplaceEntry(marketplace, skill, "current marketplace");
  return validatedManifestSet({ claude, codex, marketplacePlugin }, "current");
}

function matchingTags(repo, skill) {
  const prefix = `${skill}-`;
  const output = runGit(repo, ["tag", "--list", `${prefix}*`]).stdout.trim();
  if (!output) return [];
  const tags = [];
  for (const tag of output.split(/\r?\n/)) {
    if (!tag.startsWith(prefix)) continue;
    const version = tag.slice(prefix.length);
    // General rule: if version does not start with a digit, ignore as sibling / non-semver suffix
    if (!/^[0-9]/.test(version)) {
      continue;
    }
    // If it starts with a digit, it is an intended release tag and must parse as valid semver
    tags.push({ tag, version, parsed: parseSemver(version, `tag ${tag}`) });
  }
  return tags;
}

function latestTag(repo, skill) {
  const tags = matchingTags(repo, skill);
  if (tags.length === 0) return null;
  tags.sort((left, right) => compareSupportedSemver(right.parsed, left.parsed));
  return tags[0];
}

function taggedVersion(repo, tag, skill) {
  const claudePath = `${tag}:skills/${skill}/.claude-plugin/plugin.json`;
  const codexPath = `${tag}:skills/${skill}/.codex-plugin/plugin.json`;
  const marketplacePath = `${tag}:.claude-plugin/marketplace.json`;
  const claude = gitJson(repo, claudePath, "tagged Claude manifest");
  const codex = gitJson(repo, codexPath, "tagged Codex manifest");
  const marketplace = marketplaceEntry(
    gitJson(repo, marketplacePath, "tagged marketplace"),
    skill,
    "tagged marketplace",
  );
  return validatedManifestSet({ claude, codex, marketplacePlugin: marketplace }, `tag ${tag}`);
}

function canonicalJson(value) {
  if (Array.isArray(value)) return value.map(canonicalJson);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, canonicalJson(value[key])]),
  );
}

function payloadChanged(repo, tag, skill, currentMarketplace, taggedMarketplace) {
  const pluginPath = `skills/${skill}`;
  const diff = runGit(repo, ["diff", "--quiet", tag, "--", pluginPath], { allowStatus: [1] });
  if (diff.status === 1) return true;

  const untracked = runGit(repo, ["ls-files", "--others", "--exclude-standard", "--", pluginPath]).stdout.trim();
  if (untracked) return true;

  return JSON.stringify(canonicalJson(currentMarketplace)) !== JSON.stringify(canonicalJson(taggedMarketplace));
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const gitRoot = runGit(opts.repo, ["rev-parse", "--show-toplevel"]).stdout.trim();
  const requestedRoot = fs.realpathSync(opts.repo);
  const resolvedGitRoot = fs.realpathSync(gitRoot);
  if (resolvedGitRoot !== requestedRoot) {
    fail(`--repo must be the Git repository root: ${opts.repo}`);
  }
  opts.repo = resolvedGitRoot;

  const current = currentVersions(opts.repo, opts.skill);
  const latest = latestTag(opts.repo, opts.skill);
  if (!latest) {
    process.stdout.write(
      `check-plugin-release-drift: no matching ${opts.skill}-* tag; bootstrap release check passed at ${current.version}\n`,
    );
    return;
  }

  const tagged = taggedVersion(opts.repo, latest.tag, opts.skill);
  if (tagged.version !== latest.version) {
    fail(`tag ${latest.tag} declares manifest version ${tagged.version}, expected ${latest.version}`);
  }

  const currentParsed = parseSemver(current.version, "current manifest version");
  const order = compareSupportedSemver(currentParsed, latest.parsed);
  if (order < 0) {
    fail(`current version ${current.version} is older than latest tag ${latest.tag}`);
  }

  const changed = payloadChanged(
    opts.repo,
    latest.tag,
    opts.skill,
    current.marketplacePlugin,
    tagged.marketplacePlugin,
  );
  if (order === 0 && changed) {
    fail(
      `${opts.skill} payload differs from ${latest.tag} while manifests still declare ${current.version}; ` +
        "same-version mutation breaks immutable installed caches. " +
        `Run ./scripts/bump-version.sh ${opts.skill} patch for stable work, or use an explicit beta bump before distribution.`,
    );
  }

  if (order > 0) {
    process.stdout.write(
      `check-plugin-release-drift: ${opts.skill} version advanced ${latest.version} -> ${current.version}; payload may be released immutably\n`,
    );
    return;
  }

  process.stdout.write(
    `check-plugin-release-drift: ${opts.skill} ${current.version} payload unchanged from ${latest.tag}\n`,
  );
}

main();
