# Address selection

Use one selection rule for both installation routes:

1. If the operator explicitly supplies a compatible GrokSearch MCP URL, use that URL.
2. Otherwise preserve an existing installation's saved address and connection.
3. For a new installation without an explicit URL, use `https://search.karldigi.dev/mcp`.

Changing the address is local configuration, not a repository edit. Accept a full HTTPS MCP URL without embedded credentials, a query or a fragment. Preserve its exact path. This is an alternate GrokSearch deployment, not an arbitrary server with unrelated tools. Never silently fall back from a custom endpoint to production.

## Connector route

Keep the endpoint in the host's documented non-secret connector settings. Confirm the actual configured URL before reusing native tools; tool names alone do not identify their service. An explicitly selected custom address must not be overwritten by the production URL in plugin examples. Hosts with fixed marketplace manifests must use a supported custom-connector setup surface; if none is available, report the limitation and offer the CLI route rather than editing plugin source or host MCP files.

Run the credential-free checker before requesting a new grant:

```bash
# New installation with no override:
node scripts/check-connection-profile.cjs --live
# Explicit custom address (example only):
node scripts/check-connection-profile.cjs --live --mcp-url https://your-deployment.example/agent/mcp
```

The checker derives expected origin, resource, API host and discovery locations from the selected URL, retaining the shared scope/tool policy. It compares live metadata against those expectations and currently requires a compatible same-origin OAuth issuer, PKCE S256, DCR and public-client authentication. Production and custom profiles do not override live metadata on mismatch. A custom profile gets a deterministic provider slug from the full resource URL, isolating it from the default vault entry. Use that returned provider throughout the host's official scaffold and credential request.

A new address needs a credential valid for that resource. Do not move an old access token, refresh token or vault surrogate to it. Keep the default connection available; create/authorize the selected custom connection through the host's secure UI when required.

## Skill + CLI route

From the installed skill unit:

```bash
# Inspect only; preserves an existing selection, otherwise reports production:
node scripts/grok-search.cjs configure
# Only on an explicit request to select/change an address:
node scripts/grok-search.cjs configure --mcp-url https://your-deployment.example/agent/mcp
```

No command is required for a new default installation. Saved selection applies on later invocations, so installation prompts do not need to be repeated. Selecting the production URL explicitly returns to the default namespace. Repeating a saved URL changes nothing. Selection uses the same POSIX storage checks as existing hosted auth; malformed or unsafe saved state fails closed rather than selecting another service.

Verify the selected address with the profile checker before `auth-start`; then follow the normal bounded pairing workflow. A custom deployment must provide the compatible same-origin CLI pairing coordinator. Search/fetch/map use direct MCP at the exact custom resource, without assuming production REST routes exist. Production keeps its existing REST-first behavior.

The saved selector is `~/.config/grok-search/endpoint.json`. Production tokens stay at their existing locations. Each custom resource gets a separate private namespace under `~/.config/grok-search/servers/`, keyed by its full URL; pending approvals, locks and generated metadata are bound to that selection. Changing settings does not copy, revoke or delete another endpoint's credentials. Each command freezes the selected address before reading credentials, so concurrent reconfiguration affects the next command only.

An inherited `GROK_SEARCH_MCP_TOKEN` is accepted for a custom endpoint only when `GROK_SEARCH_MCP_TOKEN_RESOURCE` explicitly matches its exact resource URL. Do not print either token material or private auth state. See [auth-contract.md](auth-contract.md).

Moving backend machines while retaining the same public URL can instead be handled in DNS/reverse-proxy deployment configuration. That does not require changing client settings, provided issuer and resource identity remain the same.
