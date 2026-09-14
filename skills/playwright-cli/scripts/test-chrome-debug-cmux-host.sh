#!/usr/bin/env bash
# TDD coverage for chrome-debug-contract v5 cmux host-class.
# Does not talk to the live collect/cmux Chrome on :9222.
# macos-dev attach path must keep owned_by_profile when the listener is not cmux-cdp-proxy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="${SCRIPT_DIR}/chrome-debug.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chrome-debug-cmux-host.XXXXXX")"
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
  printf 'test-chrome-debug-cmux-host: %s\n' "$1" >&2
  exit 1
}

[[ -x "${LAUNCHER}" ]] || fail "missing launcher ${LAUNCHER}"

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

write_cdp_stub() {
  local dest="$1"
  cat > "${dest}" <<'PY'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

PORT = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/json/version"):
            body = (
                b'{"Browser":"Chrome/test",'
                b'"webSocketDebuggerUrl":"ws://127.0.0.1:39382/devtools/browser/test"}'
            )
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, *_args):
        return


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PY
  chmod +x "${dest}"
}

wait_healthy() {
  local port="$1"
  local _
  for _ in $(seq 1 40); do
    if curl -fs "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

start_cdp_stub() {
  local dest="$1"
  local label="$2"
  local port_var="$3"
  local port
  port="$(pick_port)"
  cp "${STUB_SRC}" "${dest}"
  chmod +x "${dest}"
  "${dest}" "${port}" &
  PIDS+=("$!")
  wait_healthy "${port}" || fail "${label} stub did not become healthy on ${port}"
  printf -v "${port_var}" '%s' "${port}"
}

HOME_DIR="${TEST_ROOT}/home"
mkdir -p "${HOME_DIR}"
PROFILE_DIR="${HOME_DIR}/.config/Google/chrome-debug-profile-from-default"
mkdir -p "${PROFILE_DIR}/Default"

explain_json() {
  local port="$1"
  HOME="${HOME_DIR}" CHROME=/usr/bin/true CHROME_DEBUG_PORT="${port}" \
    bash "${LAUNCHER}" --explain --json
}

check_json() {
  local port="$1"
  HOME="${HOME_DIR}" CHROME=/usr/bin/true CHROME_DEBUG_PORT="${port}" \
    bash "${LAUNCHER}" --check-port --json
}

STUB_SRC="${TEST_ROOT}/cdp-stub"
write_cdp_stub "${STUB_SRC}"

# --- A: cmux-cdp-proxy listener is owned_by_cmux even if a profile marker exists ---
start_cdp_stub "${TEST_ROOT}/cmux-cdp-proxy" "cmux" CMUX_PORT
python3 -c 'import time,sys; time.sleep(600)' --user-data-dir="${PROFILE_DIR}" &
PIDS+=("$!")

cmux_explain="$(explain_json "${CMUX_PORT}")"
python3 - "${cmux_explain}" <<'PY' || fail "cmux listener + profile marker must be owned_by_cmux"
import json, sys
data = json.loads(sys.argv[1])
assert data["portStatus"] == "owned_by_cmux", data
action = data["nextAction"].lower()
assert "attach" in action, data
assert "do not run chrome-debug --restart" in action, data
PY

cmux_check="$(check_json "${CMUX_PORT}")"
python3 - "${cmux_check}" <<'PY' || fail "cmux --check-port json status"
import json, sys
data = json.loads(sys.argv[1])
assert data["status"] == "owned_by_cmux", data
PY

cmux_pid="${PIDS[0]}"
restart_rc=0
HOME="${HOME_DIR}" CHROME=/usr/bin/true CHROME_DEBUG_PORT="${CMUX_PORT}" \
  bash "${LAUNCHER}" --restart >/tmp/chrome-debug-cmux-restart.out 2>/tmp/chrome-debug-cmux-restart.err || restart_rc=$?
[[ "${restart_rc}" -ne 0 ]] || fail "cmux --restart must refuse (exit non-zero)"
grep -Ei 'cmux|refus' /tmp/chrome-debug-cmux-restart.err /tmp/chrome-debug-cmux-restart.out >/dev/null \
  || fail "cmux --restart must mention cmux/refuse"
kill -0 "${cmux_pid}" 2>/dev/null || fail "cmux --restart killed the proxy (pid ${cmux_pid})"
curl -fs "http://127.0.0.1:${CMUX_PORT}/json/version" >/dev/null || fail "cmux stub died after --restart"

# --- B: macos-dev regression — non-cmux listener + profile marker stays owned_by_profile ---
start_cdp_stub "${TEST_ROOT}/fake-chrome-cdp" "macos" MAC_PORT

mac_explain="$(explain_json "${MAC_PORT}")"
python3 - "${mac_explain}" <<'PY' || fail "macos-dev path must stay owned_by_profile"
import json, sys
data = json.loads(sys.argv[1])
assert data["portStatus"] == "owned_by_profile", data
assert "restart" in data["nextAction"].lower() or "attach" in data["nextAction"].lower(), data
PY

printf 'test-chrome-debug-cmux-host: PASS\n'
