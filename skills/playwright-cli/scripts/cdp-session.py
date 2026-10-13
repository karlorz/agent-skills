#!/usr/bin/env python3
"""Browser-level CDP list/eval/screenshot. Python 3 stdlib only.

Does not use Playwright, connectOverCDP, or page.title(). Attaches one chosen
target with flatten=true and a monotonic total deadline.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time
from typing import Any
from urllib.parse import urlparse

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
DEFAULT_TIMEOUT_MS = 8_000
DEFAULT_PORT = 9222


class HelperError(Exception):
    def __init__(self, message: str, exit_code: int = 1, payload: dict[str, Any] | None = None) -> None:
        super().__init__(message)
        self.exit_code = exit_code
        self.payload = payload or {}


class Deadline:
    def __init__(self, timeout_ms: int) -> None:
        self.end = time.monotonic() + max(timeout_ms, 1) / 1000.0

    def remaining(self) -> float:
        left = self.end - time.monotonic()
        if left <= 0:
            raise HelperError("CDP action timed out", 1)
        return left


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Raw CDP list/eval/screenshot (stdlib only)")
    parser.add_argument("action", nargs="?", choices=["list", "eval", "screenshot"])
    parser.add_argument("--action", dest="action_flag", choices=["list", "eval", "screenshot"])
    parser.add_argument("--port", type=int, default=int(os.environ.get("CHROME_DEBUG_PORT", DEFAULT_PORT)))
    parser.add_argument("--timeout-ms", type=int, default=DEFAULT_TIMEOUT_MS)
    parser.add_argument("--url-contains", default="")
    parser.add_argument("--target-id", default="")
    parser.add_argument("--eval", dest="expression", default="")
    parser.add_argument("--out", default="")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    action = args.action_flag or args.action
    if args.action_flag and args.action and args.action_flag != args.action:
        parser.error("--action conflicts with positional action")
    if not action:
        parser.error("action is required (list, eval, or screenshot)")
    args.resolved_action = action
    return args


def emit(ok: bool, payload: dict[str, Any], as_json: bool, stream: Any = None) -> None:
    out = stream or (sys.stdout if as_json or ok else sys.stderr)
    body = {"ok": ok, **payload}
    json.dump(body, out, separators=(",", ":"))
    out.write("\n")


def http_json(url: str, timeout: float) -> Any:
    import urllib.error
    import urllib.request

    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        raise HelperError(f"Failed to read {url}: {exc}") from exc


def ws_accept_header(key: str) -> str:
    digest = hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def rewrite_ws_url(advertised: str, port: int) -> str:
    parsed = urlparse(advertised)
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"
    return f"ws://127.0.0.1:{port}{path}"


def browser_ws_url(port: int, timeout: float) -> str:
    version = http_json(f"http://127.0.0.1:{port}/json/version", timeout)
    ws_url = version.get("webSocketDebuggerUrl") if isinstance(version, dict) else None
    if not isinstance(ws_url, str) or not ws_url:
        raise HelperError("CDP version payload missing webSocketDebuggerUrl")
    return rewrite_ws_url(ws_url, port)


class ChromeWebSocket:
    def __init__(self, url: str, deadline: Deadline) -> None:
        parsed = urlparse(url)
        if parsed.scheme not in {"ws", "http"}:
            raise HelperError(f"Unsupported CDP websocket URL: {url}")
        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or 80
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"
        timeout = deadline.remaining()
        self._deadline = deadline
        try:
            self._sock = socket.create_connection((host, port), timeout=timeout)
            self._sock.settimeout(timeout)
        except TimeoutError as exc:
            raise HelperError("CDP action timed out", 1) from exc
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        self._sock.sendall(request.encode("ascii"))
        self._buffer = bytearray()
        header = self._read_until(b"\r\n\r\n")
        status = header.split(b"\r\n", 1)[0]
        if b"101" not in status:
            raise HelperError(
                f"CDP websocket upgrade failed: {status.decode('iso-8859-1', 'replace')}"
            )
        accept = None
        for line in header.split(b"\r\n")[1:]:
            if b":" not in line:
                continue
            name, value = line.split(b":", 1)
            if name.strip().lower() == b"sec-websocket-accept":
                accept = value.strip().decode("ascii", "replace")
                break
        expected = ws_accept_header(key)
        if accept != expected:
            raise HelperError("CDP websocket accept mismatch")
        self._next_id = 1

    def close(self) -> None:
        try:
            self._sock.close()
        except OSError:
            pass

    def call(
        self,
        method: str,
        params: dict[str, Any] | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        message_id = self._next_id
        self._next_id += 1
        payload: dict[str, Any] = {"id": message_id, "method": method}
        if params:
            payload["params"] = params
        if session_id:
            payload["sessionId"] = session_id
        self._send_text(json.dumps(payload, separators=(",", ":")))
        while True:
            incoming = json.loads(self._recv_text())
            if incoming.get("id") != message_id:
                continue
            if session_id and incoming.get("sessionId") not in (None, session_id):
                continue
            if "error" in incoming:
                error = incoming["error"]
                if isinstance(error, dict):
                    text = str(error.get("message") or error)
                else:
                    text = str(error)
                raise HelperError(f"{method} failed: {text}")
            result = incoming.get("result")
            return result if isinstance(result, dict) else {}

    def _arm(self) -> None:
        self._sock.settimeout(self._deadline.remaining())

    def _read_until(self, marker: bytes) -> bytes:
        while marker not in self._buffer:
            self._arm()
            try:
                chunk = self._sock.recv(4096)
            except TimeoutError as exc:
                raise HelperError("CDP action timed out", 1) from exc
            if not chunk:
                raise HelperError("CDP websocket closed during HTTP upgrade")
            self._buffer.extend(chunk)
        idx = self._buffer.find(marker)
        header = bytes(self._buffer[:idx])
        del self._buffer[: idx + len(marker)]
        return header

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        header = bytearray([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        mask = os.urandom(4)
        header.extend(mask)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self._arm()
        self._sock.sendall(bytes(header) + masked)

    def _send_text(self, message: str) -> None:
        self._send_frame(0x1, message.encode("utf-8"))

    def _recv_text(self) -> str:
        chunks: list[bytes] = []
        started = False
        while True:
            payload, opcode, fin = self._recv_frame()
            if opcode == 0x8:
                raise HelperError("CDP websocket closed")
            if opcode == 0x9:
                self._send_pong(payload)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x1:
                if started:
                    raise HelperError("CDP websocket interleaved text frames")
                started = True
                chunks.append(payload)
            elif opcode == 0x0:
                if not started:
                    raise HelperError("CDP websocket continuation without start")
                chunks.append(payload)
            else:
                continue
            if fin:
                return b"".join(chunks).decode("utf-8")

    def _send_pong(self, payload: bytes) -> None:
        self._send_frame(0xA, payload)

    def _recv_frame(self) -> tuple[bytes, int, bool]:
        header = self._recv_exact(2)
        fin = bool(header[0] & 0x80)
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(8))[0]
        mask = self._recv_exact(4) if masked else b""
        payload = self._recv_exact(length)
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return payload, opcode, fin

    def _recv_exact(self, size: int) -> bytes:
        while len(self._buffer) < size:
            self._arm()
            try:
                chunk = self._sock.recv(max(size - len(self._buffer), 4096))
            except TimeoutError as exc:
                raise HelperError("CDP action timed out", 1) from exc
            if not chunk:
                raise HelperError("CDP websocket closed while reading a frame")
            self._buffer.extend(chunk)
        data = bytes(self._buffer[:size])
        del self._buffer[:size]
        return data


def summarize_targets(target_infos: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for item in target_infos:
        if not isinstance(item, dict):
            continue
        rows.append(
            {
                "targetId": str(item.get("targetId") or item.get("id") or ""),
                "type": str(item.get("type") or ""),
                "url": str(item.get("url") or ""),
                "title": str(item.get("title") or ""),
            }
        )
    return rows


def select_target(pages: list[dict[str, Any]], url_contains: str, target_id: str) -> dict[str, Any]:
    if url_contains and target_id:
        raise HelperError("pass only one of --url-contains or --target-id", 2, {"targets": pages})
    if not url_contains and not target_id:
        raise HelperError(
            "eval/screenshot require --url-contains or --target-id",
            2,
            {"targets": pages},
        )
    if target_id:
        matches = [item for item in pages if item["targetId"] == target_id]
        if len(matches) != 1:
            raise HelperError(
                f"--target-id matched {len(matches)} page target(s)",
                2,
                {"targets": pages},
            )
        return matches[0]
    if not url_contains.strip():
        raise HelperError("--url-contains is empty", 2, {"targets": pages})
    matches = [item for item in pages if url_contains in item["url"]]
    if len(matches) != 1:
        raise HelperError(
            f"--url-contains={url_contains!r} matched {len(matches)} page target(s)",
            2,
            {"targets": pages},
        )
    return matches[0]


def get_target_infos(ws: ChromeWebSocket) -> list[dict[str, Any]]:
    result = ws.call("Target.getTargets")
    infos = result.get("targetInfos")
    if not isinstance(infos, list):
        return []
    return [item for item in infos if isinstance(item, dict)]


def attach_session(ws: ChromeWebSocket, target_id: str) -> str:
    result = ws.call("Target.attachToTarget", {"targetId": target_id, "flatten": True})
    session_id = result.get("sessionId")
    if not isinstance(session_id, str) or not session_id:
        raise HelperError("Target.attachToTarget did not return sessionId")
    return session_id


def detach_session(ws: ChromeWebSocket, session_id: str) -> None:
    try:
        ws.call("Target.detachFromTarget", {"sessionId": session_id})
    except HelperError:
        pass


def run_eval(ws: ChromeWebSocket, session_id: str, expression: str) -> Any:
    result = ws.call(
        "Runtime.evaluate",
        {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True,
        },
        session_id=session_id,
    )
    if result.get("exceptionDetails"):
        details = result["exceptionDetails"]
        text = ""
        if isinstance(details, dict):
            text = str(details.get("text") or details.get("exception") or details)
        raise HelperError(f"Runtime.evaluate exception: {text}")
    inner = result.get("result")
    if isinstance(inner, dict) and "value" in inner:
        return inner["value"]
    return inner


def run_screenshot_safe(ws: ChromeWebSocket, session_id: str, out_path: str) -> str:
    import binascii

    # Do not Page.enable first: some Chrome builds never reply, and a swallowed
    # timeout would spend the shared monotonic deadline then fail the capture.
    # Do not set fromSurface: some cmux Chrome sessions hang on that flag.
    result = ws.call("Page.captureScreenshot", {"format": "png"}, session_id=session_id)
    data = result.get("data")
    if not isinstance(data, str) or not data:
        raise HelperError("Page.captureScreenshot returned no data")
    try:
        raw = base64.b64decode(data, validate=False)
    except (ValueError, binascii.Error) as exc:
        raise HelperError(f"screenshot was not base64: {exc}") from exc
    if len(raw) < 8 or raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise HelperError("screenshot was not a PNG")
    directory = os.path.dirname(os.path.abspath(out_path))
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp_path = f"{out_path}.tmp.{os.getpid()}"
    try:
        with open(tmp_path, "wb") as handle:
            handle.write(raw)
        os.replace(tmp_path, out_path)
    except OSError as exc:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise HelperError(f"failed to write screenshot: {exc}") from exc
    return os.path.abspath(out_path)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    as_json = bool(args.json)
    try:
        if args.resolved_action == "eval" and not str(args.expression).strip():
            raise HelperError("--eval is required for eval", 2)
        if args.resolved_action == "screenshot" and not str(args.out).strip():
            raise HelperError("--out is required for screenshot", 2)
        deadline = Deadline(args.timeout_ms)
        ws_url = browser_ws_url(args.port, deadline.remaining())
        ws = ChromeWebSocket(ws_url, deadline)
        session_id: str | None = None
        try:
            infos = get_target_infos(ws)
            summary = summarize_targets(infos)
            if args.resolved_action == "list":
                emit(True, {"targets": summary}, True)
                return 0
            pages = [item for item in summary if item["type"] == "page"]
            selected = select_target(pages, args.url_contains, args.target_id)
            session_id = attach_session(ws, selected["targetId"])
            if args.resolved_action == "eval":
                value = run_eval(ws, session_id, args.expression)
                emit(True, {"result": value, "targetId": selected["targetId"]}, True)
                return 0
            try:
                ws.call("Target.activateTarget", {"targetId": selected["targetId"]})
            except HelperError as exc:
                if "timed out" in str(exc).lower():
                    raise
            path = run_screenshot_safe(ws, session_id, args.out)
            emit(True, {"path": path, "targetId": selected["targetId"]}, True)
            return 0
        finally:
            if session_id:
                detach_session(ws, session_id)
            ws.close()
    except HelperError as exc:
        payload = {"error": str(exc), **exc.payload}
        emit(False, payload, as_json)
        return exc.exit_code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        raise SystemExit(1)
