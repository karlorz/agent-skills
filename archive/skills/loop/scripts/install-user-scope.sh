#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-user-scope.sh [--codex-home DIR] [--mode copy|symlink]

Notes:
  - Installs the skill bundle into CODEX_HOME/skills/loop.
  - Does not modify Stop hooks.
  - This is user-scope skill installation, not job registration.
EOF
}

codex_home_default() {
  if [[ -n "${CODEX_HOME:-}" ]]; then
    printf '%s\n' "$CODEX_HOME"
  else
    printf '%s/.codex\n' "$HOME"
  fi
}

remove_path() {
  local path="$1"
  if [[ -L "$path" || -e "$path" ]]; then
    rm -rf "$path"
  fi
}

MODE="copy"
CODEX_HOME_DIR="$(codex_home_default)"

while (($# > 0)); do
  case "$1" in
    --codex-home)
      CODEX_HOME_DIR="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  copy|symlink) ;;
  *)
    echo "Unsupported install mode: $MODE" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${CODEX_HOME_DIR}/skills"
TARGET_SKILL_DIR="${SKILLS_DIR}/loop"

mkdir -p "$SKILLS_DIR"
remove_path "$TARGET_SKILL_DIR"

if [[ "$MODE" == "copy" ]]; then
  cp -R "$SKILL_ROOT" "$TARGET_SKILL_DIR"
else
  ln -s "$SKILL_ROOT" "$TARGET_SKILL_DIR"
fi

echo "Installed Loop skill into $TARGET_SKILL_DIR"
