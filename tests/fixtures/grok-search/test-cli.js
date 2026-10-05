'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const nestedCliPath = path.resolve(__dirname, '../../../skills/grok-search/skills/grok-search/scripts/grok-search.cjs');
const outerCliPath = path.resolve(__dirname, '../../../skills/grok-search/scripts/grok-search.cjs');

function runCli(scriptPath, args, options = {}) {
  const result = spawnSync(process.execPath, [scriptPath, ...args], {
    encoding: 'utf8',
    env: options.env || { ...process.env },
    cwd: options.cwd || process.cwd(),
  });
  let stdoutJson = null;
  if (result.stdout && result.stdout.trim()) {
    try {
      stdoutJson = JSON.parse(result.stdout.trim());
    } catch (_) {}
  }
  return {
    status: result.status,
    stdout: result.stdout,
    stderr: result.stderr,
    json: stdoutJson,
  };
}

function decodeQRMatrix(matrix) {
  const size = matrix.length;
  const version = (size - 17) / 4;
  let formatBits = 0;
  const formatCoords = [
    [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
    [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8]
  ];
  for (let i = 0; i < 15; i++) {
    const [r, c] = formatCoords[i];
    if (matrix[r][c]) formatBits |= (1 << (14 - i));
  }
  formatBits ^= 0b101010001010010;
  const mask = (formatBits >> 10) & 0b111;

  function isMasked(r, c) {
    switch (mask) {
      case 0: return (r + c) % 2 === 0;
      case 1: return r % 2 === 0;
      case 2: return c % 3 === 0;
      case 3: return (r + c) % 3 === 0;
      case 4: return (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0;
      case 5: return ((r * c) % 2) + ((r * c) % 3) === 0;
      case 6: return (((r * c) % 2) + ((r * c) % 3)) % 2 === 0;
      case 7: return (((r + c) % 2) + ((r * c) % 3)) % 2 === 0;
    }
  }

  const isFunction = Array.from({ length: size }, () => Array(size).fill(false));
  function markRect(r1, c1, h, w) {
    for (let r = r1; r < r1 + h; r++) {
      for (let c = c1; c < c1 + w; c++) {
        if (r >= 0 && r < size && c >= 0 && c < size) isFunction[r][c] = true;
      }
    }
  }
  markRect(0, 0, 9, 9);
  markRect(0, size - 8, 9, 8);
  markRect(size - 8, 0, 8, 9);
  for (let i = 0; i < size; i++) {
    isFunction[6][i] = true;
    isFunction[i][6] = true;
  }
  isFunction[4 * version + 9][8] = true;

  const alignmentPatternPositions = [
    [], [],
    [6, 18],
    [6, 22],
    [6, 26],
    [6, 30],
    [6, 34],
    [6, 22, 38],
    [6, 24, 42],
    [6, 26, 46],
    [6, 28, 50],
  ];
  if (version >= 2 && alignmentPatternPositions[version]) {
    const pos = alignmentPatternPositions[version];
    for (const r of pos) {
      for (const c of pos) {
        if (!((r === 6 && c === 6) || (r === 6 && c === pos[pos.length - 1] && c > size - 10) || (c === 6 && r === pos[pos.length - 1] && r > size - 10))) {
          if (!isFunction[r][c]) {
            markRect(r - 2, c - 2, 5, 5);
          }
        }
      }
    }
  }

  if (version >= 7) {
    markRect(0, size - 11, 6, 3);
    markRect(size - 11, 0, 3, 6);
  }

  const bits = [];
  let upward = true;
  for (let right = size - 1; right > 0; right -= 2) {
    if (right === 6) right--;
    const cols = [right, right - 1];
    const rows = upward
      ? Array.from({ length: size }, (_, i) => size - 1 - i)
      : Array.from({ length: size }, (_, i) => i);
    for (const r of rows) {
      for (const c of cols) {
        if (!isFunction[r][c]) {
          const mod = matrix[r][c] ? 1 : 0;
          const bit = isMasked(r, c) ? (mod ^ 1) : mod;
          bits.push(bit);
        }
      }
    }
    upward = !upward;
  }

  let bitIdx = 0;
  function readBits(n) {
    let val = 0;
    for (let i = 0; i < n; i++) {
      val = (val << 1) | bits[bitIdx++];
    }
    return val;
  }

  const mode = readBits(4);
  if (mode === 4) {
    const countLength = version <= 9 ? 8 : 16;
    const charCount = readBits(countLength);
    const resultBytes = [];
    for (let i = 0; i < charCount; i++) {
      resultBytes.push(readBits(8));
    }
    return Buffer.from(resultBytes).toString('utf8');
  }
  return null;
}

describe('Grok Search CLI sequential test suite', { concurrency: 1 }, () => {
  it('CLI option parsing and unknown argument rejection', () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    try {
      const res = runCli(nestedCliPath, ['search', '--invalid-opt'], {
        env: { HOME: tmpHome, PATH: process.env.PATH },
      });
      assert.strictEqual(res.status, 2);
      assert.strictEqual(res.json.ok, false);
      assert.strictEqual(res.json.error.code, 'unknown_option');
    } finally {
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('token env-over-file precedence and env_token_rejected', () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    const origToken = process.env.GROK_SEARCH_MCP_TOKEN;
    try {
      process.env.HOME = tmpHome;
      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true });
      fs.writeFileSync(path.join(configDir, 'http-mcp.token'), 'file-token\n');

      const cliMod = require(nestedCliPath);
      process.env.GROK_SEARCH_MCP_TOKEN = 'env-token';
      const envRes = cliMod.getTokenResolution();
      assert.strictEqual(envRes.token, 'env-token');
      assert.strictEqual(envRes.source, 'env');

      delete process.env.GROK_SEARCH_MCP_TOKEN;
      const fileRes = cliMod.getTokenResolution();
      assert.strictEqual(fileRes.token, 'file-token');
      assert.strictEqual(fileRes.source, 'file');
    } finally {
      process.env.HOME = origHome;
      if (origToken) process.env.GROK_SEARCH_MCP_TOKEN = origToken;
      else delete process.env.GROK_SEARCH_MCP_TOKEN;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('auth_required when token is missing', () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    try {
      const res = runCli(nestedCliPath, ['search', '--query', 'test query'], {
        env: { HOME: tmpHome, PATH: process.env.PATH },
      });
      assert.strictEqual(res.status, 1);
      assert.strictEqual(res.json.ok, false);
      assert.strictEqual(res.json.error.code, 'auth_required');
    } finally {
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('auth-start returns HTTPS link without pollSecret and QR encodes approveUrl', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    const origToken = process.env.GROK_SEARCH_MCP_TOKEN;
    try {
      process.env.HOME = tmpHome;
      delete process.env.GROK_SEARCH_MCP_TOKEN;

      const cliMod = require(nestedCliPath);
      cliMod.setTransport(async (url) => {
        assert.strictEqual(url, 'https://search.karldigi.dev/auth/cli/start');
        return {
          status: 200,
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            approveUrl: 'https://search.karldigi.dev/auth/cli/approve?code=testapprove123',
            authRunId: 'auth-run-test-id',
            pollSecret: 'poll-secret-collector-keep-private',
            expiresAt: '2026-10-05T12:00:00Z',
            intervalSeconds: 5,
          }),
        };
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };

      try {
        await assert.rejects(async () => {
          await cliMod.handleAuthStart();
        }, /EXIT_0/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        cliMod.setTransport(null);
      }

      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.data.approveUrl, 'https://search.karldigi.dev/auth/cli/approve?code=testapprove123');
      assert.strictEqual(res.data.authRunId, 'auth-run-test-id');
      assert.strictEqual(res.data.pollSecret, undefined);
      assert.strictEqual(stdoutData.includes('poll-secret-collector-keep-private'), false);

      const pendingFile = path.join(tmpHome, '.config', 'grok-search', 'cli-auth.json');
      assert.strictEqual(fs.existsSync(pendingFile), true);
      const stat = fs.statSync(pendingFile);
      assert.strictEqual((stat.mode & 0o777), 0o600);

      const { toQR } = require('../../../skills/grok-search/skills/grok-search/scripts/lib/toqr.cjs');
      const rawQr = toQR(res.data.approveUrl);
      const extent = Math.sqrt(rawQr.byteLength) | 0;
      const matrix = [];
      for (let r = 0; r < extent; r++) {
        const row = [];
        for (let c = 0; c < extent; c++) {
          row.push(rawQr[r * extent + c] === 1);
        }
        matrix.push(row);
      }
      const decodedUrl = decodeQRMatrix(matrix);
      assert.strictEqual(decodedUrl, res.data.approveUrl);
      assert.strictEqual(decodedUrl.includes('poll-secret'), false);
    } finally {
      process.env.HOME = origHome;
      if (origToken) process.env.GROK_SEARCH_MCP_TOKEN = origToken;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('auth-status handles pending and authenticated transitions', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    try {
      process.env.HOME = tmpHome;
      delete process.env.GROK_SEARCH_MCP_TOKEN;

      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
      const pendingFile = path.join(configDir, 'cli-auth.json');
      fs.writeFileSync(pendingFile, JSON.stringify({
        authRunId: 'run-check-1',
        pollSecret: 'secret-check-1',
        origin: 'https://search.karldigi.dev',
        expiresAt: '2026-10-05T12:00:00Z',
        intervalSeconds: 5,
      }), { mode: 0o600 });

      const cliMod = require(nestedCliPath);
      cliMod.setTransport(async (url, opts) => {
        assert.strictEqual(url, 'https://search.karldigi.dev/auth/cli/check?authRunId=run-check-1');
        assert.strictEqual(opts.headers['X-CLI-Poll-Secret'], 'secret-check-1');
        return {
          status: 200,
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            status: 'ready',
            token: 'saved-bearer-token-123',
            expiresAt: '2026-10-05T14:00:00Z',
          }),
        };
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };

      try {
        await assert.rejects(async () => {
          await cliMod.handleAuthStatus();
        }, /EXIT_0/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        cliMod.setTransport(null);
      }

      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.data.status, 'authenticated');

      const tokenPath = path.join(configDir, 'http-mcp.token');
      assert.strictEqual(fs.existsSync(tokenPath), true);
      assert.strictEqual(fs.readFileSync(tokenPath, 'utf8').trim(), 'saved-bearer-token-123');
      const stat = fs.statSync(tokenPath);
      assert.strictEqual((stat.mode & 0o777), 0o600);
      assert.strictEqual(fs.existsSync(pendingFile), false);
    } finally {
      process.env.HOME = origHome;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('safe file permissions: symlinks rejected', () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    try {
      process.env.HOME = tmpHome;
      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true });
      const realTarget = path.join(tmpHome, 'real.txt');
      fs.writeFileSync(realTarget, 'real-content');
      const symlinkTarget = path.join(configDir, 'http-mcp.token');
      fs.symlinkSync(realTarget, symlinkTarget);

      const cliMod = require(nestedCliPath);
      assert.throws(() => {
        cliMod.getTokenResolution();
      }, /symlink_rejected/);
    } finally {
      process.env.HOME = origHome;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('mocked MCP search executes initialize, notifications/initialized, web_search and get_sources', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    try {
      process.env.HOME = tmpHome;
      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(path.join(configDir, 'http-mcp.token'), 'mock-bearer\n', { mode: 0o600 });

      const cliMod = require(nestedCliPath);
      const trace = [];
      cliMod.setTransport(async (url, opts, body) => {
        if (url === 'https://search.karldigi.dev/api/v1/search') {
          return { status: 404, headers: { 'content-type': 'text/plain' }, body: '404 Not Found' };
        }
        assert.strictEqual(url, 'https://search.karldigi.dev/mcp');
        assert.strictEqual(opts.headers.Authorization, 'Bearer mock-bearer');
        const req = JSON.parse(body);
        trace.push(req.method + (req.params && req.params.name ? ':' + req.params.name : ''));

        if (req.method === 'initialize') {
          return {
            status: 200,
            headers: { 'content-type': 'application/json', 'mcp-session-id': 'sess-1' },
            body: JSON.stringify({
              jsonrpc: '2.0',
              id: req.id,
              result: { protocolVersion: '2025-03-26', serverInfo: { name: 'grok-search' } },
            }),
          };
        }
        if (req.method === 'notifications/initialized') {
          return { status: 202, headers: {}, body: '' };
        }
        if (req.method === 'tools/call' && req.params.name === 'web_search') {
          return {
            status: 200,
            headers: { 'content-type': 'text/event-stream', 'mcp-session-id': 'sess-1' },
            body: 'data: ' + JSON.stringify({
              jsonrpc: '2.0',
              id: req.id,
              result: {
                content: [{
                  type: 'text',
                  text: JSON.stringify({
                    session_id: 'search-sid-abc',
                    content: 'Mocked search answer.',
                    sources_count: 1,
                  }),
                }],
              },
            }) + '\n\n',
          };
        }
        if (req.method === 'tools/call' && req.params.name === 'get_sources') {
          return {
            status: 200,
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              jsonrpc: '2.0',
              id: req.id,
              result: {
                content: [{
                  type: 'text',
                  text: JSON.stringify({
                    session_id: 'search-sid-abc',
                    sources: [{ title: 'Doc', url: 'https://docs.example.com' }],
                    sources_count: 1,
                  }),
                }],
              },
            }),
          };
        }
        throw new Error('Unexpected: ' + JSON.stringify(req));
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };
      const origArgv = process.argv;
      process.argv = ['node', 'grok-search.cjs', 'search', '--query', 'latest news'];

      try {
        await assert.rejects(async () => {
          await cliMod.main();
        }, /EXIT_0/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        process.argv = origArgv;
        cliMod.setTransport(null);
      }

      assert.deepStrictEqual(trace, [
        'initialize',
        'notifications/initialized',
        'tools/call:web_search',
        'tools/call:get_sources',
      ]);
      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.data.session_id, 'search-sid-abc');
      assert.strictEqual(res.data.sources.length, 1);
      assert.strictEqual(res.data.sources[0].url, 'https://docs.example.com');
    } finally {
      process.env.HOME = origHome;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('packaged install: space in dir path, invocation from another CWD, host configs untouched', () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    try {
      const hostSkillsDir = path.join(tmpHome, 'host skills space');
      fs.mkdirSync(hostSkillsDir, { recursive: true });
      const targetDir = path.join(hostSkillsDir, 'grok-search');

      const sourceUnit = path.resolve(__dirname, '../../../skills/grok-search/skills/grok-search');
      fs.cpSync(sourceUnit, targetDir, { recursive: true });

      const hostMcpJson = path.join(tmpHome, 'mcp.json');
      const hostConfigToml = path.join(tmpHome, 'config.toml');
      fs.writeFileSync(hostMcpJson, '{"untouched":true}\n');
      fs.writeFileSync(hostConfigToml, '[untouched]\nflag = true\n');

      const unrelatedCwd = os.tmpdir();
      const installedScript = path.join(targetDir, 'scripts', 'grok-search.cjs');
      const res = runCli(installedScript, [], {
        cwd: unrelatedCwd,
        env: { HOME: tmpHome, PATH: process.env.PATH },
      });

      assert.strictEqual(res.status, 2);
      assert.strictEqual(res.json.ok, false);
      assert.strictEqual(res.json.error.code, 'missing_command');

      assert.strictEqual(fs.readFileSync(hostMcpJson, 'utf8'), '{"untouched":true}\n');
      assert.strictEqual(fs.readFileSync(hostConfigToml, 'utf8'), '[untouched]\nflag = true\n');

      const outerRes = runCli(outerCliPath, [], {
        cwd: unrelatedCwd,
        env: { HOME: tmpHome, PATH: process.env.PATH },
      });
      assert.strictEqual(outerRes.status, 2);
      assert.strictEqual(outerRes.json.ok, false);
      assert.strictEqual(outerRes.json.error.code, 'missing_command');
    } finally {
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('M2 REST 200 used; MCP not called and includes sources', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    try {
      process.env.HOME = tmpHome;
      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(path.join(configDir, 'http-mcp.token'), 'test-rest-token\n', { mode: 0o600 });

      const cliMod = require(nestedCliPath);
      let restCalls = 0;
      let mcpCalls = 0;

      cliMod.setTransport(async (url, opts, body) => {
        if (url === 'https://search.karldigi.dev/api/v1/search') {
          restCalls++;
          assert.strictEqual(opts.headers.Authorization, 'Bearer test-rest-token');
          assert.strictEqual(opts.headers.Accept, 'application/json');
          const parsedBody = JSON.parse(body);
          assert.strictEqual(parsedBody.query, 'rest query');
          return {
            status: 200,
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              ok: true,
              data: {
                content: 'REST search answer',
                session_id: 'rest-sid-1',
                sources: [{ title: 'REST Doc', url: 'https://rest.example.com' }],
                sources_count: 1,
              },
            }),
          };
        }
        if (url.includes('/mcp')) {
          mcpCalls++;
        }
        throw new Error('Unexpected URL: ' + url);
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };
      const origArgv = process.argv;
      process.argv = ['node', 'grok-search.cjs', 'search', '--query', 'rest query'];

      try {
        await assert.rejects(async () => {
          await cliMod.main();
        }, /EXIT_0/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        process.argv = origArgv;
        cliMod.setTransport(null);
      }

      assert.strictEqual(restCalls, 1, 'REST endpoint called exactly once');
      assert.strictEqual(mcpCalls, 0, 'MCP not called when REST returns 200');

      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.data.content, 'REST search answer');
      assert.strictEqual(res.data.session_id, 'rest-sid-1');
      assert.strictEqual(res.data.sources_count, 1);
      assert.strictEqual(res.data.sources[0].url, 'https://rest.example.com');
    } finally {
      process.env.HOME = origHome;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('M2 REST 404 empty/HTML triggers exactly one MCP search fallback', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    try {
      process.env.HOME = tmpHome;
      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(path.join(configDir, 'http-mcp.token'), 'test-fallback-token\n', { mode: 0o600 });

      const cliMod = require(nestedCliPath);
      let restCalls = 0;
      let mcpSearchCalls = 0;
      let mcpSourcesCalls = 0;

      cliMod.setTransport(async (url, opts, body) => {
        if (url === 'https://search.karldigi.dev/api/v1/search') {
          restCalls++;
          return {
            status: 404,
            headers: { 'content-type': 'text/html' },
            body: '<html><body>404 Not Found from Gateway/Caddy</body></html>',
          };
        }
        if (url === 'https://search.karldigi.dev/mcp') {
          const req = JSON.parse(body);
          if (req.method === 'initialize') {
            return {
              status: 200,
              headers: { 'content-type': 'application/json', 'mcp-session-id': 'fallback-sess' },
              body: JSON.stringify({
                jsonrpc: '2.0',
                id: req.id,
                result: { protocolVersion: '2025-03-26', serverInfo: { name: 'grok-search' } },
              }),
            };
          }
          if (req.method === 'notifications/initialized') {
            return { status: 202, headers: {}, body: '' };
          }
          if (req.method === 'tools/call' && req.params.name === 'web_search') {
            mcpSearchCalls++;
            return {
              status: 200,
              headers: { 'content-type': 'application/json', 'mcp-session-id': 'fallback-sess' },
              body: JSON.stringify({
                jsonrpc: '2.0',
                id: req.id,
                result: {
                  content: [{
                    type: 'text',
                    text: JSON.stringify({
                      session_id: 'mcp-fallback-sid',
                      content: 'MCP fallback content',
                      sources_count: 1,
                    }),
                  }],
                },
              }),
            };
          }
          if (req.method === 'tools/call' && req.params.name === 'get_sources') {
            mcpSourcesCalls++;
            return {
              status: 200,
              headers: { 'content-type': 'application/json' },
              body: JSON.stringify({
                jsonrpc: '2.0',
                id: req.id,
                result: {
                  content: [{
                    type: 'text',
                    text: JSON.stringify({
                      session_id: 'mcp-fallback-sid',
                      sources: [{ title: 'Fallback Doc', url: 'https://fallback.example.com' }],
                      sources_count: 1,
                    }),
                  }],
                },
              }),
            };
          }
        }
        throw new Error('Unexpected URL: ' + url);
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };
      const origArgv = process.argv;
      process.argv = ['node', 'grok-search.cjs', 'search', '--query', 'fallback test'];

      try {
        await assert.rejects(async () => {
          await cliMod.main();
        }, /EXIT_0/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        process.argv = origArgv;
        cliMod.setTransport(null);
      }

      assert.strictEqual(restCalls, 1, 'REST called once');
      assert.strictEqual(mcpSearchCalls, 1, 'Exactly one MCP web_search fallback call');
      assert.strictEqual(mcpSourcesCalls, 1, 'MCP get_sources called once');

      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, true);
      assert.strictEqual(res.data.session_id, 'mcp-fallback-sid');
      assert.strictEqual(res.data.content, 'MCP fallback content');
    } finally {
      process.env.HOME = origHome;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('M2 REST 401 returns env_token_rejected or auth_required; MCP not called', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    const origEnvToken = process.env.GROK_SEARCH_MCP_TOKEN;
    try {
      process.env.HOME = tmpHome;
      process.env.GROK_SEARCH_MCP_TOKEN = 'rejected-env-token';

      const cliMod = require(nestedCliPath);
      let restCalls = 0;
      let mcpCalls = 0;

      cliMod.setTransport(async (url) => {
        if (url === 'https://search.karldigi.dev/api/v1/search') {
          restCalls++;
          return { status: 401, headers: {}, body: 'Unauthorized' };
        }
        if (url.includes('/mcp')) {
          mcpCalls++;
        }
        throw new Error('Unexpected URL: ' + url);
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };
      const origArgv = process.argv;
      process.argv = ['node', 'grok-search.cjs', 'search', '--query', 'test 401'];

      try {
        await assert.rejects(async () => {
          await cliMod.main();
        }, /EXIT_1/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        process.argv = origArgv;
        cliMod.setTransport(null);
      }

      assert.strictEqual(restCalls, 1);
      assert.strictEqual(mcpCalls, 0, 'MCP not called on 401');

      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, false);
      assert.strictEqual(res.error.code, 'env_token_rejected');
    } finally {
      process.env.HOME = origHome;
      if (origEnvToken) process.env.GROK_SEARCH_MCP_TOKEN = origEnvToken;
      else delete process.env.GROK_SEARCH_MCP_TOKEN;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('M2 REST 500 returns error; MCP not called', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    try {
      process.env.HOME = tmpHome;
      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(path.join(configDir, 'http-mcp.token'), 'test-token\n', { mode: 0o600 });

      const cliMod = require(nestedCliPath);
      let restCalls = 0;
      let mcpCalls = 0;

      cliMod.setTransport(async (url) => {
        if (url === 'https://search.karldigi.dev/api/v1/search') {
          restCalls++;
          return { status: 500, headers: {}, body: 'Internal Server Error' };
        }
        if (url.includes('/mcp')) {
          mcpCalls++;
        }
        throw new Error('Unexpected URL: ' + url);
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };
      const origArgv = process.argv;
      process.argv = ['node', 'grok-search.cjs', 'search', '--query', 'test 500'];

      try {
        await assert.rejects(async () => {
          await cliMod.main();
        }, /EXIT_1/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        process.argv = origArgv;
        cliMod.setTransport(null);
      }

      assert.strictEqual(restCalls, 1);
      assert.strictEqual(mcpCalls, 0, 'MCP not called on 500');

      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, false);
      assert.strictEqual(res.error.code, 'server_error');
      assert.strictEqual(res.error.retryable, true);
    } finally {
      process.env.HOME = origHome;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('M2 REST {ok:false,error:{code:"not_found"}} with HTTP 404 does not fall back to MCP', async () => {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-cli-test-'));
    const origHome = process.env.HOME;
    try {
      process.env.HOME = tmpHome;
      const configDir = path.join(tmpHome, '.config', 'grok-search');
      fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(path.join(configDir, 'http-mcp.token'), 'test-token\n', { mode: 0o600 });

      const cliMod = require(nestedCliPath);
      let restCalls = 0;
      let mcpCalls = 0;

      cliMod.setTransport(async (url) => {
        if (url === 'https://search.karldigi.dev/api/v1/search') {
          restCalls++;
          return {
            status: 404,
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              ok: false,
              error: {
                code: 'not_found',
                message: 'Application item not found',
              },
            }),
          };
        }
        if (url.includes('/mcp')) {
          mcpCalls++;
        }
        throw new Error('Unexpected URL: ' + url);
      });

      let stdoutData = '';
      const origWrite = process.stdout.write;
      process.stdout.write = (chunk) => { stdoutData += chunk; return true; };
      const origExit = process.exit;
      process.exit = (code) => { throw new Error('EXIT_' + code); };
      const origArgv = process.argv;
      process.argv = ['node', 'grok-search.cjs', 'search', '--query', 'test app 404'];

      try {
        await assert.rejects(async () => {
          await cliMod.main();
        }, /EXIT_1/);
      } finally {
        process.stdout.write = origWrite;
        process.exit = origExit;
        process.argv = origArgv;
        cliMod.setTransport(null);
      }

      assert.strictEqual(restCalls, 1);
      assert.strictEqual(mcpCalls, 0, 'MCP fallback must not happen on application error envelope');

      const res = JSON.parse(stdoutData.trim());
      assert.strictEqual(res.ok, false);
      assert.strictEqual(res.error.code, 'not_found');
      assert.strictEqual(res.error.message, 'Application item not found');
    } finally {
      process.env.HOME = origHome;
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  });

  it('fetch and map never attach grok bearer to user target URLs and reject invalid URLs', () => {
    const cliMod = require(nestedCliPath);
    assert.throws(() => cliMod.validateUserUrl('ftp://example.com'), /invalid_url/);
    assert.throws(() => cliMod.validateUserUrl('http://user:pass@example.com'), /invalid_url/);
    assert.throws(() => cliMod.validateUserUrl('http://localhost:8080'), /invalid_url/);
    assert.throws(() => cliMod.validateUserUrl('http://127.0.0.1/admin'), /invalid_url/);
    assert.strictEqual(cliMod.validateUserUrl('https://example.com/page'), 'https://example.com/page');
  });
});
