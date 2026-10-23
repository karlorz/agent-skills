'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const unit = path.resolve(__dirname, '../../../skills/grok-search/skills/grok-search');
const profile = require(path.join(unit, 'references/connection-profile.json'));
const { validateProfile, validateDiscovery, fetchMetadata } = require(path.join(unit, 'scripts/check-connection-profile.cjs'));
function metadata() {
  return {
    resource: { resource: profile.resource, authorization_servers: [profile.origin],
      bearer_methods_supported: ['header'], scopes_supported: [...profile.scopes, 'config:write'] },
    auth: { issuer: profile.origin, authorization_endpoint: `${profile.origin}/authorize`,
      token_endpoint: `${profile.origin}/token`, registration_endpoint: `${profile.origin}/register`,
      scopes_supported: [...profile.scopes, 'config:write'], response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      code_challenge_methods_supported: ['S256'], token_endpoint_auth_methods_supported: ['none'] }
  };
}
test('checked discovery builds the typed request without escalating supported scopes', () => {
  const { resource, auth } = metadata();
  const request = validateDiscovery(profile, resource, auth);
  assert.equal(request.scopes, 'mcp offline_access');
  assert.equal(request.registration_url, auth.registration_endpoint);
  assert.equal(request.issuer_domain, 'search.karldigi.dev');
  assert.equal(request.token_endpoint_auth_method, 'none');
  assert.equal(request.resource, profile.resource);
  assert(!('reconnect' in request));
  assert(!('client_secret' in request));
});
for (const [name, mutate] of [
  ['different resource', m => { m.resource.resource += '/other'; }],
  ['different issuer', m => { m.auth.issuer = 'https://example.com'; }],
  ['extra authorization server', m => { m.resource.authorization_servers.push('https://example.com'); }],
  ['missing resource scope', m => { m.resource.scopes_supported = ['mcp']; }],
  ['missing auth scope', m => { m.auth.scopes_supported = ['mcp']; }],
  ['missing PKCE', m => { m.auth.code_challenge_methods_supported = ['plain']; }],
  ['missing refresh', m => { m.auth.grant_types_supported = ['authorization_code']; }],
  ['missing public client auth', m => { m.auth.token_endpoint_auth_methods_supported = ['client_secret_basic']; }],
  ['cross-origin token endpoint', m => { m.auth.token_endpoint = 'https://example.com/token'; }],
  ['credential URL', m => { m.auth.authorization_endpoint = 'https://secret@search.karldigi.dev/authorize'; }],
  ['endpoint query', m => { m.auth.registration_endpoint += '?redirect=https://example.com'; }],
  ['invalid revocation', m => { m.auth.revocation_endpoint = 'http://127.0.0.1/revoke'; }]
]) test(`setup fails before a credential request: ${name}`, () => {
  const m = metadata(); mutate(m);
  assert.throws(() => validateDiscovery(profile, m.resource, m.auth));
});
test('profile rejects scope escalation and extra helper tools', () => {
  for (const field of ['scopes', 'allowed_tools']) {
    const changed = structuredClone(profile);
    changed[field].push(field === 'scopes' ? 'config:write' : 'switch_model');
    assert.throws(() => validateProfile(changed));
  }
});
test('metadata fetch is bounded, credential-free and does not follow redirects', async () => {
  let calls = 0;
  assert.deepEqual(await fetchMetadata(profile.authorization_server_metadata, async (url, options) => {
    calls++;
    assert.equal(url, profile.authorization_server_metadata);
    assert.equal(options.redirect, 'error');
    assert(options.signal instanceof AbortSignal);
    assert.deepEqual(options.headers, { Accept: 'application/json' });
    return new Response('{"ok":true}');
  }), { ok: true });
  assert.equal(calls, 1);
  await assert.rejects(fetchMetadata(profile.authorization_server_metadata, async () => new Response('x'.repeat(65537))), /64 KiB/);
  await assert.rejects(fetchMetadata(profile.authorization_server_metadata, async () => new Response('{}', { status: 302 })), /HTTP/);
});
test('copied skill keeps profile, checker and all local document references', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'grok setup '));
  try {
    const dest = path.join(dir, 'installed skill');
    fs.cpSync(unit, dest, { recursive: true });
    const checker = require(path.join(dest, 'scripts/check-connection-profile.cjs'));
    checker.validateProfile(require(path.join(dest, 'references/connection-profile.json')));
    for (const file of [path.join(dest, 'SKILL.md'), ...fs.readdirSync(path.join(dest, 'references')).filter(f => f.endsWith('.md')).map(f => path.join(dest, 'references', f))]) {
      for (const match of fs.readFileSync(file, 'utf8').matchAll(/\]\(([^)]+)\)/g)) {
        const target = match[1].split('#')[0];
        if (!target || /^[a-z]+:/i.test(target)) continue;
        assert(fs.existsSync(path.resolve(path.dirname(file), target)), `Missing packaged link in ${file}: ${target}`);
      }
    }
    assert(!fs.existsSync(path.join(dest, 'bin/dynamic_credentials.py')));
    assert(!fs.existsSync(path.join(dest, 'connector.yaml')));
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
