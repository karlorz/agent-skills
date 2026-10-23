'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const unit = path.resolve(__dirname, '../../../skills/grok-search/skills/grok-search');
const cliPath = path.join(unit, 'scripts/grok-search.cjs');
const { normalizeEndpoint, profileForEndpoint, DEFAULT_MCP_URL } = require(path.join(unit, 'scripts/lib/endpoint.cjs'));
const { validateDiscovery } = require(path.join(unit, 'scripts/check-connection-profile.cjs'));
const custom = 'https://alternate.example/agent/mcp';
const other = 'https://alternate.example/other/mcp';
function fixture(fn) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'grok endpoints '));
  try { return fn(home); } finally { fs.rmSync(home, { recursive: true, force: true }); }
}
function state(home, url = DEFAULT_MCP_URL) {
  const base = path.join(home, '.config/grok-search');
  return url === DEFAULT_MCP_URL ? base : path.join(base, 'servers', crypto.createHash('sha256').update(url).digest('hex'));
}
function run(home, args, transport = `throw new Error('unexpected_network')`, env = {}) {
  const log = path.join(home, 'last-calls.json');
  const script = `const fs=require('node:fs'); const path=require('node:path');
const cli=require(${JSON.stringify(cliPath)});const calls=[];
function reply(data,status=200){return {status,headers:{'content-type':'application/json'},body:JSON.stringify(data)}}
cli.setTransport(async(url,options,body)=>{calls.push({url,options,body});${transport}});
process.argv=['node',${JSON.stringify(cliPath)},...${JSON.stringify(args)}];
cli.run().then(()=>fs.writeFileSync(${JSON.stringify(log)},JSON.stringify(calls)));`;
  const childEnv = { ...process.env, HOME: home };
  delete childEnv.GROK_SEARCH_MCP_TOKEN;
  delete childEnv.GROK_SEARCH_MCP_TOKEN_RESOURCE;
  Object.assign(childEnv, env);
  const result = spawnSync(process.execPath, ['-e', script], { encoding: 'utf8', env: childEnv });
  assert(!result.error, result.error?.message);
  assert.equal(result.stderr, '');
  return { status: result.status, output: JSON.parse(result.stdout), calls: JSON.parse(fs.readFileSync(log, 'utf8')) };
}
const searchTransport = `
if (options.method==='DELETE') return reply({},204);
const request=JSON.parse(body);
if(request.method==='initialize') return reply({jsonrpc:'2.0',id:request.id,result:{protocolVersion:'2025-03-26',capabilities:{tools:{}}}});
if(request.method==='notifications/initialized') return reply({},202);
if(request.params.name==='web_search') return reply({jsonrpc:'2.0',id:request.id,result:{structuredContent:{content:'fixture answer',session_id:'fixture-session'}}});
if(request.params.name==='get_sources') return reply({jsonrpc:'2.0',id:request.id,result:{structuredContent:{sources:[{url:'https://example.com/source'}]}}});
throw new Error('unexpected_request');`;
test('default has no setup requirement; selection persists and an identical selection is a no-op', () => fixture(home => {
  assert.equal(run(home, ['configure']).output.data.mcpUrl, DEFAULT_MCP_URL);
  assert(!fs.existsSync(path.join(state(home), 'endpoint.json')));
  assert.equal(run(home, ['configure', '--mcp-url', custom]).output.data.changed, true);
  const file = path.join(state(home), 'endpoint.json');
  const before = fs.statSync(file).mtimeMs;
  assert.equal(run(home, ['configure']).output.data.mcpUrl, custom);
  assert.equal(run(home, ['configure', '--mcp-url', custom]).output.data.changed, false);
  assert.equal(fs.statSync(file).mtimeMs, before);
  assert.equal(fs.statSync(file).mode & 0o777, 0o600);
}));
test('invalid explicit addresses fail without replacing a saved choice or making requests', () => fixture(home => {
  run(home, ['configure', '--mcp-url', custom]);
  for (const url of ['http://alternate.example/mcp','https://user:secret@alternate.example/mcp',custom+'?token=secret',custom+'#fragment',custom+'?',custom+'#','ftp://alternate.example/mcp','not-a-url']) {
    const result = run(home, ['configure', '--mcp-url', url]);
    assert.equal(result.output.error.code, 'invalid_mcp_url');
    assert.equal(result.calls.length, 0);
    assert.equal(run(home, ['configure']).output.data.mcpUrl, custom);
  }
}));
test('custom deployment cannot inherit the production file or an unbound environment token', () => fixture(home => {
  fs.mkdirSync(state(home), { recursive: true });
  fs.writeFileSync(path.join(state(home), 'http-mcp.token'), 'dummy-production-token');
  run(home, ['configure', '--mcp-url', custom]);
  let result = run(home, ['search', '--query', 'fixture']);
  assert.equal(result.output.error.code, 'auth_required');
  assert.deepEqual(result.calls, []);
  result = run(home, ['search', '--query', 'fixture'], searchTransport, { GROK_SEARCH_MCP_TOKEN: 'dummy-production-env' });
  assert.equal(result.output.error.code, 'env_token_resource_mismatch');
  assert.deepEqual(result.calls, []);
  result = run(home, ['search', '--query', 'fixture'], searchTransport, { GROK_SEARCH_MCP_TOKEN: 'dummy-custom-token', GROK_SEARCH_MCP_TOKEN_RESOURCE: custom });
  assert.equal(result.output.ok, true);
  assert.equal(result.output.data.sources_count, 1);
  assert(result.calls.every(call => call.url === custom));
  run(home, ['configure', '--mcp-url', DEFAULT_MCP_URL]);
  result = run(home, ['search', '--query', 'fixture'], `return reply({ok:true,data:{content:'default fixture',sources:[]}});`);
  assert.equal(result.output.ok, true);
  assert.equal(result.calls[0].options.headers.Authorization, 'Bearer dummy-production-token');
}));
test('custom pairing binds pending state and credentials to the selected exact resource', () => fixture(home => {
  run(home, ['configure', '--mcp-url', custom]);
  const started = run(home, ['auth-start'], `return reply({authRunId:'dummy-run',pollSecret:'dummy-private',approveUrl:'https://alternate.example/auth/cli/approve?ref=dummy',expiresAt:new Date(Date.now()+300000).toISOString(),intervalSeconds:2});`);
  assert.equal(started.output.ok, true);
  assert.equal(started.calls[0].url, 'https://alternate.example/auth/cli/start');
  const pending = path.join(state(home, custom), 'cli-auth.json');
  assert.equal(JSON.parse(fs.readFileSync(pending)).resource, custom);
  run(home, ['configure', '--mcp-url', other]);
  assert.equal(run(home, ['auth-status']).output.error.code, 'no_pending_auth');
  assert(fs.existsSync(pending));
  run(home, ['configure', '--mcp-url', custom]);
  const claimed = run(home, ['auth-status'], `return reply({status:'success',token:'dummy-custom-file-token',expires_in:300});`);
  assert.equal(claimed.output.data.status, 'authenticated');
  const meta = JSON.parse(fs.readFileSync(path.join(state(home, custom), 'token-meta.json')));
  assert.equal(meta.resource, custom);
  assert.equal(meta.origin, 'https://alternate.example');
  assert.equal(run(home, ['search','--query','fixture'], searchTransport).output.ok, true);
  run(home, ['configure', '--mcp-url', other]);
  assert.equal(run(home, ['search','--query','fixture']).output.error.code, 'auth_required');
}));
test('a concurrent address change cannot move an in-flight credential to the new resource', () => fixture(home => {
  run(home, ['configure','--mcp-url',custom]);
  const result = run(home, ['search','--query','fixture'], `fs.writeFileSync(path.join(process.env.HOME,'.config/grok-search/endpoint.json'),JSON.stringify({schemaVersion:1,mcpUrl:${JSON.stringify(other)}}));${searchTransport}`, { GROK_SEARCH_MCP_TOKEN:'dummy-bound-token',GROK_SEARCH_MCP_TOKEN_RESOURCE:custom });
  assert.equal(result.output.ok, true);
  assert(result.calls.every(call => call.url === custom));
  assert.equal(run(home, ['configure']).output.data.mcpUrl, other);
}));
test('invalid saved state fails closed instead of silently falling back to production', () => fixture(home => {
  fs.mkdirSync(state(home), {recursive:true});
  const file=path.join(state(home),'endpoint.json');
  fs.writeFileSync(file,'{');
  assert.equal(run(home,['configure']).output.error.code,'invalid_endpoint_settings');
  fs.unlinkSync(file);fs.symlinkSync(path.join(home,'missing'),file);
  assert.equal(run(home,['configure']).output.error.code,'symlink_rejected');
}));
test('custom discovery gets a separate connector identity and rejects production-resource metadata', () => {
  const profile = profileForEndpoint(custom);
  assert.equal(profile.resource, custom);
  assert.equal(profile.protected_resource_metadata, 'https://alternate.example/.well-known/oauth-protected-resource/agent/mcp');
  assert.notEqual(profile.provider, profileForEndpoint().provider);
  assert.notEqual(profile.provider, profileForEndpoint(other).provider);
  const resource = {resource:custom,authorization_servers:[profile.origin],bearer_methods_supported:['header'],scopes_supported:['mcp','offline_access']};
  const auth = {issuer:profile.origin,authorization_endpoint:profile.origin+'/authorize',token_endpoint:profile.origin+'/token',registration_endpoint:profile.origin+'/register',scopes_supported:resource.scopes_supported,code_challenge_methods_supported:['S256'],response_types_supported:['code'],grant_types_supported:['authorization_code','refresh_token'],token_endpoint_auth_methods_supported:['none']};
  assert.equal(validateDiscovery(profile,resource,auth).resource,custom);
  assert.throws(()=>validateDiscovery(profile,{...resource,resource:DEFAULT_MCP_URL},auth));
  assert.equal(normalizeEndpoint(custom),custom);
});

test('root MCP resources use root protected-resource discovery', () => {
  const profile = profileForEndpoint('https://alternate.example');
  assert.equal(profile.resource, 'https://alternate.example/');
  assert.equal(profile.protected_resource_metadata, 'https://alternate.example/.well-known/oauth-protected-resource');
});
test('custom metadata and pending state with another resource fail before requests', () => fixture(home => {
  run(home, ['configure','--mcp-url',custom]);
  fs.mkdirSync(state(home,custom),{recursive:true});
  fs.writeFileSync(path.join(state(home,custom),'cli-auth.json'),JSON.stringify({origin:'https://alternate.example',resource:other,authRunId:'dummy-run',pollSecret:'dummy-private',expiresAt:new Date(Date.now()+300000).toISOString()}));
  let result=run(home,['auth-status']);
  assert.equal(result.output.error.code,'corrupted_auth_state');assert.deepEqual(result.calls,[]);
  fs.writeFileSync(path.join(state(home,custom),'http-mcp.token'),'dummy-token');
  fs.writeFileSync(path.join(state(home,custom),'token-meta.json'),JSON.stringify({origin:'https://alternate.example',resource:other}));
  result=run(home,['search','--query','fixture']);
  assert.equal(result.output.error.code,'invalid_token_origin');assert.deepEqual(result.calls,[]);
}));
test('a custom endpoint redirect does not replay against production or another host', () => fixture(home => {
  run(home,['configure','--mcp-url',custom]);
  const result=run(home,['search','--query','fixture'],`return {status:302,headers:{location:'https://search.karldigi.dev/mcp'},body:''};`,{GROK_SEARCH_MCP_TOKEN:'dummy-custom',GROK_SEARCH_MCP_TOKEN_RESOURCE:custom});
  assert.equal(result.output.error.code,'transport_error');assert.equal(result.calls.length,1);assert.equal(result.calls[0].url,custom);
}));
