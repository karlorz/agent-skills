#!/usr/bin/env bash
# TDD coverage for chrome-debug --load-unpacked (contract v4).
# Does not talk to the live collect Chrome on :9222.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="${SCRIPT_DIR}/chrome-debug.sh"
HELPER="${SCRIPT_DIR}/cdp-load-unpacked.py"
SETUP="${SCRIPT_DIR}/setup-playwright-cli.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chrome-debug-load-unpacked.XXXXXX")"
cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "${TEST_ROOT}" ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'test-chrome-debug-load-unpacked: %s\n' "$1" >&2
  exit 1
}

[[ -x "${LAUNCHER}" ]] || fail "missing launcher ${LAUNCHER}"

# Homebrew bash 5.3 + set -u treats `local -a name` (no =()) as unbound.
if grep -E '^[[:space:]]*local -a [A-Za-z_][A-Za-z0-9_]*[[:space:]]*$' "${LAUNCHER}"; then
  fail "local -a arrays must be initialized with =() for bash 5.3 nounset"
fi

EXT_DIR="${TEST_ROOT}/ext"
mkdir -p "${EXT_DIR}"
printf '%s\n' '{"name":"fixture-ext","version":"1.0.0","manifest_version":3}' > "${EXT_DIR}/manifest.json"
NO_MANIFEST="${TEST_ROOT}/empty-ext"
mkdir -p "${NO_MANIFEST}"

dry_json() {
  HOME="${TEST_ROOT}/home" CHROME=/usr/bin/true \
    bash "${LAUNCHER}" --repo-local-profile --dry-run --json "$@"
}

# --- dry-run contract + flag parsing ---
base_json="$(dry_json)"
python3 - "${base_json}" <<'PY' || fail "v4 contract / unsafe-extension flag missing from dry-run json"
import json, sys
data = json.loads(sys.argv[1])
assert data["chromeDebugContract"] == "v4", data.get("chromeDebugContract")
assert data["launchArgs"].count("--enable-unsafe-extension-debugging") == 1, data["launchArgs"]
assert data.get("loadUnpackedPaths") == [], data.get("loadUnpackedPaths")
PY

load_json="$(dry_json --load-unpacked "${EXT_DIR}")"
python3 - "${load_json}" "${EXT_DIR}" <<'PY' || fail "dry-run json did not echo --load-unpacked path"
import json, os, sys
data = json.loads(sys.argv[1])
assert data["chromeDebugContract"] == "v4", data
paths = data["loadUnpackedPaths"]
assert len(paths) == 1, paths
assert os.path.samefile(paths[0], sys.argv[2]), (paths[0], sys.argv[2])
PY

if dry_json --load-unpacked "${TEST_ROOT}/no-such-ext" >/dev/null 2>&1; then
  fail "expected nonzero for missing --load-unpacked path"
fi

if dry_json --load-unpacked "${NO_MANIFEST}" >/dev/null 2>&1; then
  fail "expected nonzero for --load-unpacked dir without manifest.json"
fi

# --- helper exists and validates paths without Chrome ---
[[ -f "${HELPER}" ]] || fail "missing ${HELPER}"
python3 -m py_compile "${HELPER}" || fail "cdp-load-unpacked.py does not compile"

if python3 "${HELPER}" --path "${TEST_ROOT}/no-such-ext" >/dev/null 2>&1; then
  fail "helper accepted a missing path"
fi
if python3 "${HELPER}" --path "${NO_MANIFEST}" >/dev/null 2>&1; then
  fail "helper accepted a dir without manifest.json"
fi

# --- helper against a mock CDP websocket (loopback, not :9222) ---
MOCK_OUT="${TEST_ROOT}/mock-out.json"
python3 - "${HELPER}" "${EXT_DIR}" "${MOCK_OUT}" <<'PY' || fail "helper did not load unpacked against mock CDP"
import json
import os
import socket
import struct
import sys
import threading
import urllib.parse
from pathlib import Path

helper, ext_dir, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
EXT_ID = "pafaiemddagkegcjcaihcomblnpjfmkf"


def recv_http_headers(conn):
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = conn.recv(4096)
        if not chunk:
            break
        buf += chunk
    header, _, rest = buf.partition(b"\r\n\r\n")
    return header.decode("iso-8859-1", "replace"), rest


def decode_ws_text(conn, pending=b""):
    data = pending
    while True:
        if len(data) >= 2:
            b1, b2 = data[0], data[1]
            opcode = b1 & 0x0F
            masked = b2 & 0x80
            length = b2 & 0x7F
            idx = 2
            if length == 126:
                if len(data) < 4:
                    pass
                else:
                    length = struct.unpack("!H", data[2:4])[0]
                    idx = 4
            elif length == 127:
                if len(data) < 10:
                    length = None
                else:
                    length = struct.unpack("!Q", data[2:10])[0]
                    idx = 10
            if length is not None:
                mask = b""
                if masked:
                    if len(data) < idx + 4:
                        length = None
                    else:
                        mask = data[idx : idx + 4]
                        idx += 4
                if length is not None and len(data) >= idx + length:
                    payload = data[idx : idx + length]
                    if masked:
                        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
                    leftover = data[idx + length :]
                    if opcode == 0x8:
                        return None, leftover
                    if opcode == 0x1:
                        return payload.decode("utf-8"), leftover
        chunk = conn.recv(4096)
        if not chunk:
            return None, b""
        data += chunk


def encode_ws_text(message):
    payload = message.encode("utf-8")
    header = bytearray([0x81])
    n = len(payload)
    if n < 126:
        header.append(n)
    elif n < 65536:
        header.append(126)
        header.extend(struct.pack("!H", n))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", n))
    return bytes(header) + payload


installed = []


def handle_ws(conn, pending):
    leftover = pending
    while True:
        text, leftover = decode_ws_text(conn, leftover)
        if text is None:
            break
        msg = json.loads(text)
        method = msg.get("method")
        mid = msg.get("id")
        if method == "Extensions.getExtensions":
            body = {
                "id": mid,
                "result": {
                    "extensions": [
                        {"id": EXT_ID, "path": path, "enabled": True, "name": "fixture-ext"}
                        for path in installed
                    ]
                },
            }
        elif method == "Extensions.loadUnpacked":
            path = msg.get("params", {}).get("path")
            if path and path not in installed:
                installed.append(path)
            body = {"id": mid, "result": {"id": EXT_ID}}
        else:
            body = {"id": mid, "error": {"message": f"unexpected {method}"}}
        conn.sendall(encode_ws_text(json.dumps(body)))


def serve(sock):
    while True:
        try:
            conn, _ = sock.accept()
        except OSError:
            break
        try:
            headers, rest = recv_http_headers(conn)
            first = headers.split("\r\n", 1)[0]
            if "GET /json/version" in first:
                ws = f"ws://127.0.0.1:{port}/devtools/browser/mock"
                body = json.dumps({"webSocketDebuggerUrl": ws, "Browser": "Chrome/test"}).encode()
                conn.sendall(
                    b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
                    + str(len(body)).encode()
                    + b"\r\n\r\n"
                    + body
                )
                continue
            if "GET /json/list" in first:
                body = b"[]"
                conn.sendall(
                    b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n"
                    + body
                )
                continue
            if "Upgrade: websocket" in headers or "upgrade: websocket" in headers:
                key = ""
                for line in headers.split("\r\n"):
                    if line.lower().startswith("sec-websocket-key:"):
                        key = line.split(":", 1)[1].strip()
                import base64
                import hashlib

                accept = base64.b64encode(
                    hashlib.sha1(
                        (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
                    ).digest()
                ).decode()
                conn.sendall(
                    (
                        "HTTP/1.1 101 Switching Protocols\r\n"
                        "Upgrade: websocket\r\n"
                        "Connection: Upgrade\r\n"
                        f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                    ).encode()
                )
                handle_ws(conn, rest)
        finally:
            conn.close()
    Path(os.environ["MOCK_LOADED"]).write_text(json.dumps(installed), encoding="utf-8")


sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 0))
sock.listen(8)
port = sock.getsockname()[1]
os.environ["MOCK_LOADED"] = str(Path(out_path).with_suffix(".loaded.json"))
thread = threading.Thread(target=serve, args=(sock,), daemon=True)
thread.start()

import subprocess

proc = subprocess.run(
    [
        sys.executable,
        helper,
        "--port",
        str(port),
        "--path",
        ext_dir,
        "--timeout-ms",
        "5000",
        "--retries",
        "3",
        "--retry-delay-ms",
        "50",
    ],
    check=False,
    capture_output=True,
    text=True,
)
Path(out_path).write_text(proc.stdout, encoding="utf-8")
if proc.returncode != 0:
    sys.stderr.write(proc.stderr)
    raise SystemExit(f"helper exit {proc.returncode}")
data = json.loads(proc.stdout)
assert data.get("ok") is True, data
ids = [item.get("id") for item in data.get("loaded", [])]
assert EXT_ID in ids, data
sock.close()
thread.join(timeout=2)
PY

# --- setup copies the helper beside the launcher payload ---
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
[[ -x "${DATA_DIR}/chrome-debug.sh" ]] || fail "setup did not install chrome-debug.sh"
[[ -f "${DATA_DIR}/cdp-load-unpacked.py" ]] || fail "setup did not install cdp-load-unpacked.py"

printf 'test-chrome-debug-load-unpacked: PASS\n'
