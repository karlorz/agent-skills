#!/usr/bin/env bash
set -euo pipefail

print_help() {
  cat <<'EOF'
install-codex-home-hooks.sh

Install or refresh the managed Codex home Stop and SessionStart hooks bundled
with the autopilot skill. The installer copies all required hook assets into
`~/.codex` so the managed home hooks remain self-contained after installation.

Usage:
  scripts/install-codex-home-hooks.sh [--home /absolute/path]
EOF
}

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

HOME_DIR="${HOME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home)
      HOME_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HOME_DIR" ]]; then
  echo "HOME is not set and --home was not provided" >&2
  exit 1
fi

require_command jq

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_ROOT="${SKILL_ROOT}/assets/codex-home"
CODEX_DIR="${HOME_DIR}/.codex"
HOOKS_DIR="${CODEX_DIR}/hooks"
HOOKS_FILE="${CODEX_DIR}/hooks.json"
CONFIG_FILE="${CODEX_DIR}/config.toml"
AUTOPILOT_DIR="${CODEX_DIR}/autopilot"
AUTOPILOT_HOOKS_DIR="${AUTOPILOT_DIR}/hooks"
AUTOPILOT_RESET_DIR="${CODEX_DIR}/skills/autopilot_reset"

mkdir -p "$HOOKS_DIR" "$AUTOPILOT_HOOKS_DIR" "$AUTOPILOT_RESET_DIR"

install_script() {
  local source_path="$1"
  local target_path="$2"

  cp "$source_path" "$target_path"
  chmod 755 "$target_path"
}

install_data_file() {
  local source_path="$1"
  local target_path="$2"

  cp "$source_path" "$target_path"
}

install_asset_script() {
  local relative_path="$1"
  local target_path="$2"

  install_script "${ASSETS_ROOT}/${relative_path}" "$target_path"
}

install_asset_file() {
  local relative_path="$1"
  local target_path="$2"

  install_data_file "${ASSETS_ROOT}/${relative_path}" "$target_path"
}

install_asset_script "hooks/cmux-stop-dispatch.sh" "${HOOKS_DIR}/cmux-stop-dispatch.sh"
install_asset_script "hooks/managed-session-start.sh" "${HOOKS_DIR}/managed-session-start.sh"
install_asset_script "hooks/home-autopilot-stop.sh" "${HOOKS_DIR}/autopilot-stop.sh"
install_asset_script "hooks/home-session-start.sh" "${HOOKS_DIR}/session-start.sh"
install_asset_script "lib/autopilot-reset.sh" "${AUTOPILOT_DIR}/autopilot-reset.sh"
install_asset_script "lib/hooks/cmux-autopilot-stop-core.sh" "${AUTOPILOT_HOOKS_DIR}/cmux-autopilot-stop-core.sh"
install_asset_script "lib/hooks/cmux-session-start-core.sh" "${AUTOPILOT_HOOKS_DIR}/cmux-session-start-core.sh"
install_asset_file "skills/autopilot_reset/SKILL.md" "${AUTOPILOT_RESET_DIR}/SKILL.md"

cat >"$HOOKS_FILE" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "sh -c 'exec \"$HOME/.codex/hooks/managed-session-start.sh\"'",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh -c 'exec \"$HOME/.codex/hooks/cmux-stop-dispatch.sh\"'",
            "timeout": 75
          }
        ]
      }
    ]
  }
}
EOF

tmp_config="$(mktemp)"
if [[ -f "$CONFIG_FILE" ]]; then
  cp "$CONFIG_FILE" "$tmp_config"
else
  : >"$tmp_config"
fi

awk '
  BEGIN {
    in_features = 0
    saw_features = 0
    wrote_codex_hooks = 0
    total_lines = 0
  }
  {
    total_lines += 1
  }
  /^\[features\][[:space:]]*$/ {
    if (in_features && !wrote_codex_hooks) {
      print "codex_hooks = true"
      wrote_codex_hooks = 1
    }
    saw_features = 1
    in_features = 1
    print
    next
  }
  in_features && /^\[/ {
    if (!wrote_codex_hooks) {
      print "codex_hooks = true"
      wrote_codex_hooks = 1
    }
    in_features = 0
  }
  in_features && /^[[:space:]]*codex_hooks[[:space:]]*=/ {
    if (!wrote_codex_hooks) {
      print "codex_hooks = true"
      wrote_codex_hooks = 1
    }
    next
  }
  {
    print
  }
  END {
    if (in_features && !wrote_codex_hooks) {
      print "codex_hooks = true"
      wrote_codex_hooks = 1
    }
    if (!saw_features) {
      if (total_lines > 0) {
        print ""
      }
      print "[features]"
      print "codex_hooks = true"
    }
  }
' "$tmp_config" >"$CONFIG_FILE"
rm -f "$tmp_config"

remove_lines_with_pattern() {
  local file_path="$1"
  local pattern="$2"
  local tmp_file=""

  if [[ ! -f "$file_path" ]]; then
    return 0
  fi

  tmp_file="$(mktemp)"
  grep -Fv "$pattern" "$file_path" >"$tmp_file" || true
  mv "$tmp_file" "$file_path"
}

remove_lines_with_pattern "${HOME_DIR}/.bashrc" "codex-shell-helpers.sh"
remove_lines_with_pattern "${HOME_DIR}/.zshrc" "codex-shell-helpers.sh"

echo "Installed bundled Codex home hooks into ${CODEX_DIR}"
