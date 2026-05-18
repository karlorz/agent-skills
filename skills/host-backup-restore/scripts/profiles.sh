#!/bin/bash
# profiles.sh — Backup profile management
# Built-in presets + user custom profiles from YAML
# Usage: source profiles.sh; load_profile <name>
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/host-backup-restore"
PROFILES_FILE="$CONFIG_DIR/profiles.yaml"

# Built-in presets (not user-editable)
# These are the defaults; user YAML overrides if same name is used
declare -A PRESET_GROUPS=(
  [full]="base caddy_domains hermes databases other_services apt"
  [quick]="base caddy_domains hermes databases"
  [minimal]="hermes"
)

declare -A PRESET_HERMES_TIER=(
  [full]="full"
  [quick]="standard"
  [minimal]="minimal"
)

declare -A PRESET_DESCRIPTION=(
  [full]="All 6 groups — full infrastructure backup"
  [quick]="Essential state: Hermes, databases, Caddy, base (skips systemd units + apt)"
  [minimal]="Hermes agent state only — fastest snapshot"
)

# Resolve a profile name to groups + hermes-tier
# Sets PROFILE_GROUPS, PROFILE_HERMES_TIER, PROFILE_DESCRIPTION
resolve_profile() {
  local name="${1:-full}"
  PROFILE_GROUPS=""
  PROFILE_HERMES_TIER="full"
  PROFILE_DESCRIPTION=""

  # Check user YAML first
  if [ -f "$PROFILES_FILE" ]; then
    local yaml_result
    yaml_result=$(python3 -c "
import sys, os

profiles_file = '$PROFILES_FILE'
target = '$name'

try:
    # Simple YAML parser (no pyyaml dependency)
    with open(profiles_file) as f:
        content = f.read()

    # Find the profile block
    in_profiles = False
    in_target = False
    groups = ''
    tier = 'full'
    desc = ''

    for line in content.split('\n'):
        stripped = line.strip()
        if stripped == 'profiles:':
            in_profiles = True
            continue
        if in_profiles and stripped.startswith(f'{target}:'):
            in_target = True
            continue
        if in_target:
            if stripped.startswith('groups:'):
                groups = stripped.split(':', 1)[1].strip().strip('[]').replace(',', ' ').replace(\"'\", '').replace('\"', '')
            elif stripped.startswith('hermes_tier:'):
                tier = stripped.split(':', 1)[1].strip().replace(\"'\", '').replace('\"', '')
            elif stripped.startswith('description:'):
                desc = stripped.split(':', 1)[1].strip().strip('\"').strip(\"'\")
            elif stripped and not stripped.startswith('#') and ':' in stripped and not stripped.startswith(' '):
                break  # Next profile or top-level key

    if groups:
        print(f'{groups}|{tier}|{desc}')
except Exception as e:
    pass
" 2>/dev/null) || true

    if [ -n "$yaml_result" ]; then
      PROFILE_GROUPS=$(echo "$yaml_result" | cut -d'|' -f1)
      PROFILE_HERMES_TIER=$(echo "$yaml_result" | cut -d'|' -f2)
      PROFILE_DESCRIPTION=$(echo "$yaml_result" | cut -d'|' -f3)
      return 0
    fi
  fi

  # Fall back to built-in presets
  if [ -n "${PRESET_GROUPS[$name]+_}" ]; then
    PROFILE_GROUPS="${PRESET_GROUPS[$name]}"
    PROFILE_HERMES_TIER="${PRESET_HERMES_TIER[$name]}"
    PROFILE_DESCRIPTION="${PRESET_DESCRIPTION[$name]}"
    return 0
  fi

  echo "Error: Profile '$name' not found. Use --list-profiles to see available profiles." >&2
  return 1
}

# List all available profiles (presets + user)
list_profiles() {
  echo "=== Backup Profiles ==="
  echo ""
  echo "Built-in presets:"
  for name in full quick minimal; do
    printf "  %-12s %s\n" "$name" "${PRESET_DESCRIPTION[$name]}"
    printf "  %-12s groups: %s, hermes-tier: %s\n" "" "${PRESET_GROUPS[$name]}" "${PRESET_HERMES_TIER[$name]}"
    echo ""
  done

  if [ -f "$PROFILES_FILE" ]; then
    echo "Custom profiles ($PROFILES_FILE):"
    python3 -c "
import re

with open('$PROFILES_FILE') as f:
    content = f.read()

in_profiles = False
current = None
for line in content.split('\n'):
    stripped = line.strip()
    if stripped == 'profiles:':
        in_profiles = True
        continue
    if in_profiles and re.match(r'^  \w+:', stripped):
        current = stripped.rstrip(':')
        print(f'  {current}')
    elif in_profiles and current and 'description:' in stripped:
        desc = stripped.split(':', 1)[1].strip().strip('\"').strip(\"'\")
        print(f'    {desc}')
    elif in_profiles and current and 'groups:' in stripped:
        groups = stripped.split(':', 1)[1].strip()
        print(f'    groups: {groups}')
    elif in_profiles and current and 'hermes_tier:' in stripped:
        tier = stripped.split(':', 1)[1].strip()
        print(f'    hermes-tier: {tier}')
        print()
" 2>/dev/null || echo "  (error reading profiles file)"
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

# Save current selection as a named profile
save_profile() {
  local name="$1"
  local groups="$2"
  local tier="${3:-full}"
  local desc="${4:-Custom profile}"

  mkdir -p "$CONFIG_DIR"

  # If file exists, update or append
  if [ -f "$PROFILES_FILE" ]; then
    python3 -c "
import re

name = '$name'
groups = '$groups'
tier = '$tier'
desc = '$desc'

with open('$PROFILES_FILE') as f:
    content = f.read()

# Check if profiles: section exists
if 'profiles:' not in content:
    content = content.rstrip() + '\nprofiles:\n'

# Check if this profile already exists
pattern = rf'  {re.escape(name)}:.*?(?=\n  \w|\Z)'
match = re.search(pattern, content, re.DOTALL)

new_block = f'''  {name}:
    groups: [{groups.replace(' ', ', ')}]
    hermes_tier: {tier}
    description: \"{desc}\"
'''

if match:
    content = content[:match.start()] + new_block + content[match.end():]
else:
    content = content.rstrip() + '\n' + new_block

with open('$PROFILES_FILE', 'w') as f:
    f.write(content)

print(f'Profile \"{name}\" saved to $PROFILES_FILE')
" 2>/dev/null
  else
    cat > "$PROFILES_FILE" <<EOF
# host-backup-restore custom profiles
# See: /host-backup-restore --list-profiles

profiles:
  ${name}:
    groups: [$(echo "$groups" | tr ' ' ',')]
    hermes_tier: ${tier}
    description: "${desc}"
EOF
    echo "Profile '$name' saved to $PROFILES_FILE"
  fi
}
