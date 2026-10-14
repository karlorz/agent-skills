'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync, execFileSync } = require('node:child_process');
const cliPath = path.resolve(__dirname, '../../../skills/grok-search/skills/grok-search/scripts/grok-search.cjs');
const cli = require(cliPath);
const origin = 'https://search.karldigi.dev';
const privateSecret = 'dummy-collector-must-stay-private';
const start = () => ({ approveUrl: origin + '/auth/cli/approve?ref=dummy-browser-reference', authRunId: 'dummy-run', pollSecret: privateSecret, expiresAt: new Date(Date.now() + 300000).toISOString(), intervalSeconds: 2 });

async function fixture(args, transport, setup = () => {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-contract-'));
  const dir = path.join(home, '.config/grok-search');
  const saved = { home: process.env.HOME, token: process.env.GROK_SEARCH_MCP_TOKEN, argv: process.argv, stdout: process.stdout.write, stderr: process.stderr.write, tty: process.stderr.isTTY };
  let stdout = '', stderr = '', failure;
  try {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    process.env.HOME = home;
    process.env.GROK_SEARCH_MCP_TOKEN = 'dummy-env-bearer';
    process.argv = ['node', cliPath, ...args];
    cli.setTransport(transport);
    process.stdout.write = c => { stdout += c; return true; };
    process.stderr.write = c => { stderr += c; return true; };
    setup({ home, dir });
    try { await cli.main(); } catch (err) { failure = err; }
    const lines = stdout.trim() ? stdout.trim().split('\n').map(JSON.parse) : [];
    return { json: lines[0], lines, stdout, stderr, failure, pending: fs.existsSync(path.join(dir, 'cli-auth.json')), lock: fs.existsSync(path.join(dir, 'cli-auth.lock')), files: fs.readdirSync(dir), meta: fs.existsSync(path.join(dir, 'token-meta.json')) ? JSON.parse(fs.readFileSync(path.join(dir, 'token-meta.json'))) : null };
  } finally {
    process.env.HOME = saved.home;
    if (saved.token === undefined) delete process.env.GROK_SEARCH_MCP_TOKEN; else process.env.GROK_SEARCH_MCP_TOKEN = saved.token;
    process.argv = saved.argv;
    process.stdout.write = saved.stdout;
    process.stderr.write = saved.stderr;
    process.stderr.isTTY = saved.tty;
    cli.setTransport(null);
    fs.rmSync(home, { recursive: true, force: true });
  }
}
function json(body, status = 200, headers = {}) { return { status, headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) }; }
function pending(dir, fields = {}) { fs.writeFileSync(path.join(dir, 'cli-auth.json'), JSON.stringify({ ...start(), origin, ...fields }), { mode: 0o600 }); }

for (const approveUrl of ['http://search.karldigi.dev/auth/cli/approve?ref=x', 'https://foreign.invalid/auth/cli/approve?ref=x', 'https://user:password@search.karldigi.dev/auth/cli/approve?ref=x', origin + '/auth/cli/approve?ref=' + privateSecret]) {
  test('auth-start rejects an unsafe approval link: ' + new URL(approveUrl).hostname, async () => {
    const result = await fixture(['auth-start'], async () => json({ ...start(), approveUrl }));
    assert.equal(result.json.error.code, 'invalid_auth_start_response');
    assert.equal(result.pending, false);
    assert.equal(result.lock, false);
    assert(!result.stdout.includes(privateSecret));
  });
}

test('start/status share a lock; a live pending run cannot be overwritten', async () => {
  let calls = 0;
  const existing = await fixture(['auth-start'], async () => { calls++; return json(start()); }, ({ dir }) => pending(dir));
  assert.equal(calls, 0);
  assert.equal(existing.json.error.code, 'concurrent_auth_start');
  for (const command of ['auth-start', 'auth-status']) {
    const locked = await fixture([command], async () => { calls++; }, ({ dir }) => {
      const lock = path.join(dir, 'cli-auth.lock');
      fs.writeFileSync(lock, 'dummy-owner', { mode: 0o600 });
      fs.utimesSync(lock, new Date(0), new Date(0));
      pending(dir);
    });
    assert.equal(locked.json.error.code, 'concurrent_auth_start');
    assert.equal(locked.lock, true, 'even an old lock must not be stolen');
  }
  assert.equal(calls, 0);
});

test('status rejects wrong origin and expired state before private polling', async () => {
  let calls = 0;
  const wrong = await fixture(['auth-status'], async () => { calls++; }, ({ dir }) => pending(dir, { origin: 'https://foreign.invalid' }));
  assert.equal(wrong.json.error.code, 'corrupted_auth_state');
  const expired = await fixture(['auth-status'], async () => { calls++; }, ({ dir }) => pending(dir, { expiresAt: '2000-01-01T00:00:00Z' }));
  assert.equal(expired.json.error.code, 'auth_expired');
  assert.equal(expired.pending, false);
  assert.equal(calls, 0);
});

test('status uses actual expires_in and removes pending state only after private persistence', async () => {
  const result = await fixture(['auth-status'], async (url, opts) => {
    assert.equal(opts.headers['X-CLI-Poll-Secret'], privateSecret);
    return json({ status: 'success', token: 'dummy-new-access', expires_in: 123 });
  }, ({ dir }) => pending(dir));
  assert.equal(result.json.data.status, 'authenticated');
  assert(Date.parse(result.meta.expiresAt) > Date.now() + 120000);
  assert(Date.parse(result.meta.expiresAt) < Date.now() + 124000);
  assert.equal(result.meta.origin, origin);
  assert.equal(result.pending, false);
  assert.equal(result.lock, false);
  assert(!result.stdout.includes('dummy-new-access') && !result.stdout.includes(privateSecret));
});

test('partial credential write fails without leftover temp or usable token', async () => {
  const result = await fixture(['auth-status'], async () => json({ status: 'success', token: 'dummy-new-access', expires_in: 123 }), ({ home, dir }) => {
    pending(dir);
    fs.symlinkSync(path.join(home, 'missing'), path.join(dir, 'http-mcp.token'));
  });
  assert.equal(result.json.error.code, 'token_save_failed');
  assert.equal(result.pending, true);
  assert(!result.files.some(name => name.startsWith('.tmp-')));
  assert(!result.files.includes('token-meta.json'));
  assert.equal(result.lock, false);
});

test('credential directory and dangling token symlinks are rejected', async () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-symlink-'));
  const oldHome = process.env.HOME, oldToken = process.env.GROK_SEARCH_MCP_TOKEN;
  try {
    process.env.HOME = home;
    delete process.env.GROK_SEARCH_MCP_TOKEN;
    fs.symlinkSync(path.join(home, 'missing'), path.join(home, '.config'));
    assert.throws(() => cli.getTokenResolution(), /symlink_rejected/);
    fs.unlinkSync(path.join(home, '.config'));
    fs.mkdirSync(path.join(home, '.config/grok-search'), { recursive: true });
    fs.symlinkSync(path.join(home, 'missing'), path.join(home, '.config/grok-search/http-mcp.token'));
    assert.throws(() => cli.getTokenResolution(), /symlink_rejected/);
  } finally {
    process.env.HOME = oldHome;
    if (oldToken === undefined) delete process.env.GROK_SEARCH_MCP_TOKEN; else process.env.GROK_SEARCH_MCP_TOKEN = oldToken;
    fs.rmSync(home, { recursive: true, force: true });
  }
});

test('SSE selects matching response across CRLF, multiline data and unrelated notifications', () => {
  const stream = 'event: message\r\ndata: {"jsonrpc":"2.0","id":7,\r\ndata: "result":{"content":[]}}\r\n\r\ndata: {"jsonrpc":"2.0","method":"notifications/progress"}\r\n\r\n';
  assert.equal(cli.decodeMcpResponse('text/event-stream', stream, 7).id, 7);
  assert.throws(() => cli.decodeMcpResponse('text/event-stream', stream, 8), /mcp_response_mismatch/);
});

for (const scenario of ['mismatched-id', 'unsupported-protocol', 'ambiguous-rest', 'ambiguous-mcp', 'sources-failure']) {
  test('transport fails without replay: ' + scenario, async () => {
    let searches = 0, rest = 0;
    const result = await fixture(['search', '--query', 'dummy query'], async (url, opts, body) => {
      if (url.includes('/api/v1/')) {
        rest++;
        if (scenario === 'ambiguous-rest') throw new Error('dummy-private-upstream');
        return { status: 404, headers: {}, body: 'Not Found' };
      }
      if (opts.method === 'DELETE') return json({});
      const req = JSON.parse(body);
      if (req.method === 'initialize') return json({ jsonrpc: '2.0', id: scenario === 'mismatched-id' ? 999 : req.id, result: { protocolVersion: scenario === 'unsupported-protocol' ? 'unknown' : '2025-03-26', capabilities: { tools: {} } } }, 200, { 'mcp-session-id': 'dummy-session' });
      if (req.method === 'notifications/initialized') return { status: 202, headers: {}, body: '' };
      assert.equal(opts.headers['Mcp-Session-Id'], 'dummy-session');
      if (req.params.name === 'web_search') {
        searches++;
        if (scenario === 'ambiguous-mcp') throw new Error('dummy-private-upstream');
        return json({ jsonrpc: '2.0', id: req.id, result: { structuredContent: { content: 'Dummy answer', session_id: 'dummy-source-session' }, content: [{ type: 'text', text: 'wrong-text-must-not-win' }] } });
      }
      assert.equal(req.params.name, 'get_sources');
      assert.equal(req.params.arguments.session_id, 'dummy-source-session');
      return json({ jsonrpc: '2.0', id: req.id, error: { code: -32603, message: 'dummy-private-upstream' } });
    });
    assert.equal(rest, 1);
    assert.equal(searches, ['ambiguous-mcp', 'sources-failure'].includes(scenario) ? 1 : 0);
    assert(!result.stdout.includes('dummy-private-upstream'));
    assert(!result.json || result.json.ok === false);
  });
}

test('strict integer options and private literal targets are rejected before requests', async () => {
  let calls = 0;
  for (const args of [ ['map', '--url', 'https://example.com', '--depth', '2junk'], ['search', '--query', 'dummy', '--extra-sources', '1.2'], ['fetch', '--url', 'http://10.1.2.3'], ['fetch', '--url', 'http://[::ffff:127.0.0.1]'], ['map', '--url', 'http://192.168.1.1'] ]) {
    const result = await fixture(args, async () => { calls++; });
    assert.equal(result.json.ok, false);
  }
  assert.equal(calls, 0);
});

test('pinned sparse fixture install runs independently with spaces and untouched host configuration', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'grok install '));
  const git = (args, cwd) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  try {
    const fixtureRepo = path.join(root, 'fixture repo');
    const unit = 'skills/grok-search/skills/grok-search';
    fs.mkdirSync(fixtureRepo);
    fs.cpSync(path.resolve(path.dirname(cliPath), '..'), path.join(fixtureRepo, unit), { recursive: true });
    git(['init', '-q'], fixtureRepo);
    git(['add', '.'], fixtureRepo);
    git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'pinned fixture'], fixtureRepo);
    const sha = git(['rev-parse', 'HEAD'], fixtureRepo);
    const checkout = path.join(root, 'staging');
    git(['clone', '--no-checkout', fixtureRepo, checkout], root);
    git(['sparse-checkout', 'set', 'skills/grok-search'], checkout);
    git(['checkout', '--detach', sha], checkout);
    const installed = path.join(root, 'host skills/grok-search');
    fs.cpSync(path.join(checkout, unit), installed, { recursive: true });
    assert(fs.existsSync(path.join(installed, 'SKILL.md')));
    for (const unwanted of ['.mcp.json', 'mcp.json', '.claude-plugin', '.cursor-plugin', '.codex-plugin', 'hooks']) assert(!fs.existsSync(path.join(installed, unwanted)));
    fs.rmSync(checkout, { recursive: true });
    fs.rmSync(fixtureRepo, { recursive: true });
    fs.writeFileSync(path.join(root, 'mcp.json'), '{"untouched":true}');
    const preload = path.join(root, 'fixture.cjs');
    fs.writeFileSync(preload, `require(${JSON.stringify(path.join(installed, 'scripts/grok-search.cjs'))}).setTransport(async () => (${JSON.stringify(json({ ok: true, data: { content: 'Fixture answer', session_id: 'fixture-session', sources: [{ url: 'https://example.com' }], sources_count: 1 } }))})); setImmediate(() => require(${JSON.stringify(path.join(installed, 'scripts/grok-search.cjs'))}).run());`);
    const result = spawnSync(process.execPath, ['--require', preload, path.join(installed, 'scripts/grok-search.cjs'), 'search', '--query', 'fixture'], { cwd: os.tmpdir(), encoding: 'utf8', env: { HOME: root, PATH: path.dirname(process.execPath), GROK_SEARCH_MCP_TOKEN: 'dummy-fixture-access' } });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).data.sources.length, 1);
    assert.equal(fs.readFileSync(path.join(root, 'mcp.json'), 'utf8'), '{"untouched":true}');
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});


test('file metadata origin and expiry fail closed while env retains precedence', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-meta-'));
  const oldHome = process.env.HOME, oldToken = process.env.GROK_SEARCH_MCP_TOKEN;
  const dir = path.join(home, '.config/grok-search');
  try {
    process.env.HOME = home;
    delete process.env.GROK_SEARCH_MCP_TOKEN;
    fs.mkdirSync(dir, {recursive: true});
    fs.writeFileSync(path.join(dir, 'http-mcp.token'), 'dummy-file-access');
    fs.writeFileSync(path.join(dir, 'token-meta.json'), JSON.stringify({ origin: 'https://foreign.invalid' }));
    assert.throws(() => cli.getTokenResolution(), /invalid_token_origin/);
    fs.writeFileSync(path.join(dir, 'token-meta.json'), JSON.stringify({ origin, expiresAt: '2000-01-01T00:00:00Z' }));
    assert.equal(cli.getTokenResolution().source, 'expired');
    process.env.GROK_SEARCH_MCP_TOKEN = 'dummy-env-override';
    assert.equal(cli.getTokenResolution().source, 'env');
    assert.equal(fs.statSync(dir).mode & 0o777, 0o700);
    assert.equal(fs.statSync(path.join(dir, 'http-mcp.token')).mode & 0o777, 0o600);
    delete process.env.GROK_SEARCH_MCP_TOKEN;
    const original = fs.lstatSync;
    try {
      fs.lstatSync = target => { const stat = original(target); stat.uid = process.getuid() + 1; return stat; };
      assert.throws(() => cli.getTokenResolution(), /unsafe_owner/);
    } finally { fs.lstatSync = original; }
  } finally {
    process.env.HOME = oldHome;
    if (oldToken === undefined) delete process.env.GROK_SEARCH_MCP_TOKEN; else process.env.GROK_SEARCH_MCP_TOKEN = oldToken;
    fs.rmSync(home, { recursive: true, force: true });
  }
});

test('native HTTP path caps response bytes and exits without replay or raw error output', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'grok-native-cap-'));
  try {
    const preload = path.join(root, 'native-cap.cjs');
    fs.writeFileSync(preload, `
      const https = require('node:https');
      const { EventEmitter } = require('node:events');
      let calls = 0;
      https.request = (options, callback) => {
        calls++;
        const req = new EventEmitter();
        req.write = () => {};
        req.destroy = () => { req.emit('error', new Error('dummy-private-diagnostic')); };
        req.end = () => setImmediate(() => {
          const res = new EventEmitter();
          res.setEncoding = () => {};
          res.statusCode = 200; res.headers = { 'content-type': 'application/json' };
          callback(res);
          res.emit('data', 'x'.repeat(10 * 1024 * 1024 + 1));
        });
        return req;
      };
      process.on('exit', () => { if (calls !== 1) process.exitCode = 99; });
    `);
    const result = spawnSync(process.execPath, ['--require', preload, cliPath, 'search', '--query', 'fixture'], { encoding: 'utf8', env: { HOME: root, GROK_SEARCH_MCP_TOKEN: 'dummy-native-access' }, timeout: 5000 });
    assert.equal(result.status, 1, result.stderr);
    assert.equal(JSON.parse(result.stdout).error.code, 'transport_error');
    assert(!result.stdout.includes('dummy-private-diagnostic'));
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});


test('structured scalar fetch/map content is normalized without object coercion', async () => {
  try {
    cli.setTransport(async (url, options, body) => {
      const req = JSON.parse(body);
      return json({ jsonrpc: '2.0', id: req.id, result: { structuredContent: { result: 'Dummy page text' }, content: [{type: 'text', text: 'wrong-text'}] } });
    });
    const client = new cli.HiddenMcpClient(origin, 'dummy-access', 'env');
    assert.equal(await client.callTool('web_fetch', {url:'https://example.com'}), 'Dummy page text');
    assert.equal(await client.callTool('web_map', {url:'https://example.com'}), 'Dummy page text');
  } finally { cli.setTransport(null); }
});

test('HTTP 200 upstream failure sentinels are redacted without MCP fallback', async () => {
  for (const [command, content] of [['search', 'upstream_error: dummy-private-provider-body'], ['fetch', '提取失败: dummy-private-provider-body'], ['map', '映射错误: dummy-private-provider-body']]) {
    let calls = 0;
    const result = await fixture([command, command === 'search' ? '--query' : '--url', command === 'search' ? 'dummy' : 'https://example.com'], async () => { calls++; return json({ok:true,data:{content}}); });
    assert.equal(result.json.ok, false);
    assert.equal(calls, 1);
    assert(!result.stdout.includes('dummy-private-provider-body'));
  }
});

test('explicit expired-session 404 reinitializes once; a second expiry stops', async () => {
  let initialized = 0, tools = 0;
  try {
    cli.setTransport(async (url, options, body) => {
      const request = JSON.parse(body);
      if (request.method === 'initialize') {
        initialized++;
        return json({jsonrpc:'2.0',id:request.id,result:{protocolVersion:'2025-03-26',capabilities:{tools:{}}}}, 200, {'mcp-session-id':'dummy-session-' + initialized});
      }
      if (request.method === 'notifications/initialized') return {status:202, headers:{}, body:''};
      tools++;
      return {status:404, headers:{}, body:'Session not found'};
    });
    const client = new cli.HiddenMcpClient(origin, 'dummy-access', 'env');
    await client.initialize();
    await assert.rejects(client.callTool('web_search', {query:'dummy'}), /mcp_session_expired/);
    assert.equal(initialized, 2);
    assert.equal(tools, 2, 'one explicit rejection permits only one safe retry');
  } finally { cli.setTransport(null); }
});
