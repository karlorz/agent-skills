#!/usr/bin/env python3
"""Local CDP HTTP+WebSocket stub for cdp-session tests. Stdlib only."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import socket
import struct
import sys
import threading

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


def targets_for_mode(mode: str) -> list[dict]:
    healthy = {
        "targetId": "page-healthy",
        "type": "page",
        "url": "https://example.com/queue",
        "title": "Queue",
    }
    decoy = {
        "targetId": "page-decoy",
        "type": "page",
        "url": "https://example.com/decoy",
        "title": "Decoy",
    }
    worker = {
        "targetId": "worker-1",
        "type": "service_worker",
        "url": "https://example.com/sw.js",
        "title": "",
    }
    second = {
        "targetId": "page-healthy-2",
        "type": "page",
        "url": "https://example.com/queue?tab=2",
        "title": "Queue 2",
    }
    if mode == "two-queue":
        return [healthy, second, worker]
    return [healthy, decoy, worker]


def accept_key(key: str) -> str:
    digest = hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def recv_exact(sock: socket.socket, size: int, buf: bytearray) -> bytes:
    while len(buf) < size:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("closed")
        buf.extend(chunk)
    data = bytes(buf[:size])
    del buf[:size]
    return data


def recv_frame(sock: socket.socket, buf: bytearray) -> tuple[bytes, int]:
    header = recv_exact(sock, 2, buf)
    opcode = header[0] & 0x0F
    masked = bool(header[1] & 0x80)
    length = header[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2, buf))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8, buf))[0]
    mask = recv_exact(sock, 4, buf) if masked else b""
    payload = recv_exact(sock, length, buf)
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return payload, opcode


def send_unmasked(sock: socket.socket, payload: bytes, opcode: int = 0x1) -> None:
    header = bytearray([0x80 | opcode])
    length = len(payload)
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", length))
    sock.sendall(bytes(header) + payload)


def handle_ws(sock: socket.socket, mode: str, leftover: bytes = b"") -> None:
    buf = bytearray(leftover)
    sessions: dict[str, str] = {}
    activated: set[str] = set()
    infos = targets_for_mode(mode)
    while True:
        payload, opcode = recv_frame(sock, buf)
        if opcode == 0x8:
            return
        if opcode == 0x9:
            send_unmasked(sock, payload, 0xA)
            continue
        if opcode != 0x1:
            continue
        message = json.loads(payload.decode("utf-8"))
        method = message.get("method")
        msg_id = message.get("id")
        session_id = message.get("sessionId")
        params = message.get("params") or {}
        if method == "Target.getTargets":
            send_unmasked(
                sock,
                json.dumps({"id": msg_id, "result": {"targetInfos": infos}}).encode(),
            )
            continue
        if method == "Target.attachToTarget":
            target_id = str(params.get("targetId") or "")
            sid = f"session-{target_id}"
            sessions[sid] = target_id
            send_unmasked(
                sock,
                json.dumps({"id": msg_id, "result": {"sessionId": sid}}).encode(),
            )
            continue
        if method == "Target.detachFromTarget":
            send_unmasked(sock, json.dumps({"id": msg_id, "result": {}}).encode())
            continue
        if method == "Target.activateTarget":
            activated.add(str(params.get("targetId") or ""))
            send_unmasked(sock, json.dumps({"id": msg_id, "result": {}}).encode())
            continue
        if method == "Page.captureScreenshot":
            target = sessions.get(str(session_id or ""), "")
            if target != "page-healthy" or target not in activated:
                continue
            send_unmasked(
                sock,
                json.dumps(
                    {
                        "id": msg_id,
                        "sessionId": session_id,
                        "result": {"data": PNG_B64},
                    }
                ).encode(),
            )
            continue
        if method == "Runtime.evaluate":
            target = sessions.get(str(session_id or ""), "")
            if target == "page-decoy" or (mode == "silent" and target == "page-healthy"):
                continue
            if mode == "flood":
                noise = json.dumps(
                    {
                        "method": "Target.targetInfoChanged",
                        "params": {"targetInfo": infos[0]},
                    }
                ).encode()
                for _ in range(40):
                    send_unmasked(sock, noise)
            send_unmasked(
                sock,
                json.dumps(
                    {
                        "id": msg_id,
                        "sessionId": session_id,
                        "result": {
                            "result": {"type": "string", "value": "ok-from-helper"}
                        },
                    }
                ).encode(),
            )
            continue
        send_unmasked(
            sock,
            json.dumps(
                {
                    "id": msg_id,
                    "sessionId": session_id,
                    "error": {"message": f"unknown {method}"},
                }
            ).encode(),
        )


def handle_client(conn: socket.socket, mode: str) -> None:
    conn.settimeout(30)
    try:
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                return
            data += chunk
        header, _, rest = data.partition(b"\r\n\r\n")
        request_line = header.split(b"\r\n", 1)[0].decode("iso-8859-1", "replace")
        if request_line.startswith("GET /json/version"):
            ws = f"ws://127.0.0.1:39382/devtools/browser/test"
            body = json.dumps(
                {"Browser": "Chrome/test", "webSocketDebuggerUrl": ws}
            ).encode()
            conn.sendall(
                b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
                + str(len(body)).encode()
                + b"\r\nConnection: close\r\n\r\n"
                + body
            )
            return
        if b"Upgrade: websocket" in header or b"upgrade: websocket" in header.lower():
            key = ""
            for line in header.split(b"\r\n")[1:]:
                if line.lower().startswith(b"sec-websocket-key:"):
                    key = line.split(b":", 1)[1].strip().decode("ascii")
            upgrade = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept_key(key)}\r\n"
                "\r\n"
            )
            conn.sendall(upgrade.encode("ascii"))
            handle_ws(conn, mode, rest)
            return
        conn.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
    except (ConnectionError, TimeoutError, OSError, json.JSONDecodeError):
        return
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main() -> int:
    port = int(sys.argv[1])
    mode = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("CDP_STUB_MODE", "default")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(8)
    try:
        while True:
            conn, _addr = server.accept()
            thread = threading.Thread(target=handle_client, args=(conn, mode), daemon=True)
            thread.start()
    finally:
        server.close()


if __name__ == "__main__":
    raise SystemExit(main())
