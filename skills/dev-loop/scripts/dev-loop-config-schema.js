#!/usr/bin/env node
"use strict";

/**
 * Node adapter for the read-only Python/PyYAML config schema bridge.
 *
 * Status, config-lint, and config-migrate share this entrypoint so they all
 * observe the same nested config, provenance, and fail-closed diagnostics.
 */

const path = require("node:path");
const { spawnSync } = require("node:child_process");

const SCHEMA_VERSION = "dev-loop-config-schema.v1";
const DEFAULT_TIMEOUT_MS = 5000;
const MAX_BUFFER_BYTES = 4 * 1024 * 1024;

function failure(code, message, parserAvailable = false) {
  return {
    schema_version: SCHEMA_VERSION,
    ok: false,
    read_only: true,
    writes_executed: false,
    config: {},
    provenance: {},
    blocks: [],
    errors: [{ code, message, path: null, line: null, block_index: null }],
    warnings: [],
    parser: {
      name: "pyyaml",
      available: parserAvailable,
      version: null,
      bridge: "node-spawn-sync",
    },
  };
}

function boundedTimeout(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_TIMEOUT_MS;
  return Math.min(Math.trunc(parsed), 120000);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function normalizeEnvelope(parsed) {
  const errors = Array.isArray(parsed.errors) ? parsed.errors : [];
  const warnings = Array.isArray(parsed.warnings) ? parsed.warnings : [];
  const blocks = Array.isArray(parsed.blocks) ? parsed.blocks : [];
  const config = isObject(parsed.config) ? parsed.config : {};
  const provenance = isObject(parsed.provenance) ? parsed.provenance : {};
  const parser = isObject(parsed.parser) ? parsed.parser : {};

  return {
    schema_version: SCHEMA_VERSION,
    ok: errors.length === 0,
    read_only: true,
    writes_executed: false,
    config,
    provenance,
    blocks,
    errors,
    warnings,
    parser: {
      name: parser.name || "pyyaml",
      available: parser.available !== false,
      version: Object.prototype.hasOwnProperty.call(parser, "version")
        ? parser.version
        : null,
      bridge: "node-spawn-sync",
    },
  };
}

function parseDevLoopConfig(configPath, options = {}) {
  if (typeof configPath !== "string" || configPath.length === 0) {
    return failure("parser_input", "config path must be a non-empty string");
  }

  const pythonExecutable =
    options.pythonExecutable || process.env.DEV_LOOP_CONFIG_PYTHON || "python3";
  const parserPath =
    options.parserPath || path.join(__dirname, "dev-loop-config-schema.py");
  const timeoutMs = boundedTimeout(
    options.timeoutMs || process.env.DEV_LOOP_CONFIG_TIMEOUT_MS,
  );
  const result = spawnSync(
    pythonExecutable,
    [parserPath, "--file", configPath],
    {
      encoding: "utf8",
      env: { ...process.env, ...(options.env || {}) },
      maxBuffer: MAX_BUFFER_BYTES,
      timeout: timeoutMs,
    },
  );

  if (result.error) {
    if (result.error.code === "ETIMEDOUT") {
      return failure(
        "parser_timeout",
        `config parser exceeded ${timeoutMs}ms`,
        true,
      );
    }
    if (result.error.code === "ENOENT" || result.error.code === "EACCES") {
      return failure(
        "parser_unavailable",
        `Python config parser is unavailable: ${result.error.message}`,
      );
    }
    return failure(
      "parser_process",
      `config parser could not start: ${result.error.message}`,
    );
  }

  const stdout = (result.stdout || "").trim();
  if (!stdout) {
    const detail = (result.stderr || "").trim().slice(0, 2000);
    return failure(
      "parser_process",
      `config parser exited ${result.status}${detail ? `: ${detail}` : " with empty stdout"}`,
      true,
    );
  }

  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    return failure(
      "parser_output",
      `config parser returned invalid JSON: ${error.message}`,
      true,
    );
  }

  if (!isObject(parsed)) {
    return failure(
      "parser_output",
      "config parser returned a non-object JSON payload",
      true,
    );
  }

  return normalizeEnvelope(parsed);
}

module.exports = {
  DEFAULT_TIMEOUT_MS,
  SCHEMA_VERSION,
  parseDevLoopConfig,
};
