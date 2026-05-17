#!/bin/bash
# ============================================================================
# setup-remote-user.sh — Create non-root user + passwordless sudo on remote
# ============================================================================
# Bootstrap a remote Debian host with a non-root automation user (default:
# "agent"). This is a one-time prerequisite for running hermes-remote-backup
# as a non-root user.
#
# Usage:
#   bash setup-remote-user.sh <host> [options]
#
# Options:
#   --user <name>     Username to create (default: agent)
#   --key <path>      SSH public key to deploy (default: ~/.ssh/id_ed25519.pub)
#   --public-ip <ip>  Public IP for SSH config (default: auto-detect from hostname -I)
#   --ssh-config      Also write ~/.ssh/config entry for <host>-agent
#   --dry-run         Print what would be done, don't execute
#   --help, -h        Show this help
#
# Examples:
#   bash setup-remote-user.sh sg02
#   bash setup-remote-user.sh sg02 --user agent --key ~/.ssh/id_rsa.pub
#   bash setup-remote-user.sh sg02 --ssh-config --public-ip 1.2.3.4
#   bash setup-remote-user.sh sg02 --dry-run
# ============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
HOST=""
USERNAME="agent"
PUBKEY="${HOME}/.ssh/id_ed25519.pub"
PUBLIC_IP=""
WRITE_SSH_CONFIG=false
DRY_RUN=false

# ── Parse args ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)     USERNAME="$2"; shift 2
      # Validate: only alphanumeric + underscore + dash, POSIX username chars
      if ! echo "$USERNAME" | grep -qxE '[a-z_][a-z0-9_-]*\$?'; then
        echo "ERROR: Invalid username '$USERNAME' — use only [a-z0-9_-]" >&2
        exit 1
      fi
      ;;
    --key)      PUBKEY="$2";       shift 2 ;;
    --public-ip) PUBLIC_IP="$2";   shift 2 ;;
    --ssh-config) WRITE_SSH_CONFIG=true; shift ;;
    --dry-run)  DRY_RUN=true;      shift ;;
    --help|-h)
      echo "Usage: setup-remote-user.sh <host> [--user <name>] [--key <path>] [--public-ip <ip>] [--ssh-config] [--dry-run]"
      exit 0 ;;
    -*)
      echo "ERROR: Unknown option $1" >&2
      exit 1 ;;
    *)
      [ -z "$HOST" ] && HOST="$1" || { echo "ERROR: Unexpected arg: $1" >&2; exit 1; }
      shift ;;
  esac
done

[ -z "$HOST" ] && { echo "ERROR: <host> is required" >&2; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────

echo "=== Prerequisite Setup ==="
echo "  Target host:  $HOST"
echo "  User to create: $USERNAME"
echo "  SSH key:      $PUBKEY"
echo ""

if $DRY_RUN; then
  echo "  [DRY-RUN] Would check SSH connectivity to $HOST (as root)"
  echo "  [DRY-RUN] Would create user '$USERNAME' on $HOST"
  echo "  [DRY-RUN] Would add $USERNAME to sudo group"
  echo "  [DRY-RUN] Would configure passwordless sudo via /etc/sudoers.d/$USERNAME"
  echo "  [DRY-RUN] Would deploy SSH public key: $PUBKEY"
  if $WRITE_SSH_CONFIG; then
    echo "  [DRY-RUN] Would append SSH config entry for '${HOST}-agent' to ~/.ssh/config"
  fi
  echo ""
  echo "=== Dry-run complete ==="
  exit 0
fi

# Check SSH key exists
if [ ! -f "$PUBKEY" ]; then
  echo "ERROR: SSH public key not found at $PUBKEY" >&2
  echo "Generate one with: ssh-keygen -t ed25519 -C \"$USER@$HOST\"" >&2
  exit 1
fi

# Test SSH connectivity as root
echo "--- Checking SSH connectivity to $HOST (root) ---"
ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" "hostname" &>/dev/null || {
  echo "ERROR: Cannot SSH to $HOST as root" >&2
  echo "Ensure root SSH key-based auth is configured in ~/.ssh/config for '$HOST'" >&2
  exit 1
}
echo "  OK: Connected to $(ssh "$HOST" "hostname")"
echo ""

# Preflight: ensure sudo is installed (Debian/Ubuntu minimal installs may not have it)
echo "--- Preflight: Ensure sudo is installed ---"
ssh "$HOST" "which sudo" &>/dev/null || {
  echo "  sudo not found — installing..."
  ssh "$HOST" "apt-get update -qq && apt-get install -y -qq sudo" || {
    echo "ERROR: Failed to install sudo" >&2
    exit 1
  }
  echo "  sudo installed"
}
echo ""

# ── Step 1: Check if user already exists ──────────────────────────────────────

echo "--- Step 1: Check if user '$USERNAME' exists ---"
if ssh "$HOST" "id -u '$USERNAME' &>/dev/null"; then
  echo "  User '$USERNAME' already exists (uid=$(ssh "$HOST" "id -u '$USERNAME'"))"
  USER_EXISTS=true
else
  echo "  User '$USERNAME' does not exist — will create"
  USER_EXISTS=false
fi
echo ""

# ── Step 2: Create user (if not exists) ────────────────────────────────────────

echo "--- Step 2: Create user '$USERNAME' ---"
if $USER_EXISTS; then
  echo "  Skipped (user already exists)"
else
  ssh "$HOST" "adduser --disabled-password --gecos 'Automation user for remote backup' '$USERNAME'" 2>/dev/null || {
    echo "ERROR: Failed to create user '$USERNAME'" >&2
    exit 1
  }
  echo "  Created user '$USERNAME'"
fi
echo ""

# ── Step 3: Add to sudo group ─────────────────────────────────────────────────

echo "--- Step 3: Add '$USERNAME' to sudo group ---"
ssh "$HOST" "usermod -aG sudo '$USERNAME'" 2>/dev/null || {
  echo "ERROR: Failed to add '$USERNAME' to sudo group" >&2
  exit 1
}
echo "  Added '$USERNAME' to sudo group"
echo ""

# ── Step 4: Passwordless sudo ─────────────────────────────────────────────────

echo "--- Step 4: Configure passwordless sudo ---"
# Ensure /etc/sudoers.d exists (may not on minimal installs if sudo was just installed)
ssh "$HOST" "mkdir -p /etc/sudoers.d" 2>/dev/null || true
SSH_SUDOERS_CMD=$(cat <<CMD
if [ -f "/etc/sudoers.d/${USERNAME}" ]; then
  echo 'EXISTS'
else
  echo '${USERNAME} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/${USERNAME}
  chmod 440 /etc/sudoers.d/${USERNAME}
  echo 'CREATED'
fi
CMD
)

SUDOERS_RESULT=$(ssh "$HOST" "$SSH_SUDOERS_CMD" 2>/dev/null || echo "FAILED")
case "$SUDOERS_RESULT" in
  CREATED) echo "  Created /etc/sudoers.d/$USERNAME with NOPASSWD: ALL" ;;
  EXISTS)  echo "  /etc/sudoers.d/$USERNAME already exists — unchanged" ;;
  *)       echo "ERROR: Failed to configure sudoers: $SUDOERS_RESULT" >&2; exit 1 ;;
esac
echo ""

# ── Step 5: Deploy SSH public key ─────────────────────────────────────────────

echo "--- Step 5: Deploy SSH public key ---"
PUBKEY_CONTENT=$(cat "$PUBKEY")
SSH_DIR_CMD=$(cat <<CMD
mkdir -p ~${USERNAME}/.ssh
chmod 700 ~${USERNAME}/.ssh
if ! grep -qF '${PUBKEY_CONTENT}' ~${USERNAME}/.ssh/authorized_keys 2>/dev/null; then
  echo '${PUBKEY_CONTENT}' >> ~${USERNAME}/.ssh/authorized_keys
  echo 'ADDED'
else
  echo 'EXISTS'
fi
chmod 600 ~${USERNAME}/.ssh/authorized_keys
chown -R ${USERNAME}:${USERNAME} ~${USERNAME}/.ssh
CMD
)

KEY_RESULT=$(ssh "$HOST" "$SSH_DIR_CMD" 2>/dev/null || echo "FAILED")
case "$KEY_RESULT" in
  ADDED) echo "  SSH public key added to ~${USERNAME}/.ssh/authorized_keys" ;;
  EXISTS) echo "  SSH public key already present — unchanged" ;;
  *)      echo "ERROR: Failed to deploy SSH key: $KEY_RESULT" >&2; exit 1 ;;
esac
echo ""

# ── Step 6: Verify non-root SSH access ────────────────────────────────────────

echo "--- Step 6: Verify SSH access as $USERNAME ---"
AGENT_HOST="${HOST}-${USERNAME}"
if ssh -o ConnectTimeout=5 -o BatchMode=yes "${AGENT_HOST}" "whoami" &>/dev/null 2>&1; then
  echo "  OK: SSH as $USERNAME via alias '$AGENT_HOST'"
elif ssh -o ConnectTimeout=5 -o BatchMode=yes "${USERNAME}@${HOST}" "whoami" &>/dev/null 2>&1; then
  echo "  OK: SSH as $USERNAME via '${USERNAME}@${HOST}'"
else
  echo "  WARNING: Could not verify SSH as $USERNAME" >&2
  echo "  You may need to add an SSH config entry (see below)" >&2
fi
echo ""

# ── Step 7: Write SSH config entry (optional) ─────────────────────────────────

SSH_CONFIG_ENTRY=$(cat <<ENTRY

# Remote backup host: $HOST (non-root user)
Host ${HOST}-${USERNAME}
  HostName ${PUBLIC_IP:-$(ssh "$HOST" "hostname -I 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "<IP-of-${HOST}>")}
  User ${USERNAME}
  Port 22
  IdentityFile ${PUBKEY%.pub}
  IdentitiesOnly yes
  PreferredAuthentications publickey
ENTRY
)

if $WRITE_SSH_CONFIG; then
  echo "--- Step 7: Write SSH config entry ---"
  if grep -q "Host ${HOST}-${USERNAME}" ~/.ssh/config 2>/dev/null; then
    echo "  SSH config entry for '${HOST}-${USERNAME}' already exists"
  else
    echo "$SSH_CONFIG_ENTRY" >> ~/.ssh/config
    chmod 600 ~/.ssh/config
    echo "  Appended to ~/.ssh/config:"
    echo "$SSH_CONFIG_ENTRY"
  fi
  echo ""
else
  echo "--- Step 7: SSH config snippet (add manually or re-run with --ssh-config) ---"
  echo "$SSH_CONFIG_ENTRY"
  echo ""
fi

# ── Summary ────────────────────────────────────────────────────────────────────

echo "=== Setup Complete ==="
echo "  Host:     $HOST"
echo "  User:     $USERNAME"
echo ""
echo "  Connect as non-root:"
echo "    ssh ${HOST}-${USERNAME}"
echo ""
echo "  Test sudo access:"
echo "    ssh ${HOST}-${USERNAME} \"sudo whoami\""
echo "    # Expected output: root"
echo ""
echo "  Run backup as non-root:"
echo "    bash scripts/remote-backup.sh ${HOST}-${USERNAME} --mode quick"
echo ""
echo "  SECURITY NOTE:"
echo "    Consider disabling root SSH login after verification:"
echo "    ssh $HOST \"sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && systemctl restart sshd\""
