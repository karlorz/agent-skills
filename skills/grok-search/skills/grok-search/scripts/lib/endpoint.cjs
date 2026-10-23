'use strict';
const crypto = require('node:crypto');
const defaults = require('../../references/connection-profile.json');

function normalizeEndpoint(value) {
  let url;
  if (typeof value !== 'string' || !value.trim() || value.length > 2048) throw new Error('invalid_mcp_url');
  try { url = new URL(value); } catch { throw new Error('invalid_mcp_url'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.href.includes('?') || url.href.includes('#')) {
    throw new Error('invalid_mcp_url');
  }
  return url.href;
}
function profileForEndpoint(value = defaults.resource) {
  const resource = normalizeEndpoint(value);
  const url = new URL(resource);
  return {
    ...defaults, provider: resource === defaults.resource ? defaults.provider :
      `grok-search-${crypto.createHash('sha256').update(resource).digest('hex').slice(0, 12)}`,
    origin: url.origin, resource, api_hosts: [url.hostname],
    protected_resource_metadata: `${url.origin}/.well-known/oauth-protected-resource${url.pathname === '/' ? '' : url.pathname}`,
    authorization_server_metadata: `${url.origin}/.well-known/oauth-authorization-server`
  };
}
module.exports = { normalizeEndpoint, profileForEndpoint, DEFAULT_MCP_URL: defaults.resource };
