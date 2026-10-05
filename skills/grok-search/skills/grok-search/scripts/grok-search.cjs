#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');
const http = require('http');
const tty = require('tty');

const DEFAULT_ORIGIN = 'https://search.karldigi.dev';
const MCP_PATH = '/mcp';
const REST_API_PREFIX = '/api/v1';
const MCP_PROTOCOL_VERSION = '2025-03-26';
const CLIENT_INFO = { name: 'grok-search-cli', version: '0.1.20' };

const REQUEST_TIMEOUT_MS = 30000;
const OVERALL_TIMEOUT_MS = 60000;
const MAX_RESPONSE_BYTES = 10 * 1024 * 1024; // 10MB limit

let activeTransport = null;

function setTransport(fn) {
  activeTransport = fn;
}

function resolveConfigDir() {
  const home = process.env.HOME || os.homedir();
  return path.join(home, '.config', 'grok-search');
}

function checkSafePath(targetPath) {
  if (fs.existsSync(targetPath)) {
    const stat = fs.lstatSync(targetPath);
    if (stat.isSymbolicLink()) {
      throw new Error(`symlink_rejected: ${targetPath} must not be a symbolic link`);
    }
  }
}

function ensureConfigDir() {
  const dir = resolveConfigDir();
  checkSafePath(dir);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  } else {
    const stat = fs.statSync(dir);
    if (process.platform !== 'win32' && (stat.mode & 0o077) !== 0) {
      fs.chmodSync(dir, 0o700);
    }
  }
  return dir;
}

function atomicWriteFile(targetPath, content, mode = 0o600) {
  checkSafePath(targetPath);
  const dir = path.dirname(targetPath);
  ensureConfigDir();
  const tmpName = `.tmp-${path.basename(targetPath)}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const tmpPath = path.join(dir, tmpName);

  const fd = fs.openSync(tmpPath, 'wx', mode);
  try {
    fs.writeFileSync(fd, content, { encoding: 'utf8' });
  } finally {
    fs.closeSync(fd);
  }
  if (process.platform !== 'win32') {
    fs.chmodSync(tmpPath, mode);
  }
  fs.renameSync(tmpPath, targetPath);
}

function getTokenResolution() {
  const envToken = process.env.GROK_SEARCH_MCP_TOKEN;
  if (envToken && envToken.trim()) {
    return { token: envToken.trim(), source: 'env' };
  }
  const configDir = resolveConfigDir();
  const tokenFile = path.join(configDir, 'http-mcp.token');
  if (fs.existsSync(tokenFile)) {
    checkSafePath(tokenFile);
    const stat = fs.statSync(tokenFile);
    if (process.platform !== 'win32' && (stat.mode & 0o077) !== 0) {
      fs.chmodSync(tokenFile, 0o600);
    }
    const token = fs.readFileSync(tokenFile, 'utf8').trim();
    if (token) {
      return { token, source: 'file' };
    }
  }
  return { token: null, source: 'none' };
}

function outputJson(obj, exitCode = 0) {
  process.stdout.write(JSON.stringify(obj) + '\n');
  process.exit(exitCode);
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
    throw new Error(`invalid_url: Target URL '${rawUrl}' is not a valid URL`);
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error(`invalid_url: Target URL protocol must be http: or https:, got '${parsed.protocol}'`);
  }
  if (parsed.username || parsed.password) {
    throw new Error('invalid_url: Target URL must not contain embedded credentials');
  }
  const hostname = parsed.hostname.toLowerCase();
  if (
    hostname === 'localhost' ||
    hostname === '127.0.0.1' ||
    hostname === '::1' ||
    hostname === '0.0.0.0' ||
    hostname.endsWith('.localhost') ||
    hostname.endsWith('.local')
  ) {
    throw new Error(`invalid_url: Target URL hostname '${parsed.hostname}' is not permitted`);
  }
  return rawUrl;
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
      outputError('invalid_rest_response', 'REST response returned invalid JSON: ' + err.message, { exitCode: 1 });
    }
    if (parsed && typeof parsed === 'object' && parsed.ok === true) {
      return { success: true, data: parsed.data };
    }
    if (parsed && typeof parsed === 'object' && parsed.ok === false && parsed.error) {
      outputError(parsed.error.code || 'api_error', parsed.error.message || 'REST API returned error', {
        exitCode: 1,
        retryable: !!parsed.error.retryable,
      });
    }
    outputError('invalid_rest_response', 'REST response did not match expected envelope', { exitCode: 1 });
  }

  if (res.status === 401) {
    if (tokenSource === 'env') {
      outputError(
        'env_token_rejected',
        'GROK_SEARCH_MCP_TOKEN environment variable was rejected (401). Update or unset the environment override; a file token cannot supersede it.',
        { exitCode: 1, retryable: false }
      );
    } else {
      outputError(
        'auth_required',
        'GrokSearch authentication token is invalid or expired. Run auth-start to authenticate.',
        { exitCode: 1, retryable: false }
      );
    }
  }

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
        outputError(parsedBody.error.code || 'not_found', parsedBody.error.message || 'Resource not found', { exitCode: 1 });
      }
      if (parsedBody.code === 'not_found' || parsedBody.error === 'not_found') {
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
  return { command, options };
}

function performHttpRequest(reqUrl, reqOptions, body) {
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
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          headers: res.headers,
          body: rawData,
        });
      });
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('request_timeout'));
    });
    req.on('error', (err) => {
      reject(err);
    });

    if (body) {
      req.write(body);
    }
    req.end();
  });
}

function decodeMcpResponse(contentType, text) {
  if (contentType && contentType.includes('text/event-stream')) {
    const lines = text.split(/\r?\n/);
    const dataLines = [];
    for (const line of lines) {
      if (line.startsWith('data:')) {
        dataLines.push(line.slice(5).trim());
      }
    }
    if (dataLines.length === 0) {
      throw new Error('empty_event_stream');
    }
    return JSON.parse(dataLines[dataLines.length - 1]);
  }
  return JSON.parse(text);
}

class HiddenMcpClient {
  constructor(origin, token, tokenSource) {
    this.origin = origin.replace(/\/+$/, '');
    this.token = token;
    this.tokenSource = tokenSource;
    this.mcpUrl = `${this.origin}${MCP_PATH}`;
    this.sessionId = null;
    this.nextRequestId = 1;
  }

  async postMcp(bodyObj, headers = {}) {
    const reqHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': MCP_PROTOCOL_VERSION,
      'Authorization': `Bearer ${this.token}`,
      ...headers,
    };
    if (this.sessionId) {
      reqHeaders['Mcp-Session-Id'] = this.sessionId;
    }

    const payload = JSON.stringify(bodyObj);
    const res = await performHttpRequest(this.mcpUrl, { method: 'POST', headers: reqHeaders }, payload);

    if (res.status === 401) {
      if (this.tokenSource === 'env') {
        outputError(
          'env_token_rejected',
          'GROK_SEARCH_MCP_TOKEN environment variable was rejected (401). Update or unset the environment override; a file token cannot supersede it.',
          { exitCode: 1, retryable: false }
        );
      } else {
        outputError(
          'auth_required',
          'GrokSearch authentication token is invalid or expired. Run auth-start to authenticate.',
          { exitCode: 1, retryable: false }
        );
      }
    }

    if (res.status === 202) {
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
      const decoded = decodeMcpResponse(res.headers['content-type'], res.body);
      return { status: res.status, payload: decoded };
    } catch (err) {
      outputError('invalid_mcp_response', 'Failed to decode MCP JSON/SSE response: ' + err.message, { exitCode: 1 });
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
      outputError('mcp_initialize_failed', payload.error.message || 'Initialize failed', {
        exitCode: 1,
        code: payload.error.code,
      });
    }

    const notifBody = {
      jsonrpc: '2.0',
      method: 'notifications/initialized',
      params: {},
    };
    await this.postMcp(notifBody);
  }

  async callTool(name, args) {
    const reqBody = {
      jsonrpc: '2.0',
      id: this.nextRequestId++,
      method: 'tools/call',
      params: {
        name,
        arguments: args,
      },
    };

    const res = await this.postMcp(reqBody);
    const payload = res.payload;
    if (payload.error) {
      outputError('tool_call_error', payload.error.message || 'Tool call error', {
        exitCode: 1,
        tool: name,
        code: payload.error.code,
      });
    }

    const result = payload.result || {};
    if (result.isError) {
      let msg = 'Tool returned error';
      if (Array.isArray(result.content) && result.content[0] && result.content[0].text) {
        msg = result.content[0].text;
      }
      outputError('tool_error', msg, { exitCode: 1, tool: name });
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

async function handleAuthStart() {
  const origin = DEFAULT_ORIGIN;
  const configDir = resolveConfigDir();
  ensureConfigDir();

  const lockPath = path.join(configDir, 'cli-auth.lock');
  checkSafePath(lockPath);
  let lockFd = null;
  try {
    lockFd = fs.openSync(lockPath, 'wx', 0o600);
  } catch (err) {
    if (err.code === 'EEXIST') {
      try {
        const stat = fs.statSync(lockPath);
        if (Date.now() - stat.mtimeMs < 60000) {
          outputError('concurrent_auth_start', 'Another authentication session is currently in progress.', { exitCode: 1 });
        } else {
          fs.unlinkSync(lockPath);
          lockFd = fs.openSync(lockPath, 'wx', 0o600);
        }
      } catch (_) {
        outputError('concurrent_auth_start', 'Another authentication session is currently in progress.', { exitCode: 1 });
      }
    } else {
      outputError('lock_failed', 'Failed to acquire auth lock: ' + err.message, { exitCode: 1 });
    }
  }

  try {
    const startUrl = `${origin}/auth/cli/start`;
    const res = await performHttpRequest(startUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    }, JSON.stringify({}));

    if (res.status < 200 || res.status >= 300) {
      outputError('auth_start_failed', `Failed to start auth flow (HTTP ${res.status}): ${res.body}`, { exitCode: 1 });
    }

    let startData;
    try {
      startData = JSON.parse(res.body);
    } catch (e) {
      outputError('invalid_auth_start_response', 'Invalid JSON from auth start: ' + e.message, { exitCode: 1 });
    }

    const { approveUrl, authRunId, pollSecret, pairingCode, expiresAt, intervalSeconds } = startData;
    if (!approveUrl || !authRunId || !pollSecret) {
      outputError('invalid_auth_start_response', 'Auth start response missing required fields', { exitCode: 1 });
    }

    const pendingState = {
      authRunId,
      pollSecret,
      origin,
      approveUrl,
      expiresAt: expiresAt || new Date(Date.now() + 600000).toISOString(),
      intervalSeconds: intervalSeconds || 5,
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
    if (pairingCode) {
      stdoutData.pairingCode = pairingCode;
    }
    outputJson({
      ok: true,
      data: stdoutData,
    }, 0);
  } finally {
    if (lockFd !== null) {
      try {
        fs.closeSync(lockFd);
        fs.unlinkSync(lockPath);
      } catch (_) {}
    }
  }
}

async function handleAuthStatus() {
  const configDir = resolveConfigDir();
  const pendingFile = path.join(configDir, 'cli-auth.json');
  if (!fs.existsSync(pendingFile)) {
    outputError('no_pending_auth', 'No pending authentication session found. Run auth-start first.', { exitCode: 1 });
  }
  checkSafePath(pendingFile);

  let pendingState;
  try {
    pendingState = JSON.parse(fs.readFileSync(pendingFile, 'utf8'));
  } catch (err) {
    outputError('corrupted_auth_state', 'Failed to read pending auth state: ' + err.message, { exitCode: 1 });
  }

  const { authRunId, pollSecret, origin } = pendingState;
  if (!authRunId || !pollSecret) {
    outputError('corrupted_auth_state', 'Pending auth state missing authRunId or pollSecret', { exitCode: 1 });
  }

  const checkUrl = `${origin || DEFAULT_ORIGIN}/auth/cli/check?authRunId=${encodeURIComponent(authRunId)}`;
  const res = await performHttpRequest(checkUrl, {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'X-CLI-Poll-Secret': pollSecret,
    },
  });

  if (res.status === 404 || res.status === 401) {
    try { fs.unlinkSync(pendingFile); } catch (_) {}
    outputError('auth_run_invalid', 'Authentication run was rejected, expired, or not found.', { exitCode: 1 });
  }

  if (res.status !== 200) {
    outputError('auth_check_failed', `Check request failed with HTTP ${res.status}`, { exitCode: 1 });
  }

  let data;
  try {
    data = JSON.parse(res.body);
  } catch (err) {
    outputError('invalid_check_response', 'Invalid JSON from auth check: ' + err.message, { exitCode: 1 });
  }

  const status = data.status;
  if (status === 'pending' || status === 'awaiting_gateway') {
    outputJson({
      ok: true,
      data: {
        status: 'pending',
        authRunId,
        nextRetrySeconds: pendingState.intervalSeconds || 5,
        expiresAt: pendingState.expiresAt,
      },
    }, 0);
  } else if (status === 'ready' || status === 'authenticated' || status === 'consumed') {
    const token = data.token || data.accessToken || data.bearer;
    if (!token) {
      outputError('auth_exchange_failed', 'Approval indicated success but server returned no token.', { exitCode: 1 });
    }

    try {
      const tokenFile = path.join(configDir, 'http-mcp.token');
      atomicWriteFile(tokenFile, token.trim() + '\n', 0o600);

      const metaFile = path.join(configDir, 'token-meta.json');
      const meta = {
        origin: origin || DEFAULT_ORIGIN,
        expiresAt: data.expiresAt || null,
        updatedAt: new Date().toISOString(),
      };
      atomicWriteFile(metaFile, JSON.stringify(meta, null, 2), 0o600);

      try { fs.unlinkSync(pendingFile); } catch (_) {}
    } catch (writeErr) {
      outputError('token_save_failed', 'Failed to atomically save token to disk: ' + writeErr.message, { exitCode: 1 });
    }

    outputJson({
      ok: true,
      data: {
        status: 'authenticated',
        expiresAt: data.expiresAt || null,
      },
    }, 0);
  } else if (status === 'cancelled') {
    try { fs.unlinkSync(pendingFile); } catch (_) {}
    outputError('auth_cancelled', 'Authentication was cancelled or denied by user.', { exitCode: 1 });
  } else if (status === 'expired') {
    try { fs.unlinkSync(pendingFile); } catch (_) {}
    outputError('auth_expired', 'Authentication session has expired.', { exitCode: 1 });
  } else {
    try { fs.unlinkSync(pendingFile); } catch (_) {}
    outputError('auth_failed', `Authentication session ended with status: ${status}`, { exitCode: 1 });
  }
}

async function main() {
  const timer = setTimeout(() => {
    outputError('command_timeout', 'Command exceeded overall deadline', { exitCode: 1 });
  }, OVERALL_TIMEOUT_MS);
  timer.unref();

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
    const allowed = new Set();
    for (const k of Object.keys(options)) {
      if (!allowed.has(k)) {
        outputError('unknown_option', `Unknown option --${k} for auth-start`, { exitCode: 2 });
      }
    }
    await handleAuthStart();
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
      extraSources = parseInt(options['extra-sources'], 10);
      if (isNaN(extraSources) || extraSources < 0) {
        outputError('invalid_option', '--extra-sources must be a non-negative integer', { exitCode: 2 });
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
      if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:')) {
        outputError('search_upstream_error', `Search failed upstream: ${content || 'empty content'}`, {
          exitCode: 1,
          content,
          retryable: true,
        });
      }
      if (content.startsWith('配置错误:') || content.startsWith('无效模型:')) {
        outputError('search_configuration_error', content, { exitCode: 1 });
      }

      outputJson({
        ok: true,
        data: {
          content,
          session_id: restData.session_id,
          sources: restData.sources || [],
          sources_count: restData.sources_count !== undefined ? restData.sources_count : (restData.sources ? restData.sources.length : 0),
        },
      }, 0);
      return;
    }

    // 2. Fall back to exactly one hidden MCP execution if REST was classified 404 (endpoint unavailable)
    const client = new HiddenMcpClient(DEFAULT_ORIGIN, token, source);
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
    if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:')) {
      outputError('search_upstream_error', `Search failed upstream: ${content || 'empty content'}`, {
        exitCode: 1,
        content,
        retryable: true,
      });
    }

    if (content.startsWith('配置错误:') || content.startsWith('无效模型:')) {
      outputError('search_configuration_error', content, { exitCode: 1 });
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

      if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:')) {
        outputError('fetch_upstream_error', `Fetch failed: ${content || 'empty content'}`, { exitCode: 1, retryable: true });
      }
      if (content.startsWith('配置错误:')) {
        outputError('fetch_configuration_error', content, { exitCode: 1 });
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
    await client.initialize();

    const result = await client.callTool('web_fetch', { url: validUrl });
    const content = typeof result === 'string' ? result : (result && result.content ? result.content : String(result || ''));

    if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:')) {
      outputError('fetch_upstream_error', `Fetch failed: ${content || 'empty content'}`, { exitCode: 1, retryable: true });
    }
    if (content.startsWith('配置错误:')) {
      outputError('fetch_configuration_error', content, { exitCode: 1 });
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
      const v = parseInt(options.depth, 10);
      if (isNaN(v) || v < 1 || v > 5) {
        outputError('invalid_option', '--depth must be an integer between 1 and 5', { exitCode: 2 });
      }
      mapPayload.max_depth = v;
    }
    if (options.breadth !== undefined) {
      const v = parseInt(options.breadth, 10);
      if (isNaN(v) || v < 1 || v > 500) {
        outputError('invalid_option', '--breadth must be an integer between 1 and 500', { exitCode: 2 });
      }
      mapPayload.max_breadth = v;
    }
    if (options.limit !== undefined) {
      const v = parseInt(options.limit, 10);
      if (isNaN(v) || v < 1 || v > 500) {
        outputError('invalid_option', '--limit must be an integer between 1 and 500', { exitCode: 2 });
      }
      mapPayload.limit = v;
    }
    if (options.timeout !== undefined) {
      const v = parseInt(options.timeout, 10);
      if (isNaN(v) || v < 10 || v > 150) {
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

      if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:')) {
        outputError('map_upstream_error', `Map failed: ${content || 'empty content'}`, { exitCode: 1, retryable: true });
      }
      if (content.startsWith('配置错误:')) {
        outputError('map_configuration_error', content, { exitCode: 1 });
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
    await client.initialize();

    const result = await client.callTool('web_map', mapPayload);
    const content = typeof result === 'string' ? result : (result && result.content ? result.content : String(result || ''));

    if (content === '' || content.startsWith('upstream_error:') || content.startsWith('upstream_empty:')) {
      outputError('map_upstream_error', `Map failed: ${content || 'empty content'}`, { exitCode: 1, retryable: true });
    }
    if (content.startsWith('配置错误:')) {
      outputError('map_configuration_error', content, { exitCode: 1 });
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

if (require.main === module) {
  main().catch((err) => {
    outputError('unhandled_error', err.message || 'Unhandled error', { exitCode: 1 });
  });
}

module.exports = {
  HiddenMcpClient,
  requestRestEndpoint,
  validateUserUrl,
  decodeMcpResponse,
  renderTerminalQr,
  setTransport,
  getTokenResolution,
  handleAuthStart,
  handleAuthStatus,
  main,
};
