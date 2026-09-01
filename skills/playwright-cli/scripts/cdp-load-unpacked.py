#!/usr/bin/env python3
"""Load unpacked Chrome extensions over CDP. Python 3 stdlib only."""
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
import urllib.error
import urllib.request
from typing import Any
from urllib.parse import urlparse

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
DEFAULT_TIMEOUT_MS = 20_000


class HelperError(Exception):
    def __init__(self, message: str, exit_code: int = 1) -> None:
        super().__init__(message)
        self.exit_code = exit_code


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="CDP Extensions.loadUnpacked helper (stdlib only)"
    )
    parser.add_argument("--port", type=int, default=9222)
    parser.add_argument("--path", action="append", default=[], dest="paths")
    parser.add_argument("--reload-http", action="store_true")
    parser.add_argument("--timeout-ms", type=int, default=DEFAULT_TIMEOUT_MS)
    parser.add_argument("--retries", type=int, default=8)
    parser.add_argument("--retry-delay-ms", type=int, default=400)
    return parser.parse_args(argv)


def resolve_unpacked_dir(raw: str) -> str:
    path = os.path.abspath(os.path.expanduser(raw))
    if not os.path.isdir(path):
        raise HelperError(f"Unpacked extension path does not exist: {path}", 2)
    manifest = os.path.join(path, "manifest.json")
    if not os.path.isfile(manifest):
        raise HelperError(f"Unpacked extension path has no manifest.json: {path}", 2)
    return os.path.realpath(path)


def http_json(url: str, timeout: float) -> Any:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def ws_accept_header(key: str) -> str:
    digest = hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


class ChromeWebSocket:
    def __init__(self, url: str, timeout: float) -> None:
        parsed = urlparse(url)
        if parsed.scheme not in {"ws", "http"}:
            raise HelperError(f"Unsupported CDP websocket URL: {url}")
        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or 80
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"
        self._sock = socket.create_connection((host, port), timeout=timeout)
        self._sock.settimeout(timeout)
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
        header = self._read_until(b"\r\n\r\n")
        status = header.split(b"\r\n", 1)[0]
        if b"101" not in status:
            raise HelperError(f"CDP websocket upgrade failed: {status.decode('iso-8859-1', 'replace')}")
        self._buffer = b""
        self._next_id = 1

    def close(self) -> None:
        try:
            self._sock.close()
        except OSError:
            pass

    def call(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        message_id = self._next_id
        self._next_id += 1
        payload: dict[str, Any] = {"id": message_id, "method": method}
        if params:
            payload["params"] = params
        self._send_text(json.dumps(payload, separators=(",", ":")))
        while True:
            incoming = json.loads(self._recv_text())
            if incoming.get("id") != message_id:
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

    def _read_until(self, marker: bytes) -> bytes:
        data = b""
        while marker not in data:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise HelperError("CDP websocket closed during HTTP upgrade")
            data += chunk
        header, _, rest = data.partition(marker)
        self._buffer = rest
        return header

    def _send_text(self, message: str) -> None:
        payload = message.encode("utf-8")
        header = bytearray([0x81])
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
        self._sock.sendall(bytes(header) + masked)

    def _recv_text(self) -> str:
        while True:
            payload, opcode = self._recv_frame()
            if opcode == 0x8:
                raise HelperError("CDP websocket closed")
            if opcode == 0x1:
                return payload.decode("utf-8")
            if opcode == 0x9:
                # ping -> pong
                self._send_pong(payload)
                continue

    def _send_pong(self, payload: bytes) -> None:
        header = bytearray([0x8A])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        else:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        mask = os.urandom(4)
        header.extend(mask)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self._sock.sendall(bytes(header) + masked)

    def _recv_frame(self) -> tuple[bytes, int]:
        header = self._recv_exact(2)
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
        return payload, opcode

    def _recv_exact(self, size: int) -> bytes:
        while len(self._buffer) < size:
            chunk = self._sock.recv(max(size - len(self._buffer), 4096))
            if not chunk:
                raise HelperError("CDP websocket closed while reading a frame")
            self._buffer += chunk
        data, self._buffer = self._buffer[:size], self._buffer[size:]
        return data


def already_loaded(extensions: list[dict[str, Any]], path: str) -> str | None:
    real = os.path.realpath(path)
    for item in extensions:
        item_path = item.get("path")
        if isinstance(item_path, str) and os.path.realpath(item_path) == real:
            if item.get("enabled", True) is False:
                continue
            ext_id = item.get("id")
            return str(ext_id) if ext_id else ""
    return None


def is_already_loaded_error(message: str) -> bool:
    lowered = message.lower()
    return "already" in lowered and ("load" in lowered or "install" in lowered or "exist" in lowered)


def load_one(ws: ChromeWebSocket, path: str) -> dict[str, str]:
    listing = ws.call("Extensions.getExtensions")
    extensions = listing.get("extensions")
    if not isinstance(extensions, list):
        extensions = []
    existing = already_loaded(extensions, path)
    if existing is not None:
        return {"path": path, "id": existing, "status": "already"}
    try:
        result = ws.call("Extensions.loadUnpacked", {"path": path})
    except HelperError as exc:
        if is_already_loaded_error(str(exc)):
            return {"path": path, "id": "", "status": "already"}
        raise
    ext_id = result.get("id")
    return {"path": path, "id": str(ext_id) if ext_id else "", "status": "loaded"}


def browser_ws_url(port: int, timeout: float) -> str:
    try:
        version = http_json(f"http://127.0.0.1:{port}/json/version", timeout)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        raise HelperError(f"Failed to read CDP version on port {port}: {exc}") from exc
    ws_url = version.get("webSocketDebuggerUrl") if isinstance(version, dict) else None
    if not isinstance(ws_url, str) or not ws_url:
        raise HelperError("CDP version payload missing webSocketDebuggerUrl")
    return ws_url


def extensions_cover_paths(extensions: list[dict[str, Any]], paths: list[str]) -> bool:
    for path in paths:
        if already_loaded(extensions, path) is None:
            return False
    return True


def load_paths_with_retry(
    port: int,
    paths: list[str],
    timeout: float,
    retries: int,
    retry_delay_ms: int,
) -> list[dict[str, str]]:
    last_error: HelperError | None = None
    attempts = max(retries, 1)
    delay = max(retry_delay_ms, 0) / 1000.0
    for attempt in range(attempts):
        try:
            ws = ChromeWebSocket(browser_ws_url(port, timeout), timeout)
            loaded: list[dict[str, str]] = []
            try:
                for path in paths:
                    loaded.append(load_one(ws, path))
            finally:
                ws.close()
            verify = ChromeWebSocket(browser_ws_url(port, timeout), timeout)
            try:
                listing = verify.call("Extensions.getExtensions")
            finally:
                verify.close()
            extensions = listing.get("extensions")
            if not isinstance(extensions, list):
                extensions = []
            if not extensions_cover_paths(extensions, paths):
                raise HelperError("Extensions.getExtensions did not include loaded unpacked path(s)")
            return loaded
        except HelperError as exc:
            last_error = exc
            if attempt + 1 < attempts and delay:
                time.sleep(delay)
    assert last_error is not None
    raise last_error


def reload_http_pages(port: int, timeout: float) -> list[str]:
    try:
        targets = http_json(f"http://127.0.0.1:{port}/json/list", timeout)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        raise HelperError(f"Failed to list CDP targets: {exc}") from exc
    if not isinstance(targets, list):
        return []
    reloaded: list[str] = []
    for target in targets:
        if not isinstance(target, dict):
            continue
        if target.get("type") != "page":
            continue
        url = target.get("url")
        ws_url = target.get("webSocketDebuggerUrl")
        if not isinstance(url, str) or not isinstance(ws_url, str):
            continue
        if not (url.startswith("http://") or url.startswith("https://")):
            continue
        page = ChromeWebSocket(ws_url, timeout)
        try:
            page.call("Page.reload", {"ignoreCache": True})
            reloaded.append(url)
        finally:
            page.close()
    return reloaded


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        paths: list[str] = []
        seen: set[str] = set()
        for raw in args.paths:
            resolved = resolve_unpacked_dir(raw)
            if resolved in seen:
                continue
            seen.add(resolved)
            paths.append(resolved)
        if not paths:
            raise HelperError("at least one --path is required", 2)
        timeout = max(args.timeout_ms, 1) / 1000.0
        loaded = load_paths_with_retry(
            args.port,
            paths,
            timeout,
            args.retries,
            args.retry_delay_ms,
        )
        reloaded: list[str] = []
        if args.reload_http:
            try:
                reloaded = reload_http_pages(args.port, timeout)
            except HelperError:
                reloaded = []
        json.dump(
            {"ok": True, "loaded": loaded, "reloaded": reloaded},
            sys.stdout,
            separators=(",", ":"),
        )
        sys.stdout.write("\n")
        return 0
    except HelperError as exc:
        json.dump({"ok": False, "error": str(exc)}, sys.stderr)
        sys.stderr.write("\n")
        return exc.exit_code


if __name__ == "__main__":
    sys.exit(main())
