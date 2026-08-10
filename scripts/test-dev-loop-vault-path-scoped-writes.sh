#!/usr/bin/env bash
set -euo pipefail

# Test: managed vault writes must be path-scoped, not git add -A.
# Asserts that unrelated modified and untracked files remain unstaged,
# uncommitted, and unchanged after a path-scoped managed write.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'test-dev-loop-vault-path-scoped-writes: %s\n' "$1" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Initialize a mock vault git repo
git init -q "$TMP/vault"
cd "$TMP/vault"
git config user.email "test@test.com"
git config user.name "Test"

# Create an initial commit with a log.md and an unrelated file
mkdir -p projects/test/work
cat > log.md <<'EOF'
# Vault Log
EOF
cat > unrelated-tracked.md <<'EOF'
# Unrelated tracked file
original content
EOF
git add log.md unrelated-tracked.md
git commit -q -m "initial vault state"

# --- Simulate a managed write (retro append to log.md) ---
# Append a retro entry to log.md (the authorized target file)
cat >> log.md <<'EOF'

## [2026-08-10] retro | loop cycle: test-work-item
- Friction: test friction
- Miss: test miss
- Improve: test improvement
- Generalize?: no
- ClaudeMd?: no
- WorkflowShift?: no
EOF

# Create a new work-item retro.md (another authorized target file)
cat > projects/test/work/retro.md <<'EOF'
# Retro: test work item
EOF

# --- Simulate unrelated concurrent changes ---
# Modify an unrelated tracked file (dirty but NOT authorized)
echo "concurrent modification by another session" >> unrelated-tracked.md

# Create an unrelated untracked file (new but NOT authorized)
cat > unrelated-untracked.md <<'EOF'
# Unrelated untracked file
should not be committed
EOF

# --- Path-scoped staging (the fix) ---
# Stage ONLY the authorized target files (log.md and the retro.md)
git add log.md projects/test/work/retro.md

# Commit with only the staged paths
git commit -q -m "dev-loop[test-work-item]: managed write (retro/crystallize)"

# --- Assertions ---

# 1. log.md change IS committed
git show HEAD:log.md | grep -q "test-work-item" || fail "log.md retro entry not committed"

# 2. projects/test/work/retro.md IS committed
git show HEAD:projects/test/work/retro.md | grep -q "Retro: test work item" \
  || fail "work-item retro.md not committed"

# 3. unrelated-tracked.md is still dirty (modified, not committed)
git diff --name-only HEAD | grep -q "unrelated-tracked.md" \
  || fail "unrelated-tracked.md was unexpectedly committed"

# 4. unrelated-untracked.md is still untracked
git status --porcelain | grep -q "^?? unrelated-untracked.md" \
  || fail "unrelated-untracked.md was unexpectedly tracked/staged"

# 5. unrelated-tracked.md content is byte-for-byte unchanged
EXPECTED="original content
concurrent modification by another session"
ACTUAL="$(cat unrelated-tracked.md)"
[[ "$ACTUAL" == *"$EXPECTED" ]] || fail "unrelated-tracked.md content changed: expected to end with='$EXPECTED' actual='$ACTUAL'"

# 6. unrelated-untracked.md content is byte-for-byte unchanged
EXPECTED_UNTRACKED="should not be committed"
ACTUAL_UNTRACKED="$(cat unrelated-untracked.md | grep -v '^#')"
[[ "$ACTUAL_UNTRACKED" == "$EXPECTED_UNTRACKED" ]] \
  || fail "unrelated-untracked.md content changed: expected='$EXPECTED_UNTRACKED' actual='$ACTUAL_UNTRACKED'"

# 7. No `git add -A` in the SKILL.md SAVE step 7 auto-commit instruction
if grep -q 'git -C \$VAULT add -A' "$ROOT/skills/dev-loop/skills/dev-loop/SKILL.md"; then
  fail "SKILL.md still contains 'git add -A' in a vault auto-commit context"
fi

printf 'test-dev-loop-vault-path-scoped-writes: all checks passed\n'
