"use strict";

const WORKFLOW_PROFILES = Object.freeze(["native", "guided", "full"]);
const WORKFLOW_MODES = Object.freeze(["fixed", "adaptive"]);
const WORKFLOW_CAPABILITIES = Object.freeze(["self-directed", "needs-guidance", "unknown"]);
const WORKFLOW_RISKS = Object.freeze(["routine", "elevated"]);

const PIPELINE_STEPS = Object.freeze({
  full: Object.freeze(["spec", "plan", "execute", "review", "merge", "save"]),
  "tdd-first": Object.freeze(["plan", "execute", "review", "merge"]),
  "single-pass": Object.freeze(["execute", "review", "merge"]),
  "debug-only": Object.freeze(["execute", "merge"]),
  manual: Object.freeze([]),
});
const PRD_PIPELINES = Object.freeze(Object.keys(PIPELINE_STEPS));

const PROFILE_PIPELINES = Object.freeze({
  native: "single-pass",
  guided: "tdd-first",
  full: "full",
});

const LEGACY_PIPELINE_PROFILES = Object.freeze({
  full: "full",
  "tdd-first": "guided",
  "single-pass": "native",
  "debug-only": "native",
  manual: "native",
});

function normalized(value) {
  return typeof value === "string" ? value.trim() : "";
}

function hasPolicy(policy) {
  if (!policy || typeof policy !== "object") return false;
  return [policy.mode, policy.profile, policy.capability, policy.risk].some(
    (value) => normalized(value) !== "",
  );
}

function diagnostic(code, message, authority = null) {
  return { code, message, ...(authority ? { authority } : {}) };
}

function unresolvedResult(diagnostics, { authority = null, mode = null, sessionKind = "interactive" } = {}) {
  return {
    ok: false,
    profile: null,
    mode,
    authority,
    explicit: false,
    prompts: false,
    unresolved: true,
    reason: diagnostics[0]?.message || "workflow profile is unresolved",
    diagnostics,
    defaultPipeline: null,
    effectivePipeline: null,
    sessionKind,
  };
}

function resolvedResult({ profile, mode, authority, explicit, reason, sessionKind, effectivePipeline = null }) {
  const defaultPipeline = PROFILE_PIPELINES[profile];
  return {
    ok: true,
    profile,
    mode,
    authority,
    explicit,
    prompts: false,
    unresolved: false,
    reason,
    diagnostics: [],
    defaultPipeline,
    effectivePipeline: effectivePipeline || defaultPipeline,
    sessionKind,
  };
}

function validateValue(value, allowed, code, label, authority, diagnostics) {
  if (!value || allowed.includes(value)) return;
  diagnostics.push(
    diagnostic(code, `${label} must be one of: ${allowed.join(", ")}`, authority),
  );
}

function resolvePolicy(policy, authority, input, sessionKind) {
  const mode = normalized(policy.mode) || (normalized(policy.profile) ? "fixed" : "adaptive");
  const profile = normalized(policy.profile);
  const capability = normalized(policy.capability) || normalized(input.capabilityEvidence) || "unknown";
  const risk = normalized(policy.risk) || normalized(input.taskEvidence?.risk) || "routine";
  const diagnostics = [];

  validateValue(mode, WORKFLOW_MODES, "invalid_workflow_selection", "workflow_selection", authority, diagnostics);
  validateValue(profile, WORKFLOW_PROFILES, "invalid_workflow_profile", "workflow_profile", authority, diagnostics);
  validateValue(
    capability,
    WORKFLOW_CAPABILITIES,
    "invalid_workflow_capability",
    "workflow_capability",
    authority,
    diagnostics,
  );
  validateValue(risk, WORKFLOW_RISKS, "invalid_workflow_risk", "workflow_risk", authority, diagnostics);

  if (mode === "fixed" && !profile) {
    diagnostics.push(
      diagnostic(
        "workflow_fixed_profile_required",
        "workflow_selection fixed requires workflow_profile",
        authority,
      ),
    );
  }
  if (mode === "adaptive" && profile) {
    diagnostics.push(
      diagnostic(
        "workflow_adaptive_profile_conflict",
        "workflow_selection adaptive must not set workflow_profile; use fixed for an explicit profile",
        authority,
      ),
    );
  }
  if (diagnostics.length > 0) {
    return unresolvedResult(diagnostics, { authority, mode: WORKFLOW_MODES.includes(mode) ? mode : null, sessionKind });
  }

  if (mode === "fixed") {
    return resolvedResult({
      profile,
      mode,
      authority,
      explicit: true,
      reason: `${authority} explicitly selected the ${profile} workflow profile`,
      sessionKind,
    });
  }

  const resolvedProfile = capability === "needs-guidance" || risk === "elevated" ? "guided" : "native";
  return resolvedResult({
    profile: resolvedProfile,
    mode,
    authority,
    explicit: false,
    reason:
      resolvedProfile === "guided"
        ? `adaptive selection chose guided from capability=${capability}, risk=${risk}`
        : `adaptive selection chose native from capability=${capability}, risk=${risk}`,
    sessionKind,
  });
}

function resolveLegacyPolicy(legacy, sessionKind) {
  const prdPipeline = normalized(legacy?.prdPipeline);
  if (!prdPipeline) return null;
  const profile = LEGACY_PIPELINE_PROFILES[prdPipeline];
  if (!profile) {
    return unresolvedResult(
      [
        diagnostic(
          "invalid_legacy_prd_pipeline",
          `legacy prd_pipeline must be one of: ${Object.keys(LEGACY_PIPELINE_PROFILES).join(", ")}`,
          "project_legacy",
        ),
      ],
      { authority: "project_legacy", mode: "fixed", sessionKind },
    );
  }
  return resolvedResult({
    profile,
    mode: "fixed",
    authority: "project_legacy",
    explicit: true,
    reason: `legacy explicit prd_pipeline ${prdPipeline} maps to the ${profile} workflow profile`,
    effectivePipeline: prdPipeline,
    sessionKind,
  });
}

function withPipelineOverride(result, prdPipeline, sessionKind) {
  if (!result.ok || !prdPipeline) return result;
  if (!PRD_PIPELINES.includes(prdPipeline)) {
    return unresolvedResult(
      [
        diagnostic(
          "invalid_prd_pipeline",
          `prd_pipeline must be one of: ${PRD_PIPELINES.join(", ")}`,
          "project",
        ),
      ],
      { authority: result.authority, mode: result.mode, sessionKind },
    );
  }
  return { ...result, effectivePipeline: prdPipeline };
}

function pipelineSteps(pipeline) {
  return PIPELINE_STEPS[pipeline] ? [...PIPELINE_STEPS[pipeline]] : [];
}

function resolveWorkflowProfile(input = {}) {
  const sessionKind = normalized(input.sessionKind) || "interactive";
  const prdPipeline = normalized(input.legacy?.prdPipeline);
  if (Array.isArray(input.configurationErrors) && input.configurationErrors.length > 0) {
    return unresolvedResult(
      [
        diagnostic(
          "workflow_configuration_invalid",
          `workflow profile cannot resolve from invalid configuration (${input.configurationErrors.length} error(s))`,
          "project",
        ),
      ],
      { authority: "project", sessionKind },
    );
  }

  const authorities = input.authorities || {};
  for (const authority of ["user", "work_item", "project"]) {
    if (hasPolicy(authorities[authority])) {
      return withPipelineOverride(
        resolvePolicy(authorities[authority], authority, input, sessionKind),
        prdPipeline,
        sessionKind,
      );
    }
  }

  const legacy = resolveLegacyPolicy(input.legacy, sessionKind);
  if (legacy) return legacy;

  if (hasPolicy(authorities.user_default)) {
    return resolvePolicy(authorities.user_default, "user_default", input, sessionKind);
  }

  return resolvePolicy(
    {
      mode: "adaptive",
      capability: normalized(input.capabilityEvidence) || "unknown",
      risk: normalized(input.taskEvidence?.risk) || "routine",
    },
    "builtin_adaptive",
    input,
    sessionKind,
  );
}

function parseCliArgs(argv) {
  const options = { config: "", sessionKind: "interactive" };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    if (arg === "--config" || arg === "--session-kind") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        options.error = `${arg} requires a value`;
        break;
      }
      index += 1;
      if (arg === "--config") options.config = value;
      else options.sessionKind = value;
      continue;
    }
    options.error = `unknown option: ${arg}`;
    break;
  }
  return options;
}

function cliUsage() {
  return [
    "Usage: dev-loop-workflow-profile.js [--config <path>] [--session-kind <kind>]",
    "",
    "Prints one JSON workflow-resolution record. It performs no writes and never prompts.",
  ].join("\n");
}

function runCli(argv) {
  const options = parseCliArgs(argv);
  if (options.help) {
    process.stdout.write(`${cliUsage()}\n`);
    return 0;
  }
  if (options.error) {
    process.stderr.write(`${options.error}\n${cliUsage()}\n`);
    return 2;
  }

  let flat = {};
  let configurationErrors = [];
  if (options.config) {
    const { parseDevLoopConfig } = require("./dev-loop-config-schema.js");
    const parsed = parseDevLoopConfig(options.config);
    flat = parsed.config || {};
    configurationErrors = parsed.errors || [];
  }

  const workflowProfile = resolveWorkflowProfile({
    authorities: {
      project: {
        mode: flat.workflow_selection,
        profile: flat.workflow_profile,
        capability: flat.workflow_capability,
        risk: flat.workflow_risk,
      },
      user_default: {
        mode: process.env.DEV_LOOP_WORKFLOW_SELECTION,
        profile: process.env.DEV_LOOP_WORKFLOW_PROFILE,
        capability: process.env.DEV_LOOP_WORKFLOW_CAPABILITY,
        risk: process.env.DEV_LOOP_WORKFLOW_RISK,
      },
    },
    legacy: { prdPipeline: flat.prd_pipeline },
    configurationErrors,
    sessionKind: options.sessionKind,
  });

  process.stdout.write(
    `${JSON.stringify({
      schema_version: "dev-loop-workflow-profile.v1",
      read_only: true,
      config_path: options.config || null,
      workflow_profile: workflowProfile,
      prd_layer: flat.prd_layer || "manual",
      prd_pipeline: workflowProfile.effectivePipeline,
    })}\n`,
  );
  return 0;
}

module.exports = {
  PIPELINE_STEPS,
  PRD_PIPELINES,
  WORKFLOW_CAPABILITIES,
  WORKFLOW_MODES,
  WORKFLOW_PROFILES,
  WORKFLOW_RISKS,
  pipelineSteps,
  resolveWorkflowProfile,
};

if (require.main === module) {
  process.exitCode = runCli(process.argv.slice(2));
}
