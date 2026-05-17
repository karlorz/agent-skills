#!/bin/bash
# ============================================================================
# setup-nonroot-hermes.sh — Prepare Hermes environment for a non-root user
# ============================================================================
# After restoring Hermes data to a non-root user (via remote-restore.sh
# --non-root-user), run this script to make the hermes CLI available to that
# user with a working venv.
#
# Prerequisites:
#   - Non-root user must already exist on the target (use setup-remote-user.sh)
#   - Hermes source must be accessible at /usr/local/lib/hermes-agent/
#     (installed via setup-hermes.sh or equivalent)
#
# Usage:
#   bash setup-nonroot-hermes.sh <host> --user <username>
#
# Options:
#   --user <name>     Non-root username (required)
#   --help, -h        Show this help
#
# Examples:
#   bash setup-nonroot-hermes.sh sg02-agent --user agent
#   bash setup-nonroot-hermes.sh sg02 --user agent
# ============================================================================

set -euo pipefail

HOST=""
USERNAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)    USERNAME="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: setup-nonroot-hermes.sh <host> --user <name>" >&2
      exit 0 ;;
    -*)
      echo "ERROR: Unknown option $1" >&2; exit 1 ;;
    *)
      [ -z "$HOST" ] && HOST="$1" || { echo "ERROR: Unexpected arg: $1" >&2; exit 1; }
      shift ;;
  esac
done

[ -z "$HOST" ] && { echo "ERROR: <host> is required" >&2; exit 1; }
[ -z "$USERNAME" ] && { echo "ERROR: --user is required" >&2; exit 1; }

SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

# Test connectivity
echo "=== Checking SSH connectivity to $HOST ==="
ssh $SSH_OPTS "$HOST" "whoami" &>/dev/null || {
  echo "ERROR: Cannot SSH to $HOST" >&2
  exit 1
}

# Resolve user home
USER_HOME=$(ssh $SSH_OPTS "$HOST" "getent passwd '$USERNAME' | cut -d: -f6" 2>/dev/null || echo "/home/$USERNAME")
echo "  User: $USERNAME"
echo "  Home: $USER_HOME"
echo ""

# Step 1: Install uv for the user
echo "--- Step 1: Install uv ---"
UV_INSTALLED=$(ssh $SSH_OPTS "$HOST" "test -f '${USER_HOME}/.local/bin/uv' && echo yes || echo no" 2>/dev/null || echo "no")
if [ "$UV_INSTALLED" = "yes" ]; then
  echo "  uv already installed"
else
  ssh $SSH_OPTS "$HOST" "curl -LsSf https://astral.sh/uv/install.sh | sh" 2>&1 | tail -1
  echo "  uv installed"
fi
echo ""

# Step 2: Create hermes venv
echo "--- Step 2: Create Hermes venv ---"
VENV_EXISTS=$(ssh $SSH_OPTS "$HOST" "test -d '${USER_HOME}/.hermes-venv' && echo yes || echo no" 2>/dev/null || echo "no")
if [ "$VENV_EXISTS" = "yes" ]; then
  echo "  Venv already exists at ${USER_HOME}/.hermes-venv"
else
  ssh $SSH_OPTS "$HOST" "export UV_PROJECT_ENVIRONMENT='${USER_HOME}/.hermes-venv'; ${USER_HOME}/.local/bin/uv python install 3.11 -q 2>&1 | tail -1; ${USER_HOME}/.local/bin/uv venv '${USER_HOME}/.hermes-venv' --seed -q" 2>&1
  echo "  Created venv at ${USER_HOME}/.hermes-venv (with pip seed)"
fi
echo ""

# Step 3: Install hermes-agent from system source
echo "--- Step 3: Install hermes-agent in venv ---"
if [ -d "/usr/local/lib/hermes-agent" ]; then
  # System source exists — copy to user-accessible location
  SRC_EXISTS=$(ssh $SSH_OPTS "$HOST" "test -d '${USER_HOME}/hermes-agent-src' && echo yes || echo no" 2>/dev/null || echo "no")
  if [ "$SRC_EXISTS" != "yes" ]; then
    # Check if system source exists on target
    HAS_SOURCE=$(ssh $SSH_OPTS "$HOST" "test -d /usr/local/lib/hermes-agent && echo yes || echo no" 2>/dev/null || echo "no")
    if [ "$HAS_SOURCE" = "yes" ]; then
      # Need root to copy — use sudo
      ssh $SSH_OPTS "$HOST" "sudo cp -r /usr/local/lib/hermes-agent '${USER_HOME}/hermes-agent-src' && sudo chown -R '${USERNAME}:${USERNAME}' '${USER_HOME}/hermes-agent-src'" 2>&1
      echo "  Copied Hermes source from /usr/local/lib/hermes-agent"
    fi
  fi
  # Install from local source (use --python for explicit venv python path)
  VENV_PYTHON="${USER_HOME}/.hermes-venv/bin/python"
  ssh $SSH_OPTS "$HOST" "${USER_HOME}/.local/bin/uv pip install -e '${USER_HOME}/hermes-agent-src' --python '${VENV_PYTHON}' -q 2>&1" 2>/dev/null || {
    echo "  WARNING: uv install failed, trying pip directly..."
    ssh $SSH_OPTS "$HOST" "'${VENV_PYTHON}' -m pip install -e '${USER_HOME}/hermes-agent-src' -q" 2>&1
  }
  echo "  Hermes installed: $(ssh $SSH_OPTS "$HOST" "export PATH='${USER_HOME}/.hermes-venv/bin:\$PATH'; hermes --version 2>&1 | head -1")"
else
  # No system source — install from PyPI
  echo "  No system Hermes source found — installing from PyPI..."
  ssh $SSH_OPTS "$HOST" "export UV_PROJECT_ENVIRONMENT='${USER_HOME}/.hermes-venv'; ${USER_HOME}/.local/bin/uv pip install hermes-agent -q" 2>&1
fi
echo ""

# Step 4: Create ~/.local/bin/hermes symlink
echo "--- Step 4: Create hermes symlink ---"
ssh $SSH_OPTS "$HOST" "mkdir -p '${USER_HOME}/.local/bin' && ln -sf '${USER_HOME}/.hermes-venv/bin/hermes' '${USER_HOME}/.local/bin/hermes'" 2>&1
echo "  Created ${USER_HOME}/.local/bin/hermes -> ${USER_HOME}/.hermes-venv/bin/hermes"
echo ""

# Step 5: Verify
echo "--- Step 5: Verify ---"
RESULT=$(ssh $SSH_OPTS "$HOST" "export PATH='${USER_HOME}/.local/bin:\$PATH'; hermes --version 2>&1" 2>/dev/null || echo "FAILED")
if echo "$RESULT" | grep -q "Hermes Agent"; then
  echo "  ✓ hermes CLI works for user $USERNAME:"
  echo "    $RESULT"
else
  echo "  ✗ hermes CLI verification failed" >&2
  echo "    $RESULT" >&2
  exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo "  User:    $USERNAME"
echo "  Venv:    ${USER_HOME}/.hermes-venv"
echo "  Symlink: ${USER_HOME}/.local/bin/hermes"
echo ""
echo "  Add to PATH (if not already):"
echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "  Test hermes:"
echo "    ssh $HOST \"hermes doctor\""
