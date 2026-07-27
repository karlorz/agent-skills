#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="${SCRIPT_DIR}/setup-playwright-cli.sh"
TEST_ROOT="$(mktemp -d)"
cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "${TEST_ROOT}" ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'test-setup-playwright-cli: %s\n' "$1" >&2
  exit 1
}

PROJECT="${TEST_ROOT}/project with spaces"
BIN_DIR="${TEST_ROOT}/bin with spaces"
DATA_DIR="${TEST_ROOT}/data with spaces"
STATE_DIR="${TEST_ROOT}/state with spaces"
mkdir -p "${PROJECT}"

bash "${SETUP}" \
  --skip-cli \
  --project "${PROJECT}" \
  --bin-dir "${BIN_DIR}" \
  --data-dir "${DATA_DIR}" \
  --state-dir "${STATE_DIR}"

[[ -x "${BIN_DIR}/chrome-debug" ]] || fail "launcher command was not installed"
[[ -x "${DATA_DIR}/chrome-debug.sh" ]] || fail "launcher payload was not installed"
[[ -f "${PROJECT}/.playwright/cli.config.json" ]] || fail "project config was not initialized"
grep -Fq 'http://localhost:9222' "${PROJECT}/.playwright/cli.config.json" || fail "project config lacks CDP endpoint"

# The installed command must preserve the invoking repository for the explicit
# repo-local mode even though its payload lives in user data storage.
launcher_json="$(
  cd "${PROJECT}"
  HOME="${TEST_ROOT}/home" CHROME=/usr/bin/true \
    "${BIN_DIR}/chrome-debug" --repo-local-profile --dry-run --json
)"
python3 - "${launcher_json}" "${PROJECT}" "${STATE_DIR}" <<'PY'
import json
import os
import sys

data = json.loads(sys.argv[1])
project = sys.argv[2]
state = sys.argv[3]
assert data["projectRoot"] == project, data
assert data["profileDir"] == os.path.join(project, ".chrome-debug-profile"), data
assert data["logFile"] == os.path.join(state, "chrome-debug.log"), data
PY

# Re-running is idempotent, and an existing richer config with the same CDP
# endpoint must be preserved instead of replaced.
cp "${PROJECT}/.playwright/cli.config.json" "${TEST_ROOT}/config.before"
bash "${SETUP}" \
  --skip-cli \
  --project "${PROJECT}" \
  --bin-dir "${BIN_DIR}" \
  --data-dir "${DATA_DIR}" \
  --state-dir "${STATE_DIR}" >/dev/null
cmp "${TEST_ROOT}/config.before" "${PROJECT}/.playwright/cli.config.json" || fail "idempotent setup changed config"

DIVERGENT="${TEST_ROOT}/divergent"
mkdir -p "${DIVERGENT}/.playwright"
printf '%s\n' '{"browser":{"cdpEndpoint":"http://localhost:9333"}}' > "${DIVERGENT}/.playwright/cli.config.json"
if bash "${SETUP}" \
  --skip-cli \
  --skip-launcher \
  --project "${DIVERGENT}" >/dev/null 2>&1; then
  fail "setup overwrote or accepted a divergent project config"
fi

bash "${SETUP}" \
  --skip-cli \
  --skip-launcher \
  --force-project-config \
  --project "${DIVERGENT}" >/dev/null
grep -Fq 'http://localhost:9222' "${DIVERGENT}/.playwright/cli.config.json" || fail "forced config did not install the template"
find "${DIVERGENT}/.playwright" -maxdepth 1 -name 'cli.config.json.bak.*' -print -quit | grep -q . || fail "forced config did not create a backup"

printf '%s\n' '#!/usr/bin/env bash' 'echo unmanaged' > "${BIN_DIR}/chrome-debug"
chmod +x "${BIN_DIR}/chrome-debug"
bash "${SETUP}" \
  --skip-cli \
  --skip-project-config \
  --force-launcher \
  --project "${PROJECT}" \
  --bin-dir "${BIN_DIR}" \
  --data-dir "${DATA_DIR}" \
  --state-dir "${STATE_DIR}" >/dev/null
grep -Fq '# playwright-cli-managed-chrome-debug: v1' "${BIN_DIR}/chrome-debug" || fail "forced launcher was not installed"
find "${BIN_DIR}" -maxdepth 1 -name 'chrome-debug.bak.*' -print -quit | grep -q . || fail "forced launcher did not create a backup"

printf 'test-setup-playwright-cli: PASS\n'
