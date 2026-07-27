#!/usr/bin/env bash
# Install the user-level chrome-debug launcher and initialize playwright-cli.
set -euo pipefail

MIN_CLI_VERSION="0.1.17"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_LAUNCHER="${SCRIPT_DIR}/chrome-debug.sh"
SOURCE_CONFIG="$(dirname "${SCRIPT_DIR}")/.playwright/cli.config.json"

PROJECT_DIR="${PWD}"
BIN_DIR="${XDG_BIN_HOME:-${HOME}/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/playwright-cli"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/playwright-cli"
INSTALL_CLI=1
UPGRADE_CLI=0
INSTALL_LAUNCHER=1
INIT_PROJECT_CONFIG=1
FORCE_LAUNCHER=0
FORCE_PROJECT_CONFIG=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: setup-playwright-cli.sh [options]

Install or verify @playwright/cli, install a user-level `chrome-debug`
command, and initialize .playwright/cli.config.json in a project.

Options:
  --project DIR              Project to initialize (default: current directory)
  --bin-dir DIR              Launcher directory (default: ~/.local/bin)
  --data-dir DIR             Stable launcher data directory
  --state-dir DIR            Launcher log/state directory
  --skip-cli                 Do not install or verify @playwright/cli
  --upgrade-cli              Install @playwright/cli@latest even when current is sufficient
  --skip-launcher            Do not install the chrome-debug command
  --skip-project-config      Do not initialize .playwright/cli.config.json
  --force-launcher           Replace an existing unmanaged command at the target path
  --force-project-config     Replace a config that does not already target CDP port 9222
  --dry-run                  Show planned actions without writing or installing
  -h, --help                 Show this help

The script never uses sudo. If npm's global prefix is not writable, configure
a user-owned npm prefix and rerun.
EOF
}

require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "${value}" || "${value}" == -* ]]; then
    printf 'setup-playwright-cli: %s requires a value\n' "${flag}" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      require_value "$1" "${2:-}"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --bin-dir)
      require_value "$1" "${2:-}"
      BIN_DIR="$2"
      shift 2
      ;;
    --data-dir)
      require_value "$1" "${2:-}"
      DATA_DIR="$2"
      shift 2
      ;;
    --state-dir)
      require_value "$1" "${2:-}"
      STATE_DIR="$2"
      shift 2
      ;;
    --skip-cli)
      INSTALL_CLI=0
      shift
      ;;
    --upgrade-cli)
      UPGRADE_CLI=1
      shift
      ;;
    --skip-launcher)
      INSTALL_LAUNCHER=0
      shift
      ;;
    --skip-project-config)
      INIT_PROJECT_CONFIG=0
      shift
      ;;
    --force-launcher)
      FORCE_LAUNCHER=1
      shift
      ;;
    --force-project-config)
      FORCE_PROJECT_CONFIG=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'setup-playwright-cli: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "${PROJECT_DIR}" ]]; then
  printf 'setup-playwright-cli: project directory does not exist: %s\n' "${PROJECT_DIR}" >&2
  exit 1
fi
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

if [[ ! -f "${SOURCE_LAUNCHER}" ]]; then
  printf 'setup-playwright-cli: bundled launcher is missing: %s\n' "${SOURCE_LAUNCHER}" >&2
  exit 1
fi
if [[ ! -f "${SOURCE_CONFIG}" ]]; then
  printf 'setup-playwright-cli: bundled config template is missing: %s\n' "${SOURCE_CONFIG}" >&2
  exit 1
fi

TARGET_LAUNCHER="${DATA_DIR}/chrome-debug.sh"
TARGET_COMMAND="${BIN_DIR}/chrome-debug"
TARGET_CONFIG="${PROJECT_DIR}/.playwright/cli.config.json"
MANAGED_MARKER="# playwright-cli-managed-chrome-debug: v1"

version_at_least() {
  local actual="$1"
  local minimum="$2"
  awk -v actual="${actual}" -v minimum="${minimum}" 'BEGIN {
    split(actual, a, "."); split(minimum, m, ".");
    for (i = 1; i <= 3; i++) {
      av = a[i] + 0; mv = m[i] + 0;
      if (av > mv) exit 0;
      if (av < mv) exit 1;
    }
    exit 0;
  }'
}

current_cli_version() {
  playwright-cli --version 2>/dev/null | awk '{print $NF}' | head -n 1
}

config_targets_default_cdp() {
  local config="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${config}" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(1)

endpoint = data.get("browser", {}).get("cdpEndpoint")
raise SystemExit(0 if endpoint == "http://localhost:9222" else 1)
PY
    return $?
  fi

  if command -v node >/dev/null 2>&1; then
    node - "${config}" <<'JS'
const fs = require("fs");

try {
  const data = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
  process.exit(data?.browser?.cdpEndpoint === "http://localhost:9222" ? 0 : 1);
} catch {
  process.exit(1);
}
JS
    return $?
  fi

  printf 'setup-playwright-cli: python3 or node is required to inspect existing JSON config\n' >&2
  return 1
}

preflight_launcher() {
  if [[ "${INSTALL_LAUNCHER}" != "1" || ! -e "${TARGET_COMMAND}" ]]; then
    return 0
  fi
  if grep -Fq "${MANAGED_MARKER}" "${TARGET_COMMAND}" 2>/dev/null; then
    return 0
  fi
  if [[ "${FORCE_LAUNCHER}" == "1" ]]; then
    return 0
  fi
  printf 'setup-playwright-cli: refusing to replace unmanaged command: %s\n' "${TARGET_COMMAND}" >&2
  printf 'Rerun with --force-launcher only after reviewing that file.\n' >&2
  exit 1
}

preflight_project_config() {
  if [[ "${INIT_PROJECT_CONFIG}" != "1" || ! -e "${TARGET_CONFIG}" ]]; then
    return 0
  fi
  if config_targets_default_cdp "${TARGET_CONFIG}"; then
    return 0
  fi
  if [[ "${FORCE_PROJECT_CONFIG}" == "1" ]]; then
    return 0
  fi
  printf 'setup-playwright-cli: existing config does not target http://localhost:9222: %s\n' "${TARGET_CONFIG}" >&2
  printf 'Merge cdpEndpoint manually or rerun with --force-project-config.\n' >&2
  exit 1
}

ensure_cli() {
  local installed=""
  if [[ "${INSTALL_CLI}" != "1" ]]; then
    printf '[SKIP] @playwright/cli installation disabled\n'
    return 0
  fi

  if command -v playwright-cli >/dev/null 2>&1; then
    installed="$(current_cli_version)"
  fi

  if [[ "${UPGRADE_CLI}" != "1" && -n "${installed}" ]] && version_at_least "${installed}" "${MIN_CLI_VERSION}"; then
    printf '[OK] playwright-cli %s satisfies >= %s\n' "${installed}" "${MIN_CLI_VERSION}"
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    printf 'setup-playwright-cli: npm is required to install @playwright/cli\n' >&2
    exit 1
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[DRY-RUN] npm install --global @playwright/cli@latest\n'
    return 0
  fi

  printf '[RUN] Installing @playwright/cli@latest with npm (no sudo)\n'
  npm install --global @playwright/cli@latest
  installed="$(current_cli_version)"
  if [[ -z "${installed}" ]] || ! version_at_least "${installed}" "${MIN_CLI_VERSION}"; then
    printf 'setup-playwright-cli: installed CLI is missing or older than %s\n' "${MIN_CLI_VERSION}" >&2
    exit 1
  fi
  printf '[OK] playwright-cli %s installed\n' "${installed}"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

install_launcher() {
  local backup launcher_quote state_quote tmp_wrapper
  if [[ "${INSTALL_LAUNCHER}" != "1" ]]; then
    printf '[SKIP] chrome-debug launcher installation disabled\n'
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[DRY-RUN] install launcher payload: %s\n' "${TARGET_LAUNCHER}"
    printf '[DRY-RUN] install command: %s\n' "${TARGET_COMMAND}"
    return 0
  fi

  mkdir -p "${DATA_DIR}" "${BIN_DIR}" "${STATE_DIR}"
  if [[ -e "${TARGET_COMMAND}" ]] && ! grep -Fq "${MANAGED_MARKER}" "${TARGET_COMMAND}" 2>/dev/null; then
    backup="${TARGET_COMMAND}.bak.$(date -u +%Y%m%dT%H%M%SZ)-$$"
    cp -p "${TARGET_COMMAND}" "${backup}"
    printf '[OK] backed up unmanaged command: %s\n' "${backup}"
  fi
  install -m 0755 "${SOURCE_LAUNCHER}" "${TARGET_LAUNCHER}"

  launcher_quote="$(shell_quote "${TARGET_LAUNCHER}")"
  state_quote="$(shell_quote "${STATE_DIR}")"
  tmp_wrapper="$(mktemp "${BIN_DIR}/.chrome-debug.XXXXXX")"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "${MANAGED_MARKER}"
    printf '%s\n' 'set -euo pipefail'
    printf 'LAUNCHER=%s\n' "${launcher_quote}"
    printf 'STATE_DIR=%s\n' "${state_quote}"
    # These expressions are intentionally written literally into the wrapper.
    # shellcheck disable=SC2016
    printf '%s\n' 'export CHROME_DEBUG_PROJECT_ROOT="${CHROME_DEBUG_PROJECT_ROOT:-$PWD}"'
    # shellcheck disable=SC2016
    printf '%s\n' 'export CHROME_DEBUG_LOG="${CHROME_DEBUG_LOG:-${STATE_DIR}/chrome-debug.log}"'
    # shellcheck disable=SC2016
    printf '%s\n' 'export CHROME_DEBUG_COMMAND_NAME="${CHROME_DEBUG_COMMAND_NAME:-chrome-debug}"'
    # shellcheck disable=SC2016
    printf '%s\n' 'exec bash "${LAUNCHER}" "$@"'
  } > "${tmp_wrapper}"
  chmod 0755 "${tmp_wrapper}"
  mv "${tmp_wrapper}" "${TARGET_COMMAND}"
  printf '[OK] installed chrome-debug command: %s\n' "${TARGET_COMMAND}"
}

initialize_project_config() {
  local backup config_dir tmp_config
  if [[ "${INIT_PROJECT_CONFIG}" != "1" ]]; then
    printf '[SKIP] project config initialization disabled\n'
    return 0
  fi

  if [[ -e "${TARGET_CONFIG}" ]] && config_targets_default_cdp "${TARGET_CONFIG}"; then
    printf '[OK] existing project config already targets CDP 9222: %s\n' "${TARGET_CONFIG}"
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[DRY-RUN] initialize project config: %s\n' "${TARGET_CONFIG}"
    return 0
  fi

  config_dir="$(dirname "${TARGET_CONFIG}")"
  mkdir -p "${config_dir}"
  if [[ -e "${TARGET_CONFIG}" ]]; then
    backup="${TARGET_CONFIG}.bak.$(date -u +%Y%m%dT%H%M%SZ)-$$"
    cp -p "${TARGET_CONFIG}" "${backup}"
    printf '[OK] backed up divergent project config: %s\n' "${backup}"
  fi
  tmp_config="$(mktemp "${config_dir}/.cli.config.json.XXXXXX")"
  install -m 0644 "${SOURCE_CONFIG}" "${tmp_config}"
  mv "${tmp_config}" "${TARGET_CONFIG}"
  printf '[OK] initialized project config: %s\n' "${TARGET_CONFIG}"
}

preflight_launcher
preflight_project_config

printf 'Playwright CLI setup\n'
printf '  project : %s\n' "${PROJECT_DIR}"
printf '  command : %s\n' "${TARGET_COMMAND}"
printf '  payload : %s\n' "${TARGET_LAUNCHER}"
printf '  config  : %s\n' "${TARGET_CONFIG}"

ensure_cli
install_launcher
initialize_project_config

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *)
    printf '[WARN] %s is not currently on PATH; add it to your shell profile.\n' "${BIN_DIR}"
    ;;
esac

resolved_command="$(command -v chrome-debug 2>/dev/null || true)"
if [[ -n "${resolved_command}" && "${resolved_command}" != "${TARGET_COMMAND}" ]]; then
  printf '[WARN] chrome-debug currently resolves to %s instead of %s.\n' "${resolved_command}" "${TARGET_COMMAND}"
fi

printf '\nNext:\n'
printf '  chrome-debug\n'
printf '  playwright-cli attach\n'
printf '  playwright-cli snapshot\n'
