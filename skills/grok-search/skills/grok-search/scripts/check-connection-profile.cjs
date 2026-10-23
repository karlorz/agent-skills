#!/usr/bin/env node
'use strict';
// Credential-free policy check. Never registers a client or requests a token.
const { profileForEndpoint } = require('./lib/endpoint.cjs');

function requireThat(condition, field) {
  if (!condition) throw new Error(`Connection policy mismatch: ${field}`);
}
function pinnedURL(value, origin, field) {
  let url;
  try { url = new URL(value); } catch { throw new Error(`Invalid metadata URL: ${field}`); }
  requireThat(url.protocol === 'https:' && url.origin === origin &&
    !url.username && !url.password && !url.hash && !url.search, field);
  return url;
}
function validateProfile(p) {
  requireThat(p.schema_version === 1, 'schema_version');
  const origin = pinnedURL(p.origin, p.origin, 'origin');
  requireThat(origin.href === `${p.origin}/`, 'origin must have no path');
  const resource = pinnedURL(p.resource, p.origin, 'resource');
  requireThat(JSON.stringify(p.api_hosts) === JSON.stringify([resource.hostname]), 'api_hosts');
  requireThat(JSON.stringify(p.scopes) === JSON.stringify(['mcp', 'offline_access']), 'scopes');
  requireThat(p.provider === profileForEndpoint(p.resource).provider, 'provider');
  requireThat(JSON.stringify(p.allowed_tools) === JSON.stringify([
    'web_search', 'web_fetch', 'web_map', 'get_sources', 'get_config_info'
  ]), 'allowed_tools');
  pinnedURL(p.protected_resource_metadata, p.origin, 'protected_resource_metadata');
  pinnedURL(p.authorization_server_metadata, p.origin, 'authorization_server_metadata');
}
function includesAll(value, required, field) {
  requireThat(Array.isArray(value) && required.every(item => value.includes(item)), field);
}
function validateDiscovery(p, resource, auth) {
  validateProfile(p);
  requireThat(resource.resource === p.resource, 'resource');
  requireThat(JSON.stringify(resource.authorization_servers) === JSON.stringify([p.origin]), 'authorization_servers');
  includesAll(resource.bearer_methods_supported, ['header'], 'bearer_methods_supported');
  includesAll(resource.scopes_supported, p.scopes, 'resource scopes_supported');
  requireThat(auth.issuer === p.origin, 'issuer');
  includesAll(auth.scopes_supported, p.scopes, 'authorization scopes_supported');
  includesAll(auth.code_challenge_methods_supported, ['S256'], 'PKCE S256');
  includesAll(auth.response_types_supported, ['code'], 'response_types_supported');
  includesAll(auth.grant_types_supported, ['authorization_code', 'refresh_token'], 'grant_types_supported');
  includesAll(auth.token_endpoint_auth_methods_supported, ['none'], 'token_endpoint_auth_methods_supported');
  for (const field of ['authorization_endpoint', 'token_endpoint', 'registration_endpoint']) {
    pinnedURL(auth[field], p.origin, field);
  }
  if (auth.revocation_endpoint !== undefined) pinnedURL(auth.revocation_endpoint, p.origin, 'revocation_endpoint');
  // Tool field names from Muse's supported credential request schema. Values
  // come from checked live metadata; this object is not an OAuth session URL.
  return {
    provider: p.provider, api_hosts: p.api_hosts, auth_scheme: 'oauth2_code',
    authorization_url: auth.authorization_endpoint, token_url: auth.token_endpoint,
    issuer_domain: new URL(auth.issuer).hostname, registration_url: auth.registration_endpoint,
    resource: resource.resource, scopes: p.scopes.join(' '), token_endpoint_auth_method: 'none',
    ...(auth.revocation_endpoint ? { revoke_url: auth.revocation_endpoint } : {})
  };
}
async function fetchMetadata(url, fetcher = fetch) {
  const signal = AbortSignal.timeout(10000);
  const response = await fetcher(url, { redirect: 'error', signal, headers: { Accept: 'application/json' } });
  if (!response.ok) throw new Error('Discovery HTTP request failed');
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 65536) throw new Error('Discovery document exceeds 64 KiB');
      chunks.push(Buffer.from(value));
    }
  } finally { await reader.cancel(); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
async function main() {
  const args = process.argv.slice(2);
  if (args[0] !== '--live' || ![1, 3].includes(args.length) || (args.length === 3 && args[1] !== '--mcp-url')) {
    process.stderr.write('Usage: node scripts/check-connection-profile.cjs --live [--mcp-url HTTPS_URL]\n');
    process.exitCode = 2;
    return;
  }
  const profile = profileForEndpoint(args.length === 3 ? args[2] : undefined);
  validateProfile(profile);
  const [resource, auth] = await Promise.all([
    fetchMetadata(profile.protected_resource_metadata), fetchMetadata(profile.authorization_server_metadata)
  ]);
  process.stdout.write(JSON.stringify({ status: 'verified', profile_schema_version: profile.schema_version, resource: profile.resource,
    credential_request: validateDiscovery(profile, resource, auth) }, null, 2) + '\n');
}
if (require.main === module) main().catch(() => {
  process.stderr.write('Connection profile verification failed; stop setup and review live discovery.\n');
  process.exitCode = 1;
});
module.exports = { validateProfile, validateDiscovery, fetchMetadata };
