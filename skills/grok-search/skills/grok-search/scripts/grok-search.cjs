#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');
const http = require('http');
const crypto = require('crypto');
const net = require('net');

const DEFAULT_ORIGIN = 'https://search.karldigi.dev';
const MCP_PATH = '/mcp';
const REST_API_PREFIX = '/api/v1';
const MCP_PROTOCOL_VERSION = '2025-03-26';
const CLIENT_INFO = { name: 'grok-search-cli', version: '0.1.24' };

const REQUEST_TIMEOUT_MS = 30000;
const OVERALL_TIMEOUT_MS = 60000;
const MAX_RESPONSE_BYTES = 10 * 1024 * 1024; // 10MB limit

let activeTransport = null;
const activeRequests = new Set();

function setTransport(fn) {
  activeTransport = fn;
}

function resolveConfigDir() {
  const home = process.env.HOME || os.homedir();
  return path.join(home, '.config', 'grok-search');
}

function checkSafePath(targetPath) {
  let stat;
  try { stat = fs.lstatSync(targetPath); } catch (err) {
    if (err.code === 'ENOENT') return null;
    throw err;
  }
  if (stat.isSymbolicLink()) throw new Error('symlink_rejected: Credential paths must not be symbolic links');
  if (process.platform !== 'win32' && stat.uid !== process.getuid()) {
    throw new Error('unsafe_owner: Credential paths must be owned by the current user');
  }
  return stat;
}

function ensureConfigDir() {
  if (process.platform === 'win32') throw new Error('secure_storage_unavailable: Use an environment token; POSIX storage is required for hosted auth');
  const dir = resolveConfigDir();
  const parent = path.dirname(dir);
  for (const target of [parent, dir]) {
    const stat = checkSafePath(target);
    if (stat && !stat.isDirectory()) throw new Error('unsafe_path: Expected a credential directory');
    if (!stat) fs.mkdirSync(target, { mode: 0o700 });
  }
  const stat = fs.statSync(dir);
  if (stat.mode & 0o077) fs.chmodSync(dir, 0o700);
  return dir;
}

function readPrivateFile(targetPath) {
  ensureConfigDir();
  const stat = checkSafePath(targetPath);
  if (!stat) return null;
  if (!stat.isFile() || stat.size > 65536) throw new Error('unsafe_file: Invalid credential file');
  const fd = fs.openSync(targetPath, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  try {
    const actual = fs.fstatSync(fd);
    if (actual.uid !== process.getuid() || !actual.isFile() || actual.size > 65536) throw new Error('unsafe_file');
    if (actual.mode & 0o077) fs.fchmodSync(fd, 0o600);
    return fs.readFileSync(fd, 'utf8');
  } finally { fs.closeSync(fd); }
}

function atomicWriteFile(targetPath, content, mode = 0o600) {
  ensureConfigDir();
  const old = checkSafePath(targetPath);
  if (old && !old.isFile()) throw new Error('unsafe_file');
  const tmpPath = path.join(path.dirname(targetPath), `.tmp-${crypto.randomBytes(16).toString('hex')}`);
  let fd;
  try {
    fd = fs.openSync(tmpPath, 'wx', mode);
    fs.writeFileSync(fd, content, { encoding: 'utf8' });
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    fd = undefined;
    checkSafePath(targetPath);
    fs.renameSync(tmpPath, targetPath);
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
    try { fs.unlinkSync(tmpPath); } catch (err) { if (err.code !== 'ENOENT') throw err; }
  }
}

async function withAuthLock(action) {
  const dir = ensureConfigDir();
  const lockPath = path.join(dir, 'cli-auth.lock');
  checkSafePath(lockPath);
  let fd;
  try { fd = fs.openSync(lockPath, 'wx', 0o600); } catch (err) {
    outputError('concurrent_auth_start', 'Another auth command holds the lock. Retry after it exits; remove a stale lock only after verifying that process has stopped.');
  }
  try {
    fs.writeFileSync(fd, String(process.pid));
    return await action();
  } finally {
    fs.closeSync(fd);
    fs.unlinkSync(lockPath);
  }
}

function readPendingState() {
  const raw = readPrivateFile(path.join(resolveConfigDir(), 'cli-auth.json'));
  if (raw === null) return null;
  let state;
  try { state = JSON.parse(raw); } catch (_) { outputError('corrupted_auth_state', 'Invalid private auth state; start a new approval after removing this file.'); }
  if (state.origin !== DEFAULT_ORIGIN || typeof state.authRunId !== 'string' || !state.authRunId || state.authRunId.length > 256 ||
      typeof state.pollSecret !== 'string' || !state.pollSecret || state.pollSecret.length > 512 || !Number.isFinite(Date.parse(state.expiresAt))) {
    outputError('corrupted_auth_state', 'Private auth state has invalid fields or origin.');
  }
  return state;
}

function withInviteQuery(approveUrl, inviteCode) {
  if (!inviteCode || !approveUrl) {
    return approveUrl;
  }
  try {
    const parsed = new URL(approveUrl);
    if (!parsed.searchParams.get('invite')) {
      parsed.searchParams.set('invite', inviteCode);
    }
    return parsed.toString();
  } catch (_) {
    return approveUrl;
  }
}

function getTokenResolution() {
  const envToken = process.env.GROK_SEARCH_MCP_TOKEN;
  if (envToken && envToken.trim()) {
    return { token: envToken.trim(), source: 'env' };
  }
  const configDir = resolveConfigDir();
  const tokenFile = path.join(configDir, 'http-mcp.token');
  const raw = readPrivateFile(tokenFile);
  if (raw && raw.trim()) {
    const metaRaw = readPrivateFile(path.join(configDir, 'token-meta.json'));
    if (metaRaw) {
      let meta;
      try { meta = JSON.parse(metaRaw); } catch (_) { throw new Error('invalid_token_metadata'); }
      if (meta.origin !== DEFAULT_ORIGIN) throw new Error('invalid_token_origin');
      if (meta.expiresAt && (!Number.isFinite(Date.parse(meta.expiresAt)) || Date.parse(meta.expiresAt) <= Date.now())) {
        return { token: null, source: 'expired' };
      }
    }
    return { token: raw.trim(), source: 'file' };
  }
  return { token: null, source: 'none' };
}

class CliExit extends Error {
  constructor(exitCode) { super('EXIT_' + exitCode); this.exitCode = exitCode; }
}

function outputJson(obj, exitCode = 0) {
  process.stdout.write(JSON.stringify(obj) + '\n');
  // Unwind finally blocks before the executable exits (locks/session cleanup).
  throw new CliExit(exitCode);
}

function outputError(code, message, options = {}) {
  const { exitCode = 1, retryable = false, ...extra } = options;
  const payload = {
    ok: false,
    error: {
      code,
      message,
      retryable,
      ...extra,
    },
  };
  outputJson(payload, exitCode);
}

function renderTerminalQr(text) {
  try {
    const { toQR } = require('./lib/toqr.cjs');
    const data = toQR(text);
    const extent = Math.sqrt(data.byteLength) | 0;
    const CHAR_00 = '\u2588';
    const CHAR_10 = '\u2584';
    const CHAR_01 = '\u2580';
    const CHAR_11 = ' ';
    let output = '';
    output += CHAR_10.repeat(extent + 2);
    for (let row = 0; row < extent; row += 2) {
      output += '\n' + CHAR_00;
      for (let col = 0; col < extent; col++) {
        const top = data[row * extent + col];
        const bottom = (row + 1 < extent) ? data[(row + 1) * extent + col] : 0;
        const value = (top << 1) | bottom;
        switch (value) {
          case 0: output += CHAR_00; break;
          case 1: output += CHAR_01; break;
          case 2: output += CHAR_10; break;
          case 3: output += CHAR_11; break;
        }
      }
      output += CHAR_00;
    }
    if (extent % 2 === 0) {
      output += '\n' + CHAR_01.repeat(extent + 2);
    }
    output += '\n';
    return output;
  } catch (err) {
    return null;
  }
}

function validateUserUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || !rawUrl.trim()) {
    throw new Error('invalid_url: Target URL must be a non-empty string');
  }
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch (_) {
    throw new Error('invalid_url: Target URL is not a valid URL');
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error(`invalid_url: Target URL protocol must be http: or https:, got '${parsed.protocol}'`);
  }
  if (parsed.username || parsed.password) {
    throw new Error('invalid_url: Target URL must not contain embedded credentials');
  }
  const hostname = parsed.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (
    hostname === 'localhost' ||
    hostname === '127.0.0.1' ||
    hostname === '::1' ||
    hostname === '0.0.0.0' ||
    hostname.endsWith('.localhost') ||
    hostname.endsWith('.local') ||
    (net.isIP(hostname) === 4 && /^(0|10|127|169\.254|172\.(1[6-9]|2\d|3[01])|192\.168)(\.|$)/.test(hostname)) ||
    (net.isIP(hostname) === 6 && (/^(::|f[cd]|fe[89ab])/.test(hostname)))
  ) {
    throw new Error(`invalid_url: Target URL hostname '${parsed.hostname}' is not permitted`);
  }
  return rawUrl;
}

function handleUnauthorizedToken(tokenSource) {
  if (tokenSource === 'env') {
    outputError('env_token_rejected', 'GROK_SEARCH_MCP_TOKEN environment variable was rejected (401). Update or unset the environment override; a file token cannot supersede it.');
  }
  outputError('auth_required', 'GrokSearch authentication token is invalid or expired. Run auth-start to authenticate.');
}

async function requestRestEndpoint(origin, endpoint, token, tokenSource, bodyObj) {
  const url = `${origin.replace(/\/+$/, '')}${REST_API_PREFIX}/${endpoint}`;
  const authPrefix = 'Bearer' + ' ';
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': authPrefix + token,
  };

  const res = await performHttpRequest(url, { method: 'POST', headers }, JSON.stringify(bodyObj));

  if (res.status === 200) {
    let parsed;
    try {
      parsed = JSON.parse(res.body);
    } catch (err) {
      outputError('invalid_rest_response', 'REST response returned invalid JSON', { exitCode: 1 });
    }
    if (parsed && typeof parsed === 'object' && parsed.ok === true) {
      return { success: true, data: parsed.data };
    }
    if (parsed && typeof parsed === 'object' && parsed.ok === false && parsed.error) {
      outputError('api_error', 'REST API returned an application error', {
        exitCode: 1,
        retryable: !!parsed.error.retryable,
      });
    }
    outputError('invalid_rest_response', 'REST response did not match expected envelope', { exitCode: 1 });
  }

  if (res.status === 401) handleUnauthorizedToken(tokenSource);

  if (res.status === 403) {
    outputError('forbidden', 'Access to REST endpoint was forbidden (403)', { exitCode: 1 });
  }

  if (res.status === 429) {
    outputError('rate_limited', 'Rate limit exceeded (429)', { exitCode: 1, retryable: true });
  }

  if (res.status >= 500) {
    outputError('server_error', `REST endpoint returned server error HTTP ${res.status}`, { exitCode: 1, retryable: true });
  }

  if (res.status === 404) {
    let parsedBody = null;
    try {
      parsedBody = JSON.parse(res.body);
    } catch (_) {}

    if (parsedBody && typeof parsedBody === 'object') {
      if (parsedBody.ok === false && parsedBody.error) {
        outputError('not_found', 'REST API returned an application error', { exitCode: 1 });
      }
      if (parsedBody.error || parsedBody.code) {
        outputError('not_found', 'Resource not found', { exitCode: 1 });
      }
    }

    return { fallbackToMcp: true };
  }

  outputError('rest_request_failed', `REST request failed with HTTP ${res.status}`, { exitCode: 1 });
}

function parseCliArgs(argv) {
  const args = argv.slice(2);
  if (args.length === 0) {
    return { command: null, options: {} };
  }
  const command = args[0];
  const options = {};
  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      if (Object.hasOwn(options, key)) throw new Error('duplicate_option: Each option may appear once');
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        options[key] = args[i + 1];
        i++;
      } else {
        options[key] = true;
      }
    } else {
      throw new Error(`unknown_argument: unexpected positional argument ${arg}`);
    }
  }
  for (const value of Object.values(options)) {
    if (typeof value !== 'string' || !value.trim()) throw new Error('invalid_option: Options require non-empty values');
  }
  return { command, options };
}

function performHttpRequest(reqUrl, reqOptions, body) {
  const serviceUrl = new URL(reqUrl);
  if (serviceUrl.origin !== DEFAULT_ORIGIN || serviceUrl.username || serviceUrl.password) throw new Error('service_origin_rejected');
  if (activeTransport) {
    return activeTransport(reqUrl, reqOptions, body);
  }
  return new Promise((resolve, reject) => {
    const parsed = new URL(reqUrl);
    const isHttps = parsed.protocol === 'https:';
    const lib = isHttps ? https : http;

    const opts = {
      protocol: parsed.protocol,
      hostname: parsed.hostname,
      port: parsed.port || (isHttps ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: reqOptions.method || 'GET',
      headers: reqOptions.headers || {},
      timeout: reqOptions.timeout || REQUEST_TIMEOUT_MS,
    };

    const deadline = setTimeout(() => req.destroy(new Error('request_timeout')), reqOptions.timeout || REQUEST_TIMEOUT_MS);
    const req = lib.request(opts, (res) => {
      let rawData = '';
      let bytesCount = 0;
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        bytesCount += Buffer.byteLength(chunk, 'utf8');
        if (bytesCount > MAX_RESPONSE_BYTES) {
          req.destroy();
          return reject(new Error('response_too_large'));
        }
        rawData += chunk;
      });
      res.on('aborted', () => req.destroy(new Error('response_aborted')));
      res.on('error', () => req.destroy(new Error('response_error')));
      res.on('end', () => {
        clearTimeout(deadline);
        activeRequests.delete(req);
        resolve({
          status: res.statusCode,
          headers: res.headers,
          body: rawData,
        });
      });
    });

    activeRequests.add(req);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('request_timeout'));
    });
    req.on('error', (err) => {
      clearTimeout(deadline);
      activeRequests.delete(req);
      reject(err);
    });

    if (body) {
      req.write(body);
    }
    req.end();
  });
}

function decodeMcpResponse(contentType, text, expectedId) {
  let messages;
  if (contentType && contentType.includes('text/event-stream')) {
    messages = text.split(/\r?\n\r?\n/).map(event => {
      const data = event.split(/\r?\n/).filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
      if (!data) return null;
      return JSON.parse(data);
    }).filter(Boolean);
  } else {
    messages = [JSON.parse(text)];
  }
  const payload = expectedId === undefined ? messages.find(m => m.id !== undefined) : messages.find(m => m.id === expectedId);
  if (!payload || payload.jsonrpc !== '2.0' || (!payload.result && !payload.error)) throw new Error('mcp_response_mismatch');
  return payload;
}

class HiddenMcpClient {
  constructor(origin, token, tokenSource) {
    this.origin = origin.replace(/\/+$/, '');
    this.token = token;
    this.tokenSource = tokenSource;
    this.mcpUrl = `${this.origin}${MCP_PATH}`;
    this.sessionId = null;
    this.nextRequestId = 1;
    this.protocolVersion = MCP_PROTOCOL_VERSION;
  }

  async postMcp(bodyObj, headers = {}) {
    const reqHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': this.protocolVersion,
      'Authorization': `Bearer ${this.token}`,
      ...headers,
    };
    if (this.sessionId) {
      reqHeaders['Mcp-Session-Id'] = this.sessionId;
    }

    const payload = JSON.stringify(bodyObj);
    const res = await performHttpRequest(this.mcpUrl, { method: 'POST', headers: reqHeaders }, payload);

    if (res.status === 401) handleUnauthorizedToken(this.tokenSource);

    if (res.status === 404 && this.sessionId && bodyObj.method === 'tools/call') throw new Error('mcp_session_expired');

    if (res.status === 202 && bodyObj.id === undefined) {
      return { status: 202, payload: null };
    }

    if (res.status < 200 || res.status >= 300) {
      outputError(
        'transport_error',
        `MCP request failed with HTTP ${res.status}`,
        { exitCode: 1, status: res.status, retryable: res.status >= 500 }
      );
    }

    const newSession = res.headers['mcp-session-id'];
    if (newSession) {
      this.sessionId = newSession;
    }

    try {
      const decoded = decodeMcpResponse(res.headers['content-type'], res.body, bodyObj.id);
      return { status: res.status, payload: decoded };
    } catch (err) {
      outputError('invalid_mcp_response', 'Invalid or mismatched MCP JSON/SSE response', { exitCode: 1 });
    }
  }

  async initialize() {
    const initBody = {
      jsonrpc: '2.0',
      id: this.nextRequestId++,
      method: 'initialize',
      params: {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: CLIENT_INFO,
      },
    };

    const res = await this.postMcp(initBody);
    const payload = res.payload;
    if (payload.error) {
      outputError('mcp_initialize_failed', 'MCP initialize failed', {
        exitCode: 1,
        rpcCode: payload.error.code,
      });
    }

    if (!payload || !payload.result || payload.result.protocolVersion !== MCP_PROTOCOL_VERSION ||
        !payload.result.capabilities || !payload.result.capabilities.tools || typeof payload.result.capabilities.tools !== 'object' || Array.isArray(payload.result.capabilities.tools)) {
      outputError('unsupported_mcp_protocol', 'Server did not negotiate the supported MCP tool protocol.');
    }
    this.protocolVersion = payload.result.protocolVersion;

    const notifBody = {
      jsonrpc: '2.0',
      method: 'notifications/initialized',
      params: {},
    };
    await this.postMcp(notifBody);
  }

  async close() {
    if (!this.sessionId) return;
    try {
      await performHttpRequest(this.mcpUrl, { method: 'DELETE', timeout: 1000, headers: {
        Authorization: `Bearer ${this.token}`, 'Mcp-Session-Id': this.sessionId, 'MCP-Protocol-Version': this.protocolVersion,
      }});
    } catch (_) { /* Cleanup never replays a tool or changes its outcome. */ }
    this.sessionId = null;
  }

  async callTool(name, args, reinitialized = false) {
    if (!['web_search', 'get_sources', 'web_fetch', 'web_map'].includes(name)) throw new Error('unsupported_tool');
    const reqBody = {
      jsonrpc: '2.0',
      id: this.nextRequestId++,
      method: 'tools/call',
      params: {
        name,
        arguments: args,
      },
    };

    let res;
    try { res = await this.postMcp(reqBody); } catch (err) {
      if (err.message !== 'mcp_session_expired' || reinitialized) throw err;
      this.sessionId = null;
      await this.initialize();
      return this.callTool(name, args, true);
    }
    const payload = res.payload;
    if (payload.error) {
      outputError('tool_call_error', 'MCP tool call failed', {
        exitCode: 1,
        tool: name,
        rpcCode: payload.error.code,
      });
    }

    const result = payload.result || {};
    if (result.isError) {
      outputError('tool_error', 'MCP tool reported failure', { exitCode: 1, tool: name });
    }
    if (result.structuredContent !== undefined) {
      const structured = result.structuredContent;
      if (name === 'web_fetch' || name === 'web_map') {
        const text = typeof structured === 'string' ? structured : structured?.result ?? structured?.content;
        if (typeof text !== 'string') outputError('invalid_tool_result', 'Expected text from the requested tool.');
        return text;
      }
      return structured;
    }

    let parsed = null;
    if (Array.isArray(result.content) && result.content.length > 0) {
      const item = result.content[0];
      if (item.type === 'text') {
        const textVal = item.text || '';
        try {
          parsed = JSON.parse(textVal);
        } catch (_) {
          parsed = textVal;
        }
      } else {
        parsed = item;
      }
    }
    return parsed;
  }
}

async function handleAuthStart(authOptions = {}) {
  const origin = DEFAULT_ORIGIN;
  const configDir = resolveConfigDir();

  return withAuthLock(async () => {
    const existing = readPendingState();
    if (existing && Date.parse(existing.expiresAt) > Date.now()) {
      outputError('concurrent_auth_start', 'A live approval is pending. Run auth-status or wait for expiry.');
    }
    const startUrl = `${origin}/auth/cli/start`;
    const startPayload = {};
    if (authOptions.agentId) {
      startPayload.agent_id = authOptions.agentId;
    }
    if (authOptions.inviteCode) {
      startPayload.invite_code = authOptions.inviteCode;
    }
    const res = await performHttpRequest(startUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    }, JSON.stringify(startPayload));

    if (res.status < 200 || res.status >= 300) {
      outputError('auth_start_failed', `Failed to start auth flow (HTTP ${res.status})`, { exitCode: 1 });
    }

    let startData;
    try {
      startData = JSON.parse(res.body);
    } catch (e) {
      outputError('invalid_auth_start_response', 'Invalid JSON from auth start', { exitCode: 1 });
    }

    const { authRunId, pollSecret, pairingCode, expiresAt, intervalSeconds } = startData;
    let approveUrl = startData.approveUrl;
    let approval;
    try { approval = new URL(approveUrl); } catch (_) {}
    if (!approval || approval.origin !== DEFAULT_ORIGIN || approval.username || approval.password ||
        approval.pathname !== '/auth/cli/approve' || approveUrl.includes(pollSecret) ||
        typeof authRunId !== 'string' || !authRunId || authRunId.length > 256 ||
        typeof pollSecret !== 'string' || !pollSecret || pollSecret.length > 512 ||
        !Number.isFinite(Date.parse(expiresAt)) || Date.parse(expiresAt) <= Date.now() ||
        Date.parse(expiresAt) > Date.now() + 600000 || !Number.isInteger(intervalSeconds) || intervalSeconds < 1 || intervalSeconds > 60) {
      outputError('invalid_auth_start_response', 'Auth start response contains invalid fields, origin, expiry or poll interval', { exitCode: 1 });
    }
    approveUrl = withInviteQuery(approveUrl, authOptions.inviteCode);

    const pendingState = {
      authRunId,
      pollSecret,
      origin,
      approveUrl,
      expiresAt,
      intervalSeconds,
      createdAt: new Date().toISOString(),
    };

    const pendingFile = path.join(configDir, 'cli-auth.json');
    atomicWriteFile(pendingFile, JSON.stringify(pendingState, null, 2), 0o600);

    if (process.stderr.isTTY) {
      const qrOutput = renderTerminalQr(approveUrl);
      if (qrOutput) {
        process.stderr.write('\nScan this QR code with your mobile device to authorize:\n\n');
        process.stderr.write(qrOutput);
        process.stderr.write('\n');
      }
    }

    const stdoutData = {
      approveUrl,
      authRunId,
      expiresAt: pendingState.expiresAt,
      intervalSeconds: pendingState.intervalSeconds,
    };
    if (typeof pairingCode === 'string' && /^[A-Z0-9]{6}$/.test(pairingCode)) {
      stdoutData.pairingCode = pairingCode;
    }
    outputJson({
      ok: true,
      data: stdoutData,
    }, 0);
  });
}

async function handleAuthStatus() {
  return withAuthLock(async () => {
    const configDir = resolveConfigDir();
    const pendingFile = path.join(configDir, 'cli-auth.json');
    const pendingState = readPendingState();
    if (!pendingState) outputError('no_pending_auth', 'No pending authentication session found. Run auth-start first.');
    if (Date.parse(pendingState.expiresAt) <= Date.now()) {
      fs.unlinkSync(pendingFile);
      outputError('auth_expired', 'Authentication session expired. Run auth-start again.');
    }
    const { authRunId, pollSecret, origin } = pendingState;
    if (!authRunId || !pollSecret) {
      outputError('corrupted_auth_state', 'Pending auth state missing authRunId or pollSecret', { exitCode: 1 });
    }

    const checkUrl = `${DEFAULT_ORIGIN}/auth/cli/check?authRunId=${encodeURIComponent(authRunId)}`;
    const res = await performHttpRequest(checkUrl, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'X-CLI-Poll-Secret': pollSecret,
      },
    });

    if (res.status === 404 || res.status === 401) {
      try { fs.unlinkSync(pendingFile); } catch (_) {}
      outputError('auth_run_invalid', 'Authentication run unavailable, possibly after a service restart. Run auth-start for a new approval.', { exitCode: 1 });
    }

    if (res.status !== 200) {
      outputError('auth_check_failed', `Check request failed with HTTP ${res.status}`, { exitCode: 1 });
    }

    let data;
    try {
      data = JSON.parse(res.body);
    } catch (err) {
      outputError('invalid_check_response', 'Invalid JSON from auth check', { exitCode: 1 });
    }

    const status = data.status;
    const pendingLike = status === 'pending' || status === 'awaiting_gateway' || status === 'claiming';
    const tokenBearing = status === 'success' || status === 'ready' || status === 'authenticated';

    if (pendingLike) {
      outputJson({
        ok: true,
        data: {
          status: 'pending',
          authRunId,
          nextRetrySeconds: pendingState.intervalSeconds || 5,
          expiresAt: pendingState.expiresAt,
        },
      }, 0);
    } else if (tokenBearing) {
      persistClaimedToken(configDir, pendingFile, origin, data);
    } else if (status === 'consumed') {
      fs.unlinkSync(pendingFile);
      outputError('auth_exchange_failed', 'Approval was already collected. A lost collection response requires a new auth-start approval.');
    } else if (status === 'cancelled') {
      try { fs.unlinkSync(pendingFile); } catch (_) {}
      outputError('auth_cancelled', 'Authentication was cancelled or denied by user.', { exitCode: 1 });
    } else if (status === 'expired') {
      try { fs.unlinkSync(pendingFile); } catch (_) {}
      outputError('auth_expired', 'Authentication session has expired.', { exitCode: 1 });
    } else if (status === 'failed') {
      try { fs.unlinkSync(pendingFile); } catch (_) {}
      outputError('auth_failed', 'Token exchange failed', { exitCode: 1 });
    } else {
      outputError('auth_failed', 'Authentication session returned an unsupported status', { exitCode: 1, retryable: true });
    }
  });
}

function persistClaimedToken(configDir, pendingFile, origin, data) {
  const token = data.token || data.accessToken || data.bearer;
  if (typeof token !== 'string' || !token.trim() || token.length > 16384 || /[\r\n]/.test(token.trim())) {
    outputError('auth_exchange_failed', 'Approval indicated success but server returned no token.', { exitCode: 1 });
  }

  const expiresAt = data.expiresAt || (Number.isFinite(data.expires_in) && data.expires_in > 0 ? new Date(Date.now() + data.expires_in * 1000).toISOString() : null);
  const tokenFile = path.join(configDir, 'http-mcp.token');
  const metaFile = path.join(configDir, 'token-meta.json');
  try {
    if (!expiresAt || !Number.isFinite(Date.parse(expiresAt)) || Date.parse(expiresAt) <= Date.now()) throw new Error('invalid_token_expiry');

    const meta = {
      origin: origin || DEFAULT_ORIGIN,
      expiresAt,
      updatedAt: new Date().toISOString(),
    };
    atomicWriteFile(metaFile, JSON.stringify(meta, null, 2), 0o600);
    atomicWriteFile(tokenFile, token.trim() + '\n', 0o600);

    try { fs.unlinkSync(pendingFile); } catch (_) {}
  } catch (writeErr) {
    // A partial pair must not be accepted as a successful credential save.
    for (const file of [tokenFile, metaFile]) {
      try { if (checkSafePath(file)?.isFile()) fs.unlinkSync(file); } catch (_) {}
    }
    outputError('token_save_failed', 'Failed to save token and metadata. Run auth-start again if collection was consumed.', { exitCode: 1 });
  }

  outputJson({
    ok: true,
    data: {
      status: 'authenticated',
      expiresAt,
    },
  }, 0);
}

async function main() {
  const clients = [];
  const abortRequests = () => {
    for (const req of activeRequests) req.destroy(new Error('command_aborted'));
  };
  const timer = setTimeout(abortRequests, OVERALL_TIMEOUT_MS);
  timer.unref();
  process.once('SIGINT', abortRequests);
  process.once('SIGTERM', abortRequests);

  try {
    await executeCommand(clients);
  } finally {
    clearTimeout(timer);
    process.removeListener('SIGINT', abortRequests);
    process.removeListener('SIGTERM', abortRequests);
    for (const client of clients) await client.close();
  }
}

async function executeCommand(clients) {
  let parsed;
  try {
    parsed = parseCliArgs(process.argv);
  } catch (err) {
    outputError('invalid_arguments', err.message, { exitCode: 2 });
  }

  const { command, options } = parsed;
  if (!command) {
    outputError('missing_command', 'Usage: grok-search <search|fetch|map|auth-start|auth-status> [options]', { exitCode: 2 });
  }

  if (command === 'auth-start') {
    const allowed = new Set(['agent-id', 'invite-code']);
    for (const k of Object.keys(options)) {
      if (!allowed.has(k)) {
        outputError('unknown_option', `Unknown option --${k} for auth-start`, { exitCode: 2 });
      }
    }
    const agentId = typeof options['agent-id'] === 'string' ? options['agent-id'].trim() : null;
    const inviteCode = typeof options['invite-code'] === 'string' ? options['invite-code'].trim() : null;
    await handleAuthStart({ agentId, inviteCode });
    return;
  }

  if (command === 'auth-status') {
    const allowed = new Set();
    for (const k of Object.keys(options)) {
      if (!allowed.has(k)) {
        outputError('unknown_option', `Unknown option --${k} for auth-status`, { exitCode: 2 });
      }
    }
    await handleAuthStatus();
    return;
  }

  if (command === 'search') {
    const allowed = new Set(['query', 'platform', 'model', 'extra-sources']);
    for (const k of Object.keys(options)) {
      if (!allowed.has(k)) {
        outputError('unknown_option', `Unknown option --${k} for search`, { exitCode: 2 });
      }
    }
    if (!options.query || typeof options.query !== 'string' || !options.query.trim()) {
      outputError('missing_query', 'Required option --query is missing or empty', { exitCode: 2 });
    }

    const { token, source } = getTokenResolution();
    if (!token) {
      outputError('auth_required', 'Authentication token required. Run auth-start to authenticate.', { exitCode: 1 });
    }

    let extraSources = 0;
    if (options['extra-sources'] !== undefined) {
      extraSources = Number(options['extra-sources']);
      if (!Number.isSafeInteger(extraSources) || extraSources < 0) {
        outputError('invalid_option', '--extra-sources must be a non-negative safe integer', { exitCode: 2 });
      }
    }

    const searchPayload = {
      query: options.query,
      platform: options.platform || '',
      model: options.model || '',
      extra_sources: extraSources,
    };

    // 1. Try REST endpoint first
    const restRes = await requestRestEndpoint(DEFAULT_ORIGIN, 'search', token, source, searchPayload);
    if (restRes && restRes.success) {
      const restData = restRes.data || {};
      const content = restData.content || '';
      if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:') || /^(提取失败:|映射超时:|HTTP错误:|映射错误:)/.test(content)) {
        outputError('search_upstream_error', 'Search failed upstream', {
          exitCode: 1,
          retryable: false,
        });
      }
      if (content.startsWith('配置错误:') || content.startsWith('无效模型:')) {
        outputError('search_configuration_error', 'Search configuration error', { exitCode: 1 });
      }

      outputJson({
        ok: true,
        data: {
          content,
          session_id: restData.session_id,
          sources: restData.sources || [],
          sources_count: restData.sources_count !== undefined ? restData.sources_count : (restData.sources ? restData.sources.length : 0),
          sources_missing: !Array.isArray(restData.sources) || restData.sources.length === 0,
        },
      }, 0);
      return;
    }

    // 2. Fall back to exactly one hidden MCP execution if REST was classified 404 (endpoint unavailable)
    const client = new HiddenMcpClient(DEFAULT_ORIGIN, token, source);
    clients.push(client);
    await client.initialize();

    const searchArgs = {
      query: options.query,
      platform: options.platform || '',
      model: options.model || '',
      extra_sources: extraSources,
    };

    const searchResult = await client.callTool('web_search', searchArgs);
    if (!searchResult || typeof searchResult !== 'object') {
      outputError('empty_search_result', 'Search returned invalid or empty response', { exitCode: 1 });
    }

    const content = searchResult.content || '';
    if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:') || /^(提取失败:|映射超时:|HTTP错误:|映射错误:)/.test(content)) {
      outputError('search_upstream_error', 'Search failed upstream', {
        exitCode: 1,
        retryable: false,
      });
    }

    if (content.startsWith('配置错误:') || content.startsWith('无效模型:')) {
      outputError('search_configuration_error', 'Search configuration error', { exitCode: 1 });
    }

    const searchSessionId = searchResult.session_id;
    let sources = [];
    let sourcesCount = 0;
    if (searchSessionId) {
      const sourcesResult = await client.callTool('get_sources', { session_id: searchSessionId });
      if (sourcesResult && Array.isArray(sourcesResult.sources)) {
        sources = sourcesResult.sources;
        sourcesCount = sourcesResult.sources_count || sources.length;
      }
    }

    outputJson({
      ok: true,
      data: {
        content,
        session_id: searchSessionId,
        sources,
        sources_count: sourcesCount,
        sources_missing: sources.length === 0,
      },
    }, 0);
    return;
  }

  if (command === 'fetch') {
    const allowed = new Set(['url']);
    for (const k of Object.keys(options)) {
      if (!allowed.has(k)) {
        outputError('unknown_option', `Unknown option --${k} for fetch`, { exitCode: 2 });
      }
    }
    if (!options.url || typeof options.url !== 'string') {
      outputError('missing_url', 'Required option --url is missing', { exitCode: 2 });
    }

    let validUrl;
    try {
      validUrl = validateUserUrl(options.url);
    } catch (urlErr) {
      outputError('invalid_url', urlErr.message, { exitCode: 2 });
    }

    const { token, source } = getTokenResolution();
    if (!token) {
      outputError('auth_required', 'Authentication token required. Run auth-start to authenticate.', { exitCode: 1 });
    }

    const fetchPayload = { url: validUrl };

    // 1. Try REST endpoint first
    const restRes = await requestRestEndpoint(DEFAULT_ORIGIN, 'fetch', token, source, fetchPayload);
    if (restRes && restRes.success) {
      const restData = restRes.data || {};
      const content = typeof restData === 'string' ? restData : (restData && restData.content !== undefined ? restData.content : String(restData || ''));

      if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:') || /^(提取失败:|映射超时:|HTTP错误:|映射错误:)/.test(content)) {
        outputError('fetch_upstream_error', 'Fetch failed upstream', { exitCode: 1, retryable: true });
      }
      if (content.startsWith('配置错误:')) {
        outputError('fetch_configuration_error', 'Fetch configuration error', { exitCode: 1 });
      }

      outputJson({
        ok: true,
        data: {
          content,
          url: validUrl,
        },
      }, 0);
      return;
    }

    // 2. Fall back to exactly one hidden MCP execution if REST was classified 404 (endpoint unavailable)
    const client = new HiddenMcpClient(DEFAULT_ORIGIN, token, source);
    clients.push(client);
    await client.initialize();

    const result = await client.callTool('web_fetch', { url: validUrl });
    const content = typeof result === 'string' ? result : (result && result.content ? result.content : String(result || ''));

    if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:') || /^(提取失败:|映射超时:|HTTP错误:|映射错误:)/.test(content)) {
      outputError('fetch_upstream_error', 'Fetch failed upstream', { exitCode: 1, retryable: true });
    }
    if (content.startsWith('配置错误:')) {
      outputError('fetch_configuration_error', 'Fetch configuration error', { exitCode: 1 });
    }

    outputJson({
      ok: true,
      data: {
        content,
        url: validUrl,
      },
    }, 0);
    return;
  }

  if (command === 'map') {
    const allowed = new Set(['url', 'instructions', 'depth', 'breadth', 'limit', 'timeout']);
    for (const k of Object.keys(options)) {
      if (!allowed.has(k)) {
        outputError('unknown_option', `Unknown option --${k} for map`, { exitCode: 2 });
      }
    }
    if (!options.url || typeof options.url !== 'string') {
      outputError('missing_url', 'Required option --url is missing', { exitCode: 2 });
    }

    let validUrl;
    try {
      validUrl = validateUserUrl(options.url);
    } catch (urlErr) {
      outputError('invalid_url', urlErr.message, { exitCode: 2 });
    }

    const mapPayload = { url: validUrl };
    if (options.instructions) mapPayload.instructions = String(options.instructions);
    if (options.depth !== undefined) {
      const v = Number(options.depth);
      if (!Number.isInteger(v) || v < 1 || v > 5) {
        outputError('invalid_option', '--depth must be an integer between 1 and 5', { exitCode: 2 });
      }
      mapPayload.max_depth = v;
    }
    if (options.breadth !== undefined) {
      const v = Number(options.breadth);
      if (!Number.isInteger(v) || v < 1 || v > 500) {
        outputError('invalid_option', '--breadth must be an integer between 1 and 500', { exitCode: 2 });
      }
      mapPayload.max_breadth = v;
    }
    if (options.limit !== undefined) {
      const v = Number(options.limit);
      if (!Number.isInteger(v) || v < 1 || v > 500) {
        outputError('invalid_option', '--limit must be an integer between 1 and 500', { exitCode: 2 });
      }
      mapPayload.limit = v;
    }
    if (options.timeout !== undefined) {
      const v = Number(options.timeout);
      if (!Number.isInteger(v) || v < 10 || v > 150) {
        outputError('invalid_option', '--timeout must be an integer between 10 and 150', { exitCode: 2 });
      }
      mapPayload.timeout = v;
    }

    const { token, source } = getTokenResolution();
    if (!token) {
      outputError('auth_required', 'Authentication token required. Run auth-start to authenticate.', { exitCode: 1 });
    }

    // 1. Try REST endpoint first
    const restRes = await requestRestEndpoint(DEFAULT_ORIGIN, 'map', token, source, mapPayload);
    if (restRes && restRes.success) {
      const restData = restRes.data || {};
      const content = typeof restData === 'string' ? restData : (restData && restData.content !== undefined ? restData.content : String(restData || ''));

      if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:') || /^(提取失败:|映射超时:|HTTP错误:|映射错误:)/.test(content)) {
        outputError('map_upstream_error', 'Map failed upstream', { exitCode: 1, retryable: true });
      }
      if (content.startsWith('配置错误:')) {
        outputError('map_configuration_error', 'Map configuration error', { exitCode: 1 });
      }

      outputJson({
        ok: true,
        data: {
          content,
          url: validUrl,
        },
      }, 0);
      return;
    }

    // 2. Fall back to exactly one hidden MCP execution if REST was classified 404 (endpoint unavailable)
    const client = new HiddenMcpClient(DEFAULT_ORIGIN, token, source);
    clients.push(client);
    await client.initialize();

    const result = await client.callTool('web_map', mapPayload);
    const content = typeof result === 'string' ? result : (result && result.content ? result.content : String(result || ''));

    if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:') || /^(提取失败:|映射超时:|HTTP错误:|映射错误:)/.test(content)) {
      outputError('map_upstream_error', 'Map failed upstream', { exitCode: 1, retryable: true });
    }
    if (content.startsWith('配置错误:')) {
      outputError('map_configuration_error', 'Map configuration error', { exitCode: 1 });
    }

    outputJson({
      ok: true,
      data: {
        content,
        url: validUrl,
      },
    }, 0);
    return;
  }

  outputError('unknown_command', `Unknown command: ${command}`, { exitCode: 2 });

}

async function run() {
  try { await main(); } catch (err) {
    if (err instanceof CliExit) { process.exitCode = err.exitCode; return; }
    const code = /^(symlink_rejected|unsafe_owner|unsafe_path|unsafe_file|secure_storage_unavailable|invalid_token_origin|invalid_token_metadata)/.exec(err.message || '');
    process.stdout.write(JSON.stringify({ ok: false, error: { code: code ? code[1] : 'transport_error', message: 'Command failed. Verify private state or service availability; an ambiguous search must not be replayed automatically.', retryable: false } }) + '\n');
    process.exitCode = 1;
  }
}

if (require.main === module) run();

module.exports = {
  run,
  HiddenMcpClient,
  requestRestEndpoint,
  validateUserUrl,
  decodeMcpResponse,
  renderTerminalQr,
  setTransport,
  getTokenResolution,
  withInviteQuery,
  handleAuthStart,
  handleAuthStatus,
  main,
};
