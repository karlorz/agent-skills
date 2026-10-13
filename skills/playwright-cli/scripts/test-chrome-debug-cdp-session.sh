#!/usr/bin/env bash
# TDD coverage for chrome-debug-contract v6 raw CDP session helper.
# Does not talk to live collect/cmux Chrome on :9222.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="${SCRIPT_DIR}/chrome-debug.sh"
HELPER="${SCRIPT_DIR}/cdp-session.py"
STUB="${SCRIPT_DIR}/test-cdp-session-stub.py"
SETUP="${SCRIPT_DIR}/setup-playwright-cli.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chrome-debug-cdp-session.XXXXXX")"
PIDS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]+"${PIDS[@]}"}"; do
    kill "${pid}" 2>/dev/null || true
  done
  if [[ -n "${TEST_ROOT:-}" && -d "${TEST_ROOT}" ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'test-chrome-debug-cdp-session: %s\n' "$1" >&2
  exit 1
}

[[ -x "${LAUNCHER}" ]] || fail "missing launcher ${LAUNCHER}"
[[ -f "${HELPER}" ]] || fail "missing helper ${HELPER}"
[[ -f "${STUB}" ]] || fail "missing stub ${STUB}"
python3 -m py_compile "${HELPER}" || fail "cdp-session.py does not compile"
python3 -m py_compile "${STUB}" || fail "test-cdp-session-stub.py does not compile"

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

wait_healthy() {
  local port="$1"
  local _
  for _ in $(seq 1 50); do
    if curl --max-time 1 -fs "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

start_stub() {
  local mode="$1"
  local port_var="$2"
  local port
  port="$(pick_port)"
  python3 "${STUB}" "${port}" "${mode}" &
  PIDS+=("$!")
  wait_healthy "${port}" || fail "stub mode ${mode} did not become healthy on ${port}"
  printf -v "${port_var}" '%s' "${port}"
}

run_helper() {
  python3 "${HELPER}" --json "$@"
}

# --- helper: list, picker fail-closed, healthy eval, decoy does not block ---
start_stub default DEFAULT_PORT

list_json="$(run_helper --port "${DEFAULT_PORT}" --timeout-ms 2000 list)"
python3 - "${list_json}" <<'PY' || fail "list should return page targets without Playwright"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is True, data
ids = {item["targetId"] for item in data["targets"]}
assert "page-healthy" in ids and "page-decoy" in ids, data
assert all("type" in item and "url" in item for item in data["targets"]), data
PY

missing_out="$(run_helper --port "${DEFAULT_PORT}" --timeout-ms 2000 eval --eval '1+1' || true)"
python3 - "${missing_out}" <<'PY' || fail "eval without picker must fail closed"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is False, data
assert "url-contains" in data["error"] or "target-id" in data["error"], data
assert "targets" in data, data
PY

eval_json="$(run_helper --port "${DEFAULT_PORT}" --timeout-ms 2000 eval --url-contains=/queue --eval '1+1')"
python3 - "${eval_json}" <<'PY' || fail "eval of healthy target must succeed while decoy exists"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is True, data
assert data["result"] == "ok-from-helper", data
assert data["targetId"] == "page-healthy", data
PY

shot="${TEST_ROOT}/shot.png"
shot_json="$(run_helper --port "${DEFAULT_PORT}" --timeout-ms 2000 screenshot --url-contains=/queue --out "${shot}")"
python3 - "${shot_json}" "${shot}" <<'PY' || fail "screenshot of healthy target"
import json, sys
from pathlib import Path
data = json.loads(sys.argv[1])
path = Path(sys.argv[2])
assert data["ok"] is True, data
raw = path.read_bytes()
assert raw.startswith(b"\x89PNG\r\n\x1a\n"), raw[:16]
PY

two_out="$(run_helper --port "${DEFAULT_PORT}" --timeout-ms 2000 eval --url-contains=example.com --eval '1' || true)"
python3 - "${two_out}" <<'PY' || fail "two URL matches must fail closed"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is False, data
assert "matched 2" in data["error"], data
PY

# --- chrome-debug early --cdp-* dispatch (no Chrome binary required) ---
HOME_DIR="${TEST_ROOT}/home"
mkdir -p "${HOME_DIR}"
list_via_launcher="$(
  HOME="${HOME_DIR}" CHROME=/does/not/exist CHROME_DEBUG_PORT="${DEFAULT_PORT}" \
    bash "${LAUNCHER}" --json --cdp-list --timeout-ms=2000
)"
python3 - "${list_via_launcher}" <<'PY' || fail "chrome-debug --cdp-list must not require Chrome binary"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is True, data
assert any(item["targetId"] == "page-healthy" for item in data["targets"]), data
PY

combo_rc=0
HOME="${HOME_DIR}" CHROME=/does/not/exist CHROME_DEBUG_PORT="${DEFAULT_PORT}" \
  bash "${LAUNCHER}" --cdp-list --restart >/tmp/cdp-combo.out 2>/tmp/cdp-combo.err || combo_rc=$?
[[ "${combo_rc}" -ne 0 ]] || fail "--cdp-list --restart must be rejected"

nopicker_rc=0
HOME="${HOME_DIR}" CHROME=/does/not/exist CHROME_DEBUG_PORT="${DEFAULT_PORT}" \
  bash "${LAUNCHER}" --json --cdp-eval --eval=1 --timeout-ms=2000 >/tmp/cdp-nopicker.out 2>/tmp/cdp-nopicker.err || nopicker_rc=$?
[[ "${nopicker_rc}" -ne 0 ]] || fail "launcher --cdp-eval without picker must fail"
python3 - <<'PY' || fail "launcher fail-closed JSON on stdout"
import json
from pathlib import Path
data = json.loads(Path("/tmp/cdp-nopicker.out").read_text())
assert data["ok"] is False, data
PY

space_eval="$(
  HOME="${HOME_DIR}" CHROME=/does/not/exist CHROME_DEBUG_PORT="${DEFAULT_PORT}" \
    bash "${LAUNCHER}" --json --cdp-eval --url-contains /queue --eval 1+1 --timeout-ms 2000
)"
python3 - "${space_eval}" <<'PY' || fail "launcher must accept space-separated --url-contains/--eval/--timeout-ms"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is True, data
assert data["result"] == "ok-from-helper", data
PY

# --- event flood on healthy eval still returns ---
start_stub flood FLOOD_PORT
flood_json="$(run_helper --port "${FLOOD_PORT}" --timeout-ms 3000 eval --url-contains=/queue --eval '1')"
python3 - "${flood_json}" <<'PY' || fail "event flood must not block a later matching result"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is True, data
assert data["result"] == "ok-from-helper", data
PY

# --- selected silent target is a bounded failure ---
start_stub silent SILENT_PORT
silent_out="$(run_helper --port "${SILENT_PORT}" --timeout-ms 400 eval --url-contains=/queue --eval '1' || true)"
python3 - "${silent_out}" <<'PY' || fail "silent selected target must time out"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is False, data
assert "timed out" in data["error"].lower(), data
PY

# --- two-queue URL matcher ---
start_stub two-queue TWO_PORT
twoq_out="$(run_helper --port "${TWO_PORT}" --timeout-ms 2000 eval --url-contains=/queue --eval '1' || true)"
python3 - "${twoq_out}" <<'PY' || fail "two /queue pages fail closed"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is False, data
assert "matched 2" in data["error"], data
PY

exact_json="$(run_helper --port "${TWO_PORT}" --timeout-ms 2000 eval --target-id=page-healthy --eval '1')"
python3 - "${exact_json}" <<'PY' || fail "--target-id selects exactly one"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is True and data["targetId"] == "page-healthy", data
PY

# --- setup copies cdp-session.py; missing helper is upgrade ---
PROJECT="${TEST_ROOT}/project"
BIN_DIR="${TEST_ROOT}/bin"
DATA_DIR="${TEST_ROOT}/data"
STATE_DIR="${TEST_ROOT}/state"
mkdir -p "${PROJECT}"
bash "${SETUP}" \
  --skip-cli \
  --skip-project-config \
  --project "${PROJECT}" \
  --bin-dir "${BIN_DIR}" \
  --data-dir "${DATA_DIR}" \
  --state-dir "${STATE_DIR}" >/dev/null
[[ -f "${DATA_DIR}/cdp-session.py" ]] || fail "setup did not install cdp-session.py"
cmp -s "${HELPER}" "${DATA_DIR}/cdp-session.py" || fail "installed cdp-session.py does not match bundle"
grep -E '^# chrome-debug-contract: v6' "${DATA_DIR}/chrome-debug.sh" >/dev/null \
  || fail "installed launcher is not contract v6"

wrapper_list="$(
  HOME="${HOME_DIR}" CHROME=/does/not/exist CHROME_DEBUG_PORT="${DEFAULT_PORT}" \
    "${BIN_DIR}/chrome-debug" --json --cdp-list --timeout-ms=2000
)"
python3 - "${wrapper_list}" <<'PY' || fail "installed chrome-debug --cdp-list uses payload helper"
import json, sys
data = json.loads(sys.argv[1])
assert data["ok"] is True, data
PY

rm -f "${DATA_DIR}/cdp-session.py"
check_rc=0
bash "${SETUP}" --check --skip-cli --skip-project-config --project "${PROJECT}" \
  --bin-dir "${BIN_DIR}" --data-dir "${DATA_DIR}" --state-dir "${STATE_DIR}" \
  >/tmp/cdp-session-check.out || check_rc=$?
[[ "${check_rc}" -eq 3 ]] || fail "missing cdp-session.py --check exit ${check_rc}, want 3"
bash "${SETUP}" \
  --skip-cli \
  --skip-project-config \
  --apply-if-needed \
  --project "${PROJECT}" \
  --bin-dir "${BIN_DIR}" \
  --data-dir "${DATA_DIR}" \
  --state-dir "${STATE_DIR}" >/tmp/cdp-session-apply.out
[[ -f "${DATA_DIR}/cdp-session.py" ]] || fail "apply-if-needed did not restore cdp-session.py"

printf 'test-chrome-debug-cdp-session: PASS\n'
