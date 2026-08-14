#!/bin/bash
# profiles.sh — Backup profile management
# Built-in presets + user custom profiles from YAML
# Usage: source profiles.sh; resolve_profile <name>
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/host-backup-restore"
PROFILES_FILE="$CONFIG_DIR/profiles.yaml"
PORTFOLIO_LAB_GROUP="portfolio_lab"

# Use functions rather than associative arrays so the profile path runs on the
# Bash 3.2 shipped with macOS.
preset_groups() {
  case "$1" in
    full) printf '%s' 'base ssh tailscale caddy_domains hermes databases other_services apt wiki' ;;
    quick) printf '%s' 'base caddy_domains hermes databases' ;;
    minimal) printf '%s' 'hermes' ;;
    portfolio-lab) printf '%s' 'portfolio_lab' ;;
    *) return 1 ;;
  esac
}

preset_hermes_tier() {
  case "$1" in
    full) printf '%s' 'full' ;;
    quick) printf '%s' 'standard' ;;
    minimal) printf '%s' 'minimal' ;;
    portfolio-lab) printf '%s' '' ;;
    *) return 1 ;;
  esac
}

preset_description() {
  case "$1" in
    full) printf '%s' 'All 9 groups — full infrastructure backup including SSH identity and Tailscale state' ;;
    quick) printf '%s' 'Essential state: Hermes, databases, Caddy, base (skips systemd units + apt)' ;;
    minimal) printf '%s' 'Hermes agent state only — fastest snapshot' ;;
    portfolio-lab) printf '%s' 'Portfolio Lab application bundle only — exclusive profile; cannot mix with generic host/identity/Caddy/Hermes groups' ;;
    *) return 1 ;;
  esac
}

assert_portfolio_lab_isolated() {
  local groups="$1" normalized count has_pl g
  normalized=$(printf '%s' "$groups" | tr ',' ' ')
  count=0
  has_pl=false
  for g in $normalized; do
    count=$((count + 1))
    [ "$g" = "$PORTFOLIO_LAB_GROUP" ] && has_pl=true
  done
  if $has_pl && [ "$count" -ne 1 ]; then
    echo "Error: '$PORTFOLIO_LAB_GROUP' cannot be combined with generic groups (host, identity, Caddy, Hermes). Use --profile portfolio-lab alone." >&2
    return 1
  fi
}

read_custom_profile() {
  python3 - "$PROFILES_FILE" "$1" <<'PY'
import sys

profiles_file, target = sys.argv[1:]
try:
    with open(profiles_file, encoding="utf-8") as handle:
        content = handle.read()
except OSError:
    raise SystemExit(0)

in_profiles = False
in_target = False
groups = ""
tier = "full"
description = ""
for line in content.splitlines():
    stripped = line.strip()
    if stripped == "profiles:":
        in_profiles = True
        continue
    if in_profiles and line.startswith("  ") and not line.startswith("    ") and stripped.endswith(":"):
        in_target = stripped[:-1] == target
        continue
    if not in_target:
        continue
    if stripped.startswith("groups:"):
        groups = stripped.split(":", 1)[1].strip().strip("[]").replace(",", " ").replace("'", "").replace('"', "")
    elif stripped.startswith("hermes_tier:"):
        tier = stripped.split(":", 1)[1].strip().strip("'\"")
    elif stripped.startswith("description:"):
        description = stripped.split(":", 1)[1].strip().strip("'\"")
if groups:
    print(f"{groups}|{tier}|{description}")
PY
}

resolve_profile() {
  local name="${1:-full}" yaml_result
  PROFILE_GROUPS=""
  PROFILE_HERMES_TIER="full"
  PROFILE_DESCRIPTION=""

  # Built-in profile names are reserved: user YAML cannot override them.
  if [ "$name" = "portfolio-lab" ]; then
    PROFILE_GROUPS=$(preset_groups "$name")
    PROFILE_HERMES_TIER=$(preset_hermes_tier "$name")
    PROFILE_DESCRIPTION=$(preset_description "$name")
    return 0
  fi

  if [ -f "$PROFILES_FILE" ]; then
    yaml_result=$(read_custom_profile "$name") || true
    if [ -n "$yaml_result" ]; then
      PROFILE_GROUPS=$(printf '%s' "$yaml_result" | cut -d'|' -f1)
      PROFILE_HERMES_TIER=$(printf '%s' "$yaml_result" | cut -d'|' -f2)
      PROFILE_DESCRIPTION=$(printf '%s' "$yaml_result" | cut -d'|' -f3)
      return 0
    fi
  fi

  if PROFILE_GROUPS=$(preset_groups "$name"); then
    PROFILE_HERMES_TIER=$(preset_hermes_tier "$name")
    PROFILE_DESCRIPTION=$(preset_description "$name")
    return 0
  fi

  echo "Error: Profile '$name' not found. Use --list-profiles to see available profiles." >&2
  return 1
}

list_custom_profiles() {
  python3 - "$PROFILES_FILE" <<'PY'
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        content = handle.read()
except OSError:
    raise SystemExit(0)

in_profiles = False
current = None
for line in content.splitlines():
    stripped = line.strip()
    if stripped == "profiles:":
        in_profiles = True
        continue
    if in_profiles and re.match(r"^  [A-Za-z0-9][A-Za-z0-9_-]*:", line):
        current = stripped[:-1]
        print(f"  {current}")
    elif in_profiles and current and stripped.startswith("description:"):
        print(f"    {stripped.split(':', 1)[1].strip().strip(chr(34)).strip(chr(39))}")
    elif in_profiles and current and stripped.startswith("groups:"):
        print(f"    groups: {stripped.split(':', 1)[1].strip()}")
    elif in_profiles and current and stripped.startswith("hermes_tier:"):
        print(f"    hermes-tier: {stripped.split(':', 1)[1].strip()}")
        print()
PY
}

list_profiles() {
  local name groups tier description
  echo "=== Backup Profiles ==="
  echo ""
  echo "Built-in presets:"
  for name in full quick minimal portfolio-lab; do
    groups=$(preset_groups "$name")
    tier=$(preset_hermes_tier "$name")
    description=$(preset_description "$name")
    printf "  %-12s %s\n" "$name" "$description"
    printf "  %-12s groups: %s" "" "$groups"
    [ -z "$tier" ] || printf ", hermes-tier: %s" "$tier"
    echo ""
    echo ""
  done

  if [ -f "$PROFILES_FILE" ]; then
    echo "Custom profiles ($PROFILES_FILE):"
    list_custom_profiles || echo "  (error reading profiles file)"
  else
    echo "No custom profiles. Create $PROFILES_FILE to add custom profiles."
    echo ""
    echo "Example profiles.yaml:"
    cat <<'EXAMPLE'
profiles:
  daily:
    groups: [hermes, databases, base, caddy_domains]
    hermes_tier: full
    description: "Daily backup of essential services"
  weekly-full:
    groups: [base, caddy_domains, hermes, databases, other_services, apt]
    hermes_tier: full
    description: "Weekly full infrastructure backup"
EXAMPLE
  fi
}

save_profile() {
  local name="$1" groups="$2" tier="${3:-full}" desc="${4:-Custom profile}"
  if [ "$name" = "portfolio-lab" ]; then
    echo "Error: 'portfolio-lab' is a reserved built-in profile name and cannot be saved as a custom profile" >&2
    return 1
  fi

  mkdir -p "$CONFIG_DIR"
  python3 - "$PROFILES_FILE" "$name" "$groups" "$tier" "$desc" <<'PY'
import re
import sys

profiles_file, name, groups, tier, description = sys.argv[1:]
try:
    with open(profiles_file, encoding="utf-8") as handle:
        content = handle.read()
except OSError:
    content = ""
if "profiles:" not in content:
    content = content.rstrip() + "\nprofiles:\n"
pattern = rf"  {re.escape(name)}:.*?(?=\n  [A-Za-z0-9][A-Za-z0-9_-]*:|\Z)"
new_block = (
    f"  {name}:\n"
    f"    groups: [{groups.replace(' ', ', ')}]\n"
    f"    hermes_tier: {tier}\n"
    f'    description: "{description}"\n'
)
match = re.search(pattern, content, re.DOTALL)
if match:
    content = content[:match.start()] + new_block + content[match.end():]
else:
    content = content.rstrip() + "\n" + new_block
with open(profiles_file, "w", encoding="utf-8") as handle:
    handle.write(content)
print(f'Profile "{name}" saved to {profiles_file}')
PY
}
