#!/bin/bash
# Regression tests for host-backup-restore backup orchestration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  shift
  if "$@"; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_nonempty() {
  test -s "$1"
}

test_discover_uses_shell_safe_python_transport() {
  local discover="$SKILL_DIR/scripts/discover.sh"
  local backup_cli="$SKILL_DIR/scripts/host-backup-cli.sh"

  assert "discover.sh does not pass Python through double-quoted python3 -c" \
    bash -c "! grep -q 'python3 -c \"' '$discover'"
  assert "discover.sh uses stdin Python program transport" \
    grep -q "python3 - .*<<'PY'" "$discover"
  assert "backup CLI records separate hostname and resolved SSH target" \
    grep -q 'manifest\["ssh_target"\] = ssh_target' "$backup_cli"
}

test_ssh_and_tailscale_groups_create_artifacts() {
  local tmp remote stubbin manifest out
  tmp="$(mktemp -d)"
  remote="$tmp/remote"
  stubbin="$tmp/bin"
  manifest="$tmp/manifest.json"
  out="$tmp/backups"
  mkdir -p "$remote/etc/ssh" "$remote/root/.ssh" "$remote/home/agent/.ssh" \
    "$remote/var/lib/tailscale" "$remote/etc/default" \
    "$remote/usr/lib/systemd/system" "$remote/etc/apt/sources.list.d" \
    "$remote/usr/share/keyrings" "$stubbin" "$out"

  echo "Host *" > "$remote/etc/ssh/ssh_config"
  echo "sshd" > "$remote/etc/ssh/sshd_config"
  echo "host-key" > "$remote/etc/ssh/ssh_host_ed25519_key"
  echo "root-key" > "$remote/root/.ssh/authorized_keys"
  echo "agent-key" > "$remote/home/agent/.ssh/authorized_keys"
  echo "state" > "$remote/var/lib/tailscale/tailscaled.state"
  echo "FLAGS=--ssh" > "$remote/etc/default/tailscaled"
  echo "[Service]" > "$remote/usr/lib/systemd/system/tailscaled.service"
  echo "deb tailscale" > "$remote/etc/apt/sources.list.d/tailscale.list"
  echo "keyring" > "$remote/usr/share/keyrings/tailscale-archive-keyring.gpg"

  cat > "$manifest" <<'JSON'
{
  "hostname": "fakehost",
  "ssh_target": "fakeuser@fakehost",
  "timestamp": "2026-05-31T00:00:00Z",
  "caddy_domains": [],
  "hermes": {},
  "databases": {"sqlite": []},
  "other_services": [],
  "apt_sources": []
}
JSON

  cat > "$stubbin/ssh" <<'SH'
#!/bin/bash
set -euo pipefail

cmd="${@: -1}"
remote_root="${FAKE_REMOTE_ROOT:?}"

case "$cmd" in
  *"/etc/ssh"*"/root/.ssh"*"/home/"*".ssh"*)
    tar -czf - -C "$remote_root" etc/ssh root/.ssh home/agent/.ssh
    ;;
  *"/var/lib/tailscale"*)
    tar -czf - -C "$remote_root" \
      var/lib/tailscale \
      etc/default/tailscaled \
      usr/lib/systemd/system/tailscaled.service \
      etc/apt/sources.list.d/tailscale.list \
      usr/share/keyrings/tailscale-archive-keyring.gpg
    ;;
  *"tailscale version"*)
    printf '1.84.0\n'
    ;;
  *"tailscale ip -4"*)
    printf '100.64.0.2\n'
    ;;
  *"tailscale ip -6"*)
    printf 'fd7a:115c:a1e0::2\n'
    ;;
  *"tailscale status --json"*)
    printf '{"Self":{"HostName":"fakehost"}}\n'
    ;;
  *"systemctl status tailscaled"*)
    printf 'tailscaled active\n'
    ;;
  *"cat /tmp/"*)
    ;;
  -O*)
    ;;
  *)
    printf 'stub ssh did not handle command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
SH
  chmod +x "$stubbin/ssh"

  FAKE_REMOTE_ROOT="$remote" PATH="$stubbin:$PATH" BACKUP_DIR="$out" \
    bash "$SKILL_DIR/scripts/backup-host.sh" "$manifest" ssh tailscale >/tmp/test-backup-groups.out

  local backup_dir
  backup_dir="$(find "$out/fakehost" -maxdepth 1 -type d -name 'backup-*' | head -1)"

  assert "ssh group creates SSH identity archive" \
    assert_file_nonempty "$backup_dir/ssh-config-and-keys.tar.gz"
  assert "tailscale group creates Tailscale state archive" \
    assert_file_nonempty "$backup_dir/tailscale-state-and-config.tar.gz"
  assert "tailscale group captures status JSON" \
    assert_file_nonempty "$backup_dir/tailscale-status.json"
  assert "backup directory permissions are owner-only" \
    bash -c "[[ \$(stat -f '%Lp' '$backup_dir' 2>/dev/null || stat -c '%a' '$backup_dir') == 700 ]]"
}

test_discover_uses_shell_safe_python_transport
test_ssh_and_tailscale_groups_create_artifacts

echo "Tests: $PASS passed, $FAIL failed"
test "$FAIL" -eq 0
