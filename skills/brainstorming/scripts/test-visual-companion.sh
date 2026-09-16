#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_ROOT="$ROOT/skills/brainstorming"
START="$SKILL_ROOT/scripts/start-server.sh"
STOP="$SKILL_ROOT/scripts/stop-server.sh"
PLUGIN_MANIFEST="$ROOT/.codex-plugin/plugin.json"

command -v node >/dev/null 2>&1 || { echo "node is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

expected_version="$(jq -r '.version' "$PLUGIN_MANIFEST")"
[[ -n "$expected_version" && "$expected_version" != "null" ]]

tmp="$(mktemp -d)"
project="$tmp/project"
mkdir -p "$project"
session_dir=""

on_error() {
  local line="$1"
  echo "test-visual-companion: failed at line $line" >&2
  sed -n "${line}p" "${BASH_SOURCE[0]}" >&2 || true
  if [[ -n "$session_dir" && -f "$session_dir/state/server.log" ]]; then
    echo "--- server.log ---" >&2
    sed -n '1,240p' "$session_dir/state/server.log" >&2 || true
  fi
}

cleanup() {
  if [[ -n "$session_dir" && -d "$session_dir" ]]; then
    bash "$STOP" "$session_dir" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap 'on_error "$LINENO"' ERR
trap cleanup EXIT

unset BRAINSTORM_ENABLE_TELEMETRY
start_json="$(bash "$START" \
  --project-dir "$project" \
  --work-id visual-companion-smoke \
  --idle-timeout-minutes 1 \
  --background)"

[[ "$(jq -r '.type' <<<"$start_json")" == "server-started" ]]
url="$(jq -r '.url' <<<"$start_json")"
screen_dir="$(jq -r '.screen_dir' <<<"$start_json")"
state_dir="$(jq -r '.state_dir' <<<"$start_json")"
port="$(jq -r '.port' <<<"$start_json")"
session_dir="$(dirname "$state_dir")"

[[ "$screen_dir" == "$project/.superpowers/sdd/visual-companion-smoke/brainstorm/"*"/content" ]]
[[ "$state_dir" == "$project/.superpowers/sdd/visual-companion-smoke/brainstorm/"*"/state" ]]
[[ -f "$state_dir/server-info" ]]
[[ "$url" == *"?key="* ]]

base_url="${url%%\?*}"
unauthorized_code="$(curl -sS -o "$tmp/forbidden.html" -w '%{http_code}' "$base_url")"
[[ "$unauthorized_code" == "403" ]]
grep -Fq 'Session key required' "$tmp/forbidden.html"

curl -sS -c "$tmp/cookies" "$url" > "$tmp/bootstrap.html"
grep -Fq 'brainstorm-session-key' "$tmp/bootstrap.html"

printf '%s\n' \
  '<h2>Visual companion smoke test</h2>' \
  '<div class="options">' \
  '  <div class="option" data-choice="a" onclick="toggleSelect(this)"><h3>Option A</h3></div>' \
  '</div>' > "$screen_dir/smoke.html"
for _ in {1..30}; do
  curl -sS -b "$tmp/cookies" "$base_url" > "$tmp/screen.html"
  grep -Fq 'Visual companion smoke test' "$tmp/screen.html" && break
  sleep 0.1
done
grep -Fq 'Visual companion smoke test' "$tmp/screen.html"
grep -Fq "Brainstorming Companion v$expected_version" "$tmp/screen.html"
grep -Fq 'toggleSelect' "$tmp/screen.html"
if grep -Fq 'primeradiant.com' "$tmp/screen.html"; then
  echo "external branding must be disabled by default" >&2
  exit 1
fi

node - "$url" <<'NODE'
const crypto = require('crypto');
const net = require('net');

const target = new URL(process.argv[2]);
const clientKey = crypto.randomBytes(16).toString('base64');
const payload = Buffer.from(JSON.stringify({
  type: 'click',
  choice: 'a',
  text: 'Option A',
  timestamp: Date.now()
}));
const mask = crypto.randomBytes(4);
const frame = Buffer.alloc(2 + 4 + payload.length);
frame[0] = 0x81;
frame[1] = 0x80 | payload.length;
mask.copy(frame, 2);
for (let i = 0; i < payload.length; i++) frame[6 + i] = payload[i] ^ mask[i % 4];

const socket = net.createConnection({ host: '127.0.0.1', port: Number(target.port) });
let response = '';
socket.on('connect', () => {
  socket.write(
    `GET ${target.pathname}${target.search} HTTP/1.1\r\n` +
    `Host: localhost:${target.port}\r\n` +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Key: ${clientKey}\r\n` +
    'Sec-WebSocket-Version: 13\r\n\r\n'
  );
});
socket.on('data', chunk => {
  response += chunk.toString('latin1');
  if (response.includes('\r\n\r\n')) {
    if (!response.startsWith('HTTP/1.1 101')) process.exit(2);
    socket.write(frame, () => {
      setTimeout(() => {
        socket.destroy();
        process.exit(0);
      }, 100);
    });
  }
});
socket.on('error', err => { console.error(err); process.exit(3); });
socket.on('close', () => process.exit(0));
setTimeout(() => { console.error('websocket smoke timeout'); process.exit(4); }, 5000).unref();
NODE

for _ in {1..30}; do
  [[ -f "$state_dir/events" ]] && break
  sleep 0.1
done
grep -Fq '"choice":"a"' "$state_dir/events"

stop_json="$(bash "$STOP" "$session_dir")"
[[ "$(jq -r '.status' <<<"$stop_json")" == "stopped" ]]
[[ -f "$state_dir/server-stopped" ]]

session_dir=""
printf 'test-visual-companion: ok\n'
