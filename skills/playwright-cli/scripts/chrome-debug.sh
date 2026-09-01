#!/usr/bin/env bash
# chrome-debug-contract: v4
# Start Chrome with remote debugging in detached mode.
# Usage: ./scripts/chrome-debug.sh [--dry-run] [--print-config] [--json] [--check-port] [--explain] [--launch-and-explain] [--load-unpacked PATH] [URL]
#
# Profile default: default-user (global clone of real Chrome). Do not use
# --repo-local-profile unless isolation was requested explicitly.
# Linux headless: auto when DISPLAY is unset; override with CHROME_DEBUG_HEADLESS=0|1.
set -euo pipefail

DEBUG_PORT="${CHROME_DEBUG_PORT:-9222}"
DRY_RUN=0
PRINT_CONFIG=0
JSON_OUTPUT=0
CHECK_PORT_ONLY=0
EXPLAIN_ONLY=0
LAUNCH_AND_EXPLAIN=0
FORCE_RESTART=0
PROFILE_MODE="${CHROME_DEBUG_PROFILE_MODE:-default-user}"
PROFILE_DIRECTORY_NAME="${CHROME_DEBUG_PROFILE_DIRECTORY:-Default}"
REFRESH_FROM_DEFAULT="${CHROME_DEBUG_REFRESH_FROM_DEFAULT:-0}"
# empty = auto (Linux: headless when DISPLAY unset); 0 = force headed; 1 = force headless
HEADLESS_MODE="${CHROME_DEBUG_HEADLESS:-}"
TARGET_URL="${CHROME_DEBUG_URL:-about:blank}"
TARGET_URL_SET=0
COMMAND_NAME="${CHROME_DEBUG_COMMAND_NAME:-./scripts/chrome-debug.sh}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="${CHROME_DEBUG_PROJECT_ROOT:-$ROOT_DIR}"
LOG_FILE="${CHROME_DEBUG_LOG:-${ROOT_DIR}/logs/chrome-debug.log}"
PROFILE_DIR="${CHROME_DEBUG_PROFILE:-}"
PROFILE_MARKER=""
PROFILE_LABEL=""
PROFILE_SOURCE_DIR=""
CHROME_ARGS=()
LOAD_UNPACKED_CLI=()
LOAD_UNPACKED_PATHS=()

get_repo_local_profile_dir() {
  printf '%s\n' "${PROJECT_ROOT}/.chrome-debug-profile"
}

get_dedicated_profile_dir() {
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    printf '%s\n' "$HOME/Library/Application Support/Google/chrome-debug-profile"
    return 0
  fi

  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Google/chrome-debug-profile"
}

get_default_user_clone_dir() {
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    printf '%s\n' "$HOME/Library/Application Support/Google/chrome-debug-profile-from-default"
    return 0
  fi

  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Google/chrome-debug-profile-from-default"
}

log_info() {
  echo "[INFO] $*"
}

log_ok() {
  echo "[OK] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

print_usage() {
  cat <<EOF_USAGE
Usage: ${COMMAND_NAME} [--dry-run] [--print-config] [--json] [URL]

Options:
  --dry-run       Print the resolved launch configuration without starting Chrome
  --print-config  Print the resolved launch configuration before continuing
  --json          Emit the resolved launch configuration as JSON
  --check-port    Report whether the debug port is free or already in use
  --explain       Print a short diagnosis and suggested next action without launching Chrome
  --launch-and-explain
                   Print the diagnosis first, then continue with the normal launch flow
  --restart       Kill any existing Chrome debug instance + stale playwright-cli sessions, then launch fresh
  --default-user-profile
                   Clone the normal Chrome profile into a debug-safe user-data directory (default)
  --refresh-from-default
                   Re-sync the cloned default-user debug profile from your real Chrome profile before launch
  --repo-local-profile
                   Use ${PROJECT_ROOT}/.chrome-debug-profile (explicit isolation only; not the default)
  --dedicated-profile
                   Use the persistent cmux-only OS-native debug profile
  --profile-directory NAME
                   Pick a Chrome profile subdirectory (Default, Profile 1, etc.) when using
                   --default-user-profile
  --load-unpacked PATH
                   CDP Extensions.loadUnpacked PATH (repeatable). Re-applied on later
                   start/restart/reuse via ${PROFILE_DIR}/.chrome-debug-load-unpacked
  -h, --help      Show this help message

Environment:
  CHROME_DEBUG_PROFILE_MODE   default-user | repo-local | dedicated (default: default-user)
  CHROME_DEBUG_HEADLESS       empty=auto (Linux: headless when DISPLAY unset), 0=headed, 1=headless
  CHROME_DEBUG_PORT           remote debugging port (default: 9222)
  CHROME_DEBUG_PROFILE        override user-data-dir path
  CHROME_DEBUG_PROJECT_ROOT   project root used only by --repo-local-profile
  CHROME_DEBUG_LOG            launcher log path
  CHROME_DEBUG_COMMAND_NAME   command name shown in help and diagnostics
  CHROME_DEBUG_LOAD_UNPACKED  colon-separated extra unpacked extension paths
  CHROME                       Chrome/Chromium binary path
EOF_USAGE
}

# Returns 0 if Chrome should launch with --headless=new.
should_use_headless() {
  if [[ "${HEADLESS_MODE}" == "1" ]]; then
    return 0
  fi
  if [[ "${HEADLESS_MODE}" == "0" ]]; then
    return 1
  fi
  # Auto: never headless on macOS; on Linux/container headless when no DISPLAY.
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    return 1
  fi
  [[ -z "${DISPLAY:-}" ]]
}

resolve_headless_label() {
  if should_use_headless; then
    if [[ "${HEADLESS_MODE}" == "1" ]]; then
      printf '%s\n' "forced (CHROME_DEBUG_HEADLESS=1)"
    else
      printf '%s\n' "auto (no DISPLAY)"
    fi
  else
    if [[ "${HEADLESS_MODE}" == "0" ]]; then
      printf '%s\n' "forced headed (CHROME_DEBUG_HEADLESS=0)"
    elif [[ "${OSTYPE:-}" == "darwin"* ]]; then
      printf '%s\n' "headed (darwin)"
    else
      printf '%s\n' "headed (DISPLAY set)"
    fi
  fi
}

detect_chrome() {
  if [[ -n "${CHROME:-}" ]]; then
    if [[ -x "${CHROME}" ]]; then
      echo "${CHROME}"
      return 0
    fi
    if command -v "${CHROME}" >/dev/null 2>&1; then
      command -v "${CHROME}"
      return 0
    fi
  fi

  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    local mac_paths=(
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
      "/Applications/Chromium.app/Contents/MacOS/Chromium"
    )
    local p
    for p in "${mac_paths[@]}"; do
      if [[ -x "${p}" ]]; then
        echo "${p}"
        return 0
      fi
    done

    p="$(ls -d "$HOME"/.cache/puppeteer/chrome/*/chrome-mac-*/Google\ Chrome\ for\ Testing.app/Contents/MacOS/Google\ Chrome\ for\ Testing 2>/dev/null | head -n 1 || true)"
    if [[ -n "${p}" && -x "${p}" ]]; then
      echo "${p}"
      return 0
    fi
  else
    local chrome_cmd
    for chrome_cmd in \
      "chromium-browser" \
      "chromium" \
      "google-chrome-unstable" \
      "google-chrome-stable" \
      "google-chrome"; do
      if command -v "${chrome_cmd}" >/dev/null 2>&1; then
        command -v "${chrome_cmd}"
        return 0
      fi
    done
  fi

  return 1
}

resolve_default_user_data_dir() {
  local chrome_bin="$1"

  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    case "${chrome_bin}" in
      *"Google Chrome Canary"*)
        printf '%s\n' "$HOME/Library/Application Support/Google/Chrome Canary"
        ;;
      *"/Chromium")
        printf '%s\n' "$HOME/Library/Application Support/Chromium"
        ;;
      *)
        printf '%s\n' "$HOME/Library/Application Support/Google/Chrome"
        ;;
    esac
    return 0
  fi

  case "$(basename "${chrome_bin}")" in
    chromium|chromium-browser)
      printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/chromium"
      ;;
    *)
      printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/google-chrome"
      ;;
  esac
}

resolve_profile_config() {
  local chrome_bin="$1"

  if [[ -n "${CHROME_DEBUG_PROFILE:-}" ]]; then
    PROFILE_MODE="custom-path"
    PROFILE_DIR="${CHROME_DEBUG_PROFILE}"
    PROFILE_LABEL="custom profile path from CHROME_DEBUG_PROFILE"
    PROFILE_SOURCE_DIR=""
  else
    case "${PROFILE_MODE}" in
      default-user)
        PROFILE_SOURCE_DIR="$(resolve_default_user_data_dir "${chrome_bin}")"
        PROFILE_DIR="$(get_default_user_clone_dir)"
        PROFILE_LABEL="clone of Chrome user-data directory (${PROFILE_DIRECTORY_NAME})"
        ;;
      repo-local)
        PROFILE_DIR="$(get_repo_local_profile_dir)"
        PROFILE_LABEL="repo-local debug profile"
        PROFILE_SOURCE_DIR=""
        ;;
      dedicated)
        PROFILE_DIR="$(get_dedicated_profile_dir)"
        PROFILE_LABEL="cmux dedicated debug profile"
        PROFILE_SOURCE_DIR=""
        ;;
      *)
        log_error "Unknown profile mode: ${PROFILE_MODE}"
        exit 1
        ;;
    esac
  fi

  PROFILE_MARKER="--user-data-dir=${PROFILE_DIR}"
}

chrome_any_process_running() {
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    pgrep -ax "Google Chrome" >/dev/null 2>&1 || \
      pgrep -ax "Google Chrome Canary" >/dev/null 2>&1 || \
      pgrep -ax "Chromium" >/dev/null 2>&1
    return $?
  fi

  pgrep -x "google-chrome" >/dev/null 2>&1 || \
    pgrep -x "google-chrome-stable" >/dev/null 2>&1 || \
    pgrep -x "google-chrome-unstable" >/dev/null 2>&1 || \
    pgrep -x "chromium" >/dev/null 2>&1 || \
    pgrep -x "chromium-browser" >/dev/null 2>&1
}

profile_is_default_user_mode() {
  [[ "${PROFILE_MODE}" == "default-user" ]]
}

profile_supports_local_seeding() {
  [[ "${PROFILE_MODE}" != "default-user" ]]
}

profile_requires_clone_sync() {
  [[ "${PROFILE_MODE}" == "default-user" ]]
}

clone_sync_requested() {
  [[ "${REFRESH_FROM_DEFAULT}" == "1" ]]
}

default_clone_exists() {
  [[ -d "${PROFILE_DIR}/${PROFILE_DIRECTORY_NAME}" ]]
}

copy_path_if_present() {
  local source_path="$1"
  local target_path="$2"

  if [[ ! -e "${source_path}" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${target_path}")"
  cp -R "${source_path}" "${target_path}"
}

sync_default_user_profile() {
  local source_profile_dir target_profile_dir

  if [[ -z "${PROFILE_SOURCE_DIR}" ]]; then
    log_error "Default-user mode is missing the source Chrome profile directory."
    exit 1
  fi

  source_profile_dir="${PROFILE_SOURCE_DIR}/${PROFILE_DIRECTORY_NAME}"
  target_profile_dir="${PROFILE_DIR}/${PROFILE_DIRECTORY_NAME}"

  if [[ ! -d "${source_profile_dir}" ]]; then
    log_error "Chrome profile directory does not exist: ${source_profile_dir}"
    exit 1
  fi

  mkdir -p "${PROFILE_DIR}"
  log_info "Syncing Chrome profile ${PROFILE_DIRECTORY_NAME} from ${PROFILE_SOURCE_DIR} into ${PROFILE_DIR}."
  rm -rf "${target_profile_dir}"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='Cache/' \
      --exclude='Code Cache/' \
      --exclude='GPUCache/' \
      --exclude='GrShaderCache/' \
      --exclude='ShaderCache/' \
      --exclude='Crashpad/' \
      --exclude='Singleton*' \
      "${source_profile_dir}/" "${target_profile_dir}/"
  else
    cp -R "${source_profile_dir}" "${target_profile_dir}"
    rm -rf \
      "${target_profile_dir}/Cache" \
      "${target_profile_dir}/Code Cache" \
      "${target_profile_dir}/GPUCache" \
      "${target_profile_dir}/GrShaderCache" \
      "${target_profile_dir}/ShaderCache" \
      "${target_profile_dir}/Crashpad"
    rm -f \
      "${target_profile_dir}/SingletonLock" \
      "${target_profile_dir}/SingletonSocket" \
      "${target_profile_dir}/SingletonCookie"
  fi

  rm -f "${PROFILE_DIR}/Local State"
  copy_path_if_present "${PROFILE_SOURCE_DIR}/Local State" "${PROFILE_DIR}/Local State"
}

list_profile_pids() {
  ps -ax -o pid= -o command= | awk -v marker="$PROFILE_MARKER" 'index($0, marker) { print $1 }'
}

wait_for_profile_exit() {
  local attempts="${1:-20}"
  local delay_seconds="${2:-0.25}"
  local _
  for _ in $(seq 1 "$attempts"); do
    if [[ -z "$(list_profile_pids)" ]]; then
      return 0
    fi
    sleep "$delay_seconds"
  done

  return 1
}

stop_profile_processes() {
  local pids
  pids="$(list_profile_pids)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi

  log_info "Stopping existing Chrome instance for profile ${PROFILE_DIR}."
  echo "${pids}" | xargs kill 2>/dev/null || true

  if wait_for_profile_exit 20 0.25; then
    return 0
  fi

  pids="$(list_profile_pids)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi

  log_info "Chrome did not exit after SIGTERM; sending SIGKILL to profile-specific processes."
  echo "${pids}" | xargs kill -9 2>/dev/null || true
  wait_for_profile_exit 20 0.25 || true
}

cleanup_profile_locks() {
  rm -f \
    "${PROFILE_DIR}/SingletonLock" \
    "${PROFILE_DIR}/SingletonSocket" \
    "${PROFILE_DIR}/SingletonCookie"
}

seed_profile_preferences() {
  local default_dir preferences_file
  default_dir="${PROFILE_DIR}/Default"
  preferences_file="${default_dir}/Preferences"

  mkdir -p "${default_dir}"
  if [[ -f "${preferences_file}" ]]; then
    return 0
  fi

  cat > "${preferences_file}" <<'PREFERENCES_EOF'
{
  "session": {
    "restore_on_startup": 5
  },
  "profile": {
    "exit_type": "Normal"
  },
  "browser": {
    "has_seen_welcome_page": true
  }
}
PREFERENCES_EOF
}

port_is_healthy() {
  curl -fs "http://127.0.0.1:${DEBUG_PORT}/json/version" >/dev/null 2>&1
}

resolve_port_status() {
  if port_is_healthy; then
    if [[ -n "$(list_profile_pids)" ]]; then
      printf '%s\n' "owned_by_profile"
    else
      printf '%s\n' "occupied_by_other"
    fi
  else
    printf '%s\n' "free"
  fi
}

emit_port_status() {
  local port_status
  port_status="$(resolve_port_status)"

  if [[ "${JSON_OUTPUT}" == "1" ]]; then
    DEBUG_PORT_JSON="${DEBUG_PORT}" \
    PORT_STATUS_JSON="${port_status}" \
    PROFILE_DIR_JSON="${PROFILE_DIR}" \
    PROFILE_MODE_JSON="${PROFILE_MODE}" \
    python3 - <<'PY'
import json
import os

print(
    json.dumps(
        {
            "debugPort": int(os.environ["DEBUG_PORT_JSON"]),
            "status": os.environ["PORT_STATUS_JSON"],
            "profileDir": os.environ["PROFILE_DIR_JSON"],
            "profileMode": os.environ["PROFILE_MODE_JSON"],
        }
    )
)
PY
    return 0
  fi

  case "${port_status}" in
    free)
      log_ok "Port ${DEBUG_PORT} is free."
      ;;
    owned_by_profile)
      log_ok "Port ${DEBUG_PORT} is already serving DevTools for profile ${PROFILE_DIR}."
      ;;
    occupied_by_other)
      log_error "Port ${DEBUG_PORT} is serving DevTools for a different Chrome instance."
      ;;
  esac
}

emit_explanation() {
  local chrome_bin="$1"
  local port_status profile_exists preferences_exist next_action summary

  port_status="$(resolve_port_status)"
  if [[ -d "${PROFILE_DIR}" ]]; then
    profile_exists="yes"
  else
    profile_exists="no"
  fi

  if [[ -f "${PROFILE_DIR}/Default/Preferences" ]]; then
    preferences_exist="yes"
  else
    preferences_exist="no"
  fi

  case "${port_status}" in
    free)
      if profile_is_default_user_mode && chrome_any_process_running && (clone_sync_requested || ! default_clone_exists); then
        summary="Port ${DEBUG_PORT} is free, but Chrome is already running outside the script-managed debugger session."
        if clone_sync_requested; then
          next_action="Close Chrome first so the script can refresh your cloned Chrome profile, or rerun without --refresh-from-default to reuse the last clone."
        else
          next_action="Close the personal Chrome window so the script can create the initial default-user clone, then rerun ${COMMAND_NAME} (prefer reuse of an existing clone over --repo-local-profile)."
        fi
      else
        summary="Port ${DEBUG_PORT} is free; Chrome is not currently serving DevTools there."
        next_action="Run ${COMMAND_NAME} (default-user profile) to start the debug browser."
      fi
      ;;
    owned_by_profile)
      summary="Port ${DEBUG_PORT} is already owned by the configured ${PROFILE_LABEL}."
      next_action="Reuse the existing browser (playwright-cli attach), or run with --restart for a clean start of the same profile."
      ;;
    occupied_by_other)
      summary="Port ${DEBUG_PORT} is occupied by a different DevTools-enabled Chrome instance."
      next_action="Stop the other Chrome debugger or set CHROME_DEBUG_PORT to another port before launching this script."
      ;;
  esac

  if [[ "${JSON_OUTPUT}" == "1" ]]; then
    CHROME_BIN_JSON="${chrome_bin}" \
    DEBUG_PORT_JSON="${DEBUG_PORT}" \
    PROFILE_DIR_JSON="${PROFILE_DIR}" \
    PROFILE_SOURCE_DIR_JSON="${PROFILE_SOURCE_DIR}" \
    PROJECT_ROOT_JSON="${PROJECT_ROOT}" \
    PROFILE_MODE_JSON="${PROFILE_MODE}" \
    PORT_STATUS_JSON="${port_status}" \
    PROFILE_EXISTS_JSON="${profile_exists}" \
    PREFERENCES_EXIST_JSON="${preferences_exist}" \
    SUMMARY_JSON="${summary}" \
    NEXT_ACTION_JSON="${next_action}" \
    python3 - <<'PY'
import json
import os

print(
    json.dumps(
        {
            "chromeBin": os.environ["CHROME_BIN_JSON"],
            "debugPort": int(os.environ["DEBUG_PORT_JSON"]),
            "profileDir": os.environ["PROFILE_DIR_JSON"],
            "profileSourceDir": os.environ["PROFILE_SOURCE_DIR_JSON"],
            "projectRoot": os.environ["PROJECT_ROOT_JSON"],
            "profileMode": os.environ["PROFILE_MODE_JSON"],
            "portStatus": os.environ["PORT_STATUS_JSON"],
            "profileExists": os.environ["PROFILE_EXISTS_JSON"] == "yes",
            "preferencesExist": os.environ["PREFERENCES_EXIST_JSON"] == "yes",
            "summary": os.environ["SUMMARY_JSON"],
            "nextAction": os.environ["NEXT_ACTION_JSON"],
        }
    )
)
PY
    return 0
  fi

  cat <<EOF_EXPLAIN
Chrome binary : ${chrome_bin}
Debug port    : ${DEBUG_PORT}
Profile mode  : ${PROFILE_MODE}
Profile label : ${PROFILE_LABEL}
Profile source: ${PROFILE_SOURCE_DIR:-<none>}
Profile dir   : ${PROFILE_DIR}
Port status   : ${port_status}
Profile exists: ${profile_exists}
Prefs seeded  : ${preferences_exist}
Summary       : ${summary}
Next action   : ${next_action}
EOF_EXPLAIN
}

load_unpacked_sidecar_path() {
  printf '%s\n' "${PROFILE_DIR}/.chrome-debug-load-unpacked"
}

cdp_load_unpacked_helper_path() {
  printf '%s\n' "${SCRIPT_DIR}/cdp-load-unpacked.py"
}

path_list_has() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

validate_unpacked_dir() {
  local raw="$1"
  local resolved
  if [[ ! -d "${raw}" ]]; then
    log_error "Unpacked extension path does not exist: ${raw}"
    return 1
  fi
  resolved="$(cd "${raw}" && pwd)"
  if [[ ! -f "${resolved}/manifest.json" ]]; then
    log_error "Unpacked extension path has no manifest.json: ${resolved}"
    return 1
  fi
  printf '%s\n' "${resolved}"
}

collect_env_load_unpacked_raw() {
  local raw="${CHROME_DEBUG_LOAD_UNPACKED:-}"
  if [[ -z "${raw}" ]]; then
    return 0
  fi
  local IFS=':'
  # shellcheck disable=SC2086
  printf '%s\n' ${raw}
}

resolve_explicit_load_unpacked_paths() {
  LOAD_UNPACKED_PATHS=()
  local raw resolved
  if [[ ${#LOAD_UNPACKED_CLI[@]} -gt 0 ]]; then
    for raw in "${LOAD_UNPACKED_CLI[@]}"; do
      resolved="$(validate_unpacked_dir "${raw}")" || exit 1
      if [[ ${#LOAD_UNPACKED_PATHS[@]} -eq 0 ]] || ! path_list_has "${resolved}" "${LOAD_UNPACKED_PATHS[@]}"; then
        LOAD_UNPACKED_PATHS+=("${resolved}")
      fi
    done
  fi
  while IFS= read -r raw; do
    [[ -z "${raw}" ]] && continue
    resolved="$(validate_unpacked_dir "${raw}")" || exit 1
    if [[ ${#LOAD_UNPACKED_PATHS[@]} -eq 0 ]] || ! path_list_has "${resolved}" "${LOAD_UNPACKED_PATHS[@]}"; then
      LOAD_UNPACKED_PATHS+=("${resolved}")
    fi
  done < <(collect_env_load_unpacked_raw)
}

read_load_unpacked_sidecar() {
  local sidecar="$1"
  if [[ ! -f "${sidecar}" ]]; then
    return 0
  fi
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    printf '%s\n' "${line}"
  done < "${sidecar}"
}

write_load_unpacked_sidecar() {
  local sidecar="$1"
  shift
  local dir
  dir="$(dirname "${sidecar}")"
  mkdir -p "${dir}"
  if [[ $# -eq 0 ]]; then
    rm -f "${sidecar}"
    return 0
  fi
  printf '%s\n' "$@" > "${sidecar}"
}

apply_load_unpacked() {
  local sidecar helper raw resolved path output
  local -a merged=()
  sidecar="$(load_unpacked_sidecar_path)"
  helper="$(cdp_load_unpacked_helper_path)"

  if [[ ${#LOAD_UNPACKED_PATHS[@]} -gt 0 ]]; then
    for raw in "${LOAD_UNPACKED_PATHS[@]}"; do
      merged+=("${raw}")
    done
  fi
  while IFS= read -r raw; do
    [[ -z "${raw}" ]] && continue
    if [[ ! -d "${raw}" || ! -f "${raw}/manifest.json" ]]; then
      log_info "Skipping vanished unpacked path from sidecar: ${raw}"
      continue
    fi
    resolved="$(cd "${raw}" && pwd)"
    if [[ ${#merged[@]} -eq 0 ]] || ! path_list_has "${resolved}" "${merged[@]}"; then
      merged+=("${resolved}")
    fi
  done < <(read_load_unpacked_sidecar "${sidecar}")

  if [[ ${#merged[@]} -gt 0 ]]; then
    write_load_unpacked_sidecar "${sidecar}" "${merged[@]}"
  else
    write_load_unpacked_sidecar "${sidecar}"
    return 0
  fi

  if [[ ! -f "${helper}" ]]; then
    log_error "CDP load-unpacked helper is missing: ${helper}"
    log_error "Re-run playwright-cli setup so cdp-load-unpacked.py is installed beside chrome-debug.sh."
    return 1
  fi

  local -a helper_args=()
  helper_args=(--port "${DEBUG_PORT}" --reload-http --timeout-ms 20000 --retries 12 --retry-delay-ms 500)
  for path in "${merged[@]}"; do
    helper_args+=(--path "${path}")
    log_info "Loading unpacked extension: ${path}"
  done

  if ! output="$(python3 "${helper}" "${helper_args[@]}" 2>&1)"; then
    log_error "Extensions.loadUnpacked failed:"
    log_error "${output}"
    return 1
  fi
  log_ok "Unpacked extension(s) loaded via CDP."
  if [[ -n "${output}" ]]; then
    log_info "${output}"
  fi
}

build_chrome_args() {
  CHROME_ARGS=(
    --no-first-run
    --no-default-browser-check
    --remote-debugging-port="${DEBUG_PORT}"
    --remote-debugging-address=127.0.0.1
    --remote-allow-origins=*
    --enable-unsafe-extension-debugging
    --user-data-dir="${PROFILE_DIR}"
    --disable-session-crashed-bubble
    --disable-default-apps
    --disable-sync
    --disable-translate
    --disable-infobars
    --disable-features=ChromeWhatsNewUI,AutofillServerCommunication,AutomationControlled
    --start-maximized
    --window-position=0,0
    --window-size=1920,1080
    "${TARGET_URL}"
  )

  if profile_is_default_user_mode; then
    CHROME_ARGS=(
      --profile-directory="${PROFILE_DIRECTORY_NAME}"
      "${CHROME_ARGS[@]}"
    )
  fi

  if should_use_headless; then
    CHROME_ARGS=(
      --headless=new
      "${CHROME_ARGS[@]}"
    )
  fi

  # Linux / LXC / container: sandbox and shm defaults often fail without privileges.
  if [[ "${OSTYPE:-}" != "darwin"* ]]; then
    CHROME_ARGS=(
      --no-sandbox
      --disable-dev-shm-usage
      --disable-gpu
      --disable-software-rasterizer
      --password-store=basic
      "${CHROME_ARGS[@]}"
    )
  fi
}

print_config() {
  local chrome_bin="${1:-<unresolved>}"
  if [[ "${JSON_OUTPUT}" == "1" ]]; then
    local launch_args_payload
    launch_args_payload="$(printf '%s\x1f' "${CHROME_ARGS[@]}")"
    local load_unpacked_payload=""
    if [[ ${#LOAD_UNPACKED_PATHS[@]} -gt 0 ]]; then
      load_unpacked_payload="$(printf '%s\x1f' "${LOAD_UNPACKED_PATHS[@]}")"
    fi
    CHROME_BIN_JSON="${chrome_bin}" \
    DEBUG_PORT_JSON="${DEBUG_PORT}" \
    PROFILE_DIR_JSON="${PROFILE_DIR}" \
    PROFILE_MODE_JSON="${PROFILE_MODE}" \
    PROFILE_DIRECTORY_JSON="${PROFILE_DIRECTORY_NAME}" \
    PROFILE_SOURCE_DIR_JSON="${PROFILE_SOURCE_DIR}" \
    PROJECT_ROOT_JSON="${PROJECT_ROOT}" \
    REFRESH_FROM_DEFAULT_JSON="${REFRESH_FROM_DEFAULT}" \
    HEADLESS_JSON="$(should_use_headless && echo true || echo false)" \
    HEADLESS_LABEL_JSON="$(resolve_headless_label)" \
    LOG_FILE_JSON="${LOG_FILE}" \
    TARGET_URL_JSON="${TARGET_URL}" \
    LAUNCH_ARGS_JSON_SOURCE="${launch_args_payload}" \
    LOAD_UNPACKED_JSON_SOURCE="${load_unpacked_payload}" \
    python3 - <<'PY'
import json
import os

launch_args = [
    arg for arg in os.environ["LAUNCH_ARGS_JSON_SOURCE"].split("\x1f") if arg
]
print(
    json.dumps(
        {
            "chromeBin": os.environ["CHROME_BIN_JSON"],
            "debugPort": int(os.environ["DEBUG_PORT_JSON"]),
            "profileDir": os.environ["PROFILE_DIR_JSON"],
            "profileMode": os.environ["PROFILE_MODE_JSON"],
            "profileDirectory": os.environ["PROFILE_DIRECTORY_JSON"],
            "profileSourceDir": os.environ["PROFILE_SOURCE_DIR_JSON"],
            "projectRoot": os.environ["PROJECT_ROOT_JSON"],
            "refreshFromDefault": os.environ["REFRESH_FROM_DEFAULT_JSON"] == "1",
            "headless": os.environ["HEADLESS_JSON"] == "true",
            "headlessLabel": os.environ["HEADLESS_LABEL_JSON"],
            "logFile": os.environ["LOG_FILE_JSON"],
            "targetUrl": os.environ["TARGET_URL_JSON"],
            "launchArgs": launch_args,
            "loadUnpackedPaths": [
                path for path in os.environ.get("LOAD_UNPACKED_JSON_SOURCE", "").split("\x1f") if path
            ],
            "chromeDebugContract": "v4",
        }
    )
)
PY
    return 0
  fi

  cat <<EOF_CONFIG
CHROME_BIN=${chrome_bin}
DEBUG_PORT=${DEBUG_PORT}
PROFILE_MODE=${PROFILE_MODE}
PROFILE_LABEL=${PROFILE_LABEL}
PROFILE_DIRECTORY_NAME=${PROFILE_DIRECTORY_NAME}
PROFILE_SOURCE_DIR=${PROFILE_SOURCE_DIR}
REFRESH_FROM_DEFAULT=${REFRESH_FROM_DEFAULT}
HEADLESS=$(should_use_headless && echo yes || echo no)
HEADLESS_LABEL=$(resolve_headless_label)
PROFILE_DIR=${PROFILE_DIR}
LOG_FILE=${LOG_FILE}
TARGET_URL=${TARGET_URL}
LOAD_UNPACKED_PATHS=$(printf '%s ' "${LOAD_UNPACKED_PATHS[@]+"${LOAD_UNPACKED_PATHS[@]}"}")
CHROME_DEBUG_CONTRACT=v4
EOF_CONFIG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --print-config)
      PRINT_CONFIG=1
      ;;
    --json)
      JSON_OUTPUT=1
      ;;
    --check-port)
      CHECK_PORT_ONLY=1
      ;;
    --explain)
      EXPLAIN_ONLY=1
      ;;
    --launch-and-explain)
      LAUNCH_AND_EXPLAIN=1
      ;;
    --restart)
      FORCE_RESTART=1
      ;;
    --default-user-profile)
      PROFILE_MODE="default-user"
      ;;
    --refresh-from-default)
      REFRESH_FROM_DEFAULT=1
      ;;
    --repo-local-profile)
      PROFILE_MODE="repo-local"
      ;;
    --dedicated-profile)
      PROFILE_MODE="dedicated"
      ;;
    --profile-directory)
      shift
      if [[ $# -eq 0 ]]; then
        log_error "--profile-directory requires a value."
        exit 1
      fi
      PROFILE_DIRECTORY_NAME="$1"
      ;;
    --load-unpacked)
      shift
      if [[ $# -eq 0 ]]; then
        log_error "--load-unpacked requires a path."
        exit 1
      fi
      LOAD_UNPACKED_CLI+=("$1")
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      if [[ $# -gt 0 ]]; then
        TARGET_URL="$1"
        shift
      fi
      if [[ $# -gt 0 ]]; then
        log_error "Unexpected extra arguments: $*"
        print_usage
        exit 1
      fi
      break
      ;;
    -*)
      log_error "Unknown option: $1"
      print_usage
      exit 1
      ;;
    *)
      if [[ "${TARGET_URL_SET}" == "1" ]]; then
        log_error "Unexpected extra argument: $1"
        print_usage
        exit 1
      fi
      TARGET_URL="$1"
      TARGET_URL_SET=1
      ;;
  esac
  shift
done

CHROME_BIN="$(detect_chrome || true)"
if [[ -z "${CHROME_BIN}" || ! -x "${CHROME_BIN}" ]]; then
  log_error "Chrome/Chromium binary not found."
  log_error "Set CHROME to a valid binary path if it is installed in a custom location."
  exit 1
fi

resolve_profile_config "${CHROME_BIN}"
build_chrome_args
resolve_explicit_load_unpacked_paths

if [[ "${CHECK_PORT_ONLY}" == "1" ]]; then
  emit_port_status
  exit 0
fi

if [[ "${EXPLAIN_ONLY}" == "1" ]]; then
  emit_explanation "${CHROME_BIN}"
  exit 0
fi

if [[ "${LAUNCH_AND_EXPLAIN}" == "1" ]]; then
  emit_explanation "${CHROME_BIN}"
fi

if [[ "${PRINT_CONFIG}" == "1" || "${DRY_RUN}" == "1" ]]; then
  print_config "${CHROME_BIN}"
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  if [[ "${JSON_OUTPUT}" != "1" ]]; then
    log_ok "Dry-run only; Chrome was not started."
  fi
  exit 0
fi

if [[ "${FORCE_RESTART}" == "1" ]] && port_is_healthy; then
  log_info "Restart requested — killing existing Chrome debug instance and stale playwright-cli sessions."
  if command -v playwright-cli >/dev/null 2>&1; then
    playwright-cli kill-all 2>/dev/null || true
  fi
  # Kill the exact process holding port 9222 (more reliable than pgrep by profile marker)
  port_pid="$(lsof -ti "tcp:${DEBUG_PORT}" 2>/dev/null || true)"
  if [[ -n "${port_pid}" ]]; then
    log_info "Killing process ${port_pid} holding port ${DEBUG_PORT}."
    kill "${port_pid}" 2>/dev/null || true
    sleep 1
    port_pid="$(lsof -ti "tcp:${DEBUG_PORT}" 2>/dev/null || true)"
    if [[ -n "${port_pid}" ]]; then
      log_info "Process still alive; sending SIGKILL."
      kill -9 "${port_pid}" 2>/dev/null || true
    fi
  fi
  stop_profile_processes
  cleanup_profile_locks
  log_info "Waiting for port ${DEBUG_PORT} to be free."
  for _ in {1..40}; do
    if ! port_is_healthy; then
      log_ok "Port ${DEBUG_PORT} is free."
      break
    fi
    sleep 0.5
  done
  if port_is_healthy; then
    log_error "Chrome did not release port ${DEBUG_PORT} after restart request."
    log_error "Close Chrome manually and rerun."
    exit 1
  fi
  log_ok "Previous instance stopped."
fi

if port_is_healthy; then
  if [[ -n "$(list_profile_pids)" ]]; then
    log_ok "Found existing debug Chrome instance on port ${DEBUG_PORT}; reusing profile ${PROFILE_DIR}."
    apply_load_unpacked
    exit 0
  fi

  log_error "Port ${DEBUG_PORT} is already serving DevTools for a different Chrome instance."
  log_error "Stop the other debugger Chrome or set CHROME_DEBUG_PORT to a different port."
  exit 1
fi

if profile_is_default_user_mode && chrome_any_process_running && (clone_sync_requested || ! default_clone_exists); then
  if clone_sync_requested; then
    log_error "Chrome is already running, so the script cannot safely refresh the cloned Chrome profile for remote debugging."
    log_error "Close Chrome first, or rerun without --refresh-from-default to reuse the last cloned profile."
  else
    log_error "Chrome is already running, so the script cannot create the initial cloned Chrome profile for remote debugging."
    log_error "Close Chrome first, then rerun to create the default-user clone."
    log_error "If a previous clone already exists, rerun without --refresh-from-default to reuse it."
    log_error "Only use --repo-local-profile when you explicitly need an empty isolated profile."
  fi
  exit 1
fi

mkdir -p "$(dirname "${LOG_FILE}")" "${PROFILE_DIR}"
if profile_requires_clone_sync; then
  stop_profile_processes
  cleanup_profile_locks
fi
SAVED_SIDECAR_PATHS=()
if clone_sync_requested; then
  while IFS= read -r _sidecar_line; do
    [[ -z "${_sidecar_line}" ]] && continue
    SAVED_SIDECAR_PATHS+=("${_sidecar_line}")
  done < <(read_load_unpacked_sidecar "$(load_unpacked_sidecar_path)")
fi
if profile_requires_clone_sync && (clone_sync_requested || ! default_clone_exists); then
  sync_default_user_profile
fi
if clone_sync_requested && [[ ${#SAVED_SIDECAR_PATHS[@]} -gt 0 ]]; then
  write_load_unpacked_sidecar "$(load_unpacked_sidecar_path)" "${SAVED_SIDECAR_PATHS[@]}"
fi
if profile_supports_local_seeding; then
  stop_profile_processes
  cleanup_profile_locks
  seed_profile_preferences
fi

log_info "Starting Chrome in detached mode."
log_info "Chrome: ${CHROME_BIN}"
log_info "Port: ${DEBUG_PORT}"
log_info "Profile mode: ${PROFILE_MODE}"
log_info "Profile label: ${PROFILE_LABEL}"
if [[ -n "${PROFILE_SOURCE_DIR}" ]]; then
  log_info "Profile source: ${PROFILE_SOURCE_DIR}"
fi
log_info "Profile: ${PROFILE_DIR}"
log_info "Headless: $(resolve_headless_label)"
log_info "URL: ${TARGET_URL}"
log_info "Log file: ${LOG_FILE}"

# Detach Chrome into its own session/process-group so it survives the
# short-lived Bash tool shell that agents invoke this script from.
#
# - setsid (Linux): the obvious choice, but it is absent on stock macOS.
# - macOS: Python3's os.setsid() creates a new session exactly like setsid.
#   python3 is already a hard dependency of this script (JSON output), so this
#   adds no new dependency. nohup alone is NOT enough on macOS: it only
#   ignores SIGHUP, so Chrome stays in the Bash tool's process group and gets
#   SIGTERM/SIGKILL when that group is torn down -> crash. A new session
#   fully detaches Chrome.
if command -v setsid >/dev/null 2>&1; then
  setsid nohup "${CHROME_BIN}" "${CHROME_ARGS[@]}" < /dev/null > "${LOG_FILE}" 2>&1 &
elif command -v python3 >/dev/null 2>&1; then
  CHROME_BIN_DETACH="${CHROME_BIN}" \
  CHROME_ARGS_DETACH="$(printf '%s\x1f' "${CHROME_ARGS[@]}")" \
  python3 - <<'PY' > "${LOG_FILE}" 2>&1 &
import os

binary = os.environ["CHROME_BIN_DETACH"]
# Drop the trailing \x1f so the split yields exactly CHROME_ARGS.
args_raw = os.environ.get("CHROME_ARGS_DETACH", "")
argv = [a for a in args_raw.split("\x1f") if a]

os.setsid()  # new session + new process group (equivalent to `setsid`)

# Give Chrome /dev/null on stdin so it never blocks on terminal input.
devnull_fd = os.open(os.devnull, os.O_RDONLY)
os.dup2(devnull_fd, 0)
os.close(devnull_fd)

os.execvp(binary, [binary, *argv])
PY
else
  nohup "${CHROME_BIN}" "${CHROME_ARGS[@]}" < /dev/null > "${LOG_FILE}" 2>&1 &
fi

printf '[INFO] Waiting for debugger on port %s' "${DEBUG_PORT}"
for _ in {1..60}; do
  if port_is_healthy; then
    sleep 1
    if port_is_healthy; then
      echo
      log_ok "Chrome is listening on port ${DEBUG_PORT}."
      # Chrome 152 can rotate the browser websocket during startup; wait and
      # let the helper retry against a fresh /json/version each attempt.
      sleep 2
      apply_load_unpacked
      exit 0
    fi
  fi
  printf '.'
  sleep 0.5
done

echo
log_error "Chrome started but port ${DEBUG_PORT} is not responsive."
log_error "Check logs at ${LOG_FILE}"
exit 1
