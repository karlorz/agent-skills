# Muse vaulted connector recipe

Use this recipe only in a Muse runtime with the installed official custom-connector setup skill and credential tool. Native grok-search MCP tools, when available, already provide the connection: reuse them instead of adding a helper. A vault entry alone does not expose MCP tools. This route adds connector instructions and a host-local helper; it does not need a second standalone Skill installation.

## Installation request

> Set up the grok-search connector using the Muse recipe in https://github.com/karlorz/agent-skills/tree/main/skills/grok-search/skills/grok-search/references/muse-connector.md. Reuse a working existing connection, verify live discovery against its shared profile, use Muse's official credential card, and finish with a small search and source retrieval. Keep secrets in the secure vault.

For an environment without this supported framework, use the separate [Skill+CLI installation request](install.md). Retiring the old Muse CLI does not remove project-wide CLI support; do not reinstall a retired local route as a setup side effect.

## 1. Inspect and reuse

Read `/opt/muse/skills/custom-connector-setup/SKILL.md`, especially “Connect the credential” and “Build the helper”, and its `references/mcp-cli.md`. Confirm the current typed credential schema before calling it. If these installed capabilities are absent, report that limitation and offer [Skill+CLI](install.md) to a suitable terminal agent.

Run inspection and reuse checks in a Muse context where `custom.grok-search` is attached and its credential policy permits the documented execution surface. Inspect `custom.grok-search` and `~/workspace/custom-connectors/custom.grok-search/` without printing secret state. A working vault connection and helper should be reused and smoke-tested. Do not create another DCR registration or reconnect merely because a conversation is new. An absent helper can be scaffolded against an existing valid connection without issuing another grant. A credential-service 403 saying sandbox access is unavailable, or a connector absent from this context, is a host attachment/policy problem before MCP negotiation. For this custom connector, return to the owning Muse context and have the operator request its use there; the tested host exposes no custom-connector privsep tool. Privsep tools belonging to shipped platform connectors cannot be borrowed. Do not bypass host policy or invent a Settings toggle. This is not evidence of an expired provider token and must not trigger reconnect or duplicate DCR. If the provider itself rejects an accessible vault entry, diagnose it; use `reconnect: true` only for a replacement authorized by the operator.

## 2. Check discovery before requesting access

[connection-profile.json](connection-profile.json) is the versioned non-secret policy shared by the installation guides. **Live discovery is authoritative.** Compare the profile's origin/resource and requested scopes with both live metadata documents before issuing a credential card. Stop and report drift; never override discovery with static profile values or continue with a stale card.

From a checked-out or copied skill unit, with Node 22 or 24:

```bash
node scripts/check-connection-profile.cjs --live
```

This credential-free check fetches only the two pinned metadata documents, rejects redirects, limits each document to 64 KiB and each request to ten seconds, and validates origin, resource, scopes, DCR, authorization code, PKCE S256, refresh grant support and public-client authentication. It does not register a client or prove refresh behavior. Successful output contains the non-secret fields for the official credential request.

On a Muse runtime without Node, perform the equivalent bounded comparison using the installed runtime: exact issuer/origin and resource, API hostname, requested scope membership in both documents, HTTPS same-origin endpoints, and the advertised features above. Do not silently skip verification.

Use `credentials.request_api_access` with the checked output's `credential_request` fields:

| Field | Source / meaning |
|---|---|
| `provider` | Profile slug; Muse stores it as `custom.<provider>` |
| `api_hosts` | Profile's bare hostname allowlist; no schemes, paths or extra hosts |
| `auth_scheme` | `oauth2_code` |
| `authorization_url`, `token_url` | Checked live authorization/token endpoints |
| `issuer_domain` | Hostname of the checked live issuer |
| `registration_url` | Checked live RFC 7591 endpoint; DCR avoids manual app credentials |
| `resource` | Exact checked MCP resource URI |
| `scopes` | Profile scopes as a **space-separated string**, not an array |
| `token_endpoint_auth_method` | `none`, only after verifying live metadata advertises it |
| `revoke_url` | Include only when live metadata provides a checked revocation endpoint |
| `reconnect` | Omit for normal setup; use only to replace a rejected existing credential |

`api_hosts`, authentication scheme and placement cannot be changed after connection according to Muse's current setup contract. Validate them before presenting a card; do not guess unsupported placement fields. If the installed schema differs from this recipe, stop and report the mismatch.

Use the official card/link **exactly as returned by the credential tool**. Never hand-build, encode, transcribe or redistribute OAuth/session URLs. The earlier “Missing required parameters” failure came from a corrupted copied link before provider login. The operator completes secure sign-in and consent; credentials remain in Secure Vault. Poll only through the documented bounded host status mechanism. If visible continuation does not resume, ask the operator to return to this conversation and confirm consent is complete; check the saved connection before issuing any new card.

## 3. Scaffold the host-local connector

Use the installed skill's `bin/scaffold-connector-docs --provider grok-search` only after checking existing files. It accepts `--provider` and optional `--display-name`, writes to the normal provider directory, and does not support a disposable output-directory flag. It does not overwrite existing documentation. Do not invent a temporary-target option or create a dummy provider to simulate a fresh install. Review the installed templates `templates/connector/CONNECTOR.md`, `templates/connector/connector.yaml`, and `templates/mcp_client.py`; adapt them using the current official instructions rather than inventing a manifest schema.

Store the endpoint, canonical resource and non-secret policy in connector configuration. Use the installed `bin/dynamic_credentials.py` via its supported import path. Do not copy platform helper code into this repo, read raw access/refresh tokens, or persist token material in scripts. Use only protected credential surrogates, restrict requests to the profile's API hosts, and disable redirects on authenticated calls.

Populate `ALLOWED_TOOLS` from the shared profile: `web_search`, `web_fetch`, `web_map`, `get_sources`, `get_config_info`. Reject any other name before sending the request. Never infer permission from the server's larger tools/list response. Plan locally; this helper does not call `plan_*`. OAuth asks for ordinary MCP and offline access only, without `config:write`. The helper allowlist and server scopes are independent controls; manual CLI credentials retain their existing operator contract.

## 4. Verify and report

1. Compile the generated helper and confirm local allowlist rejection of `switch_model`, `toggle_builtin_tools` and `plan_intent` without network calls.
2. Initialize MCP and list tools using the connected helper in a context authorized to access its credentials. Report a sandbox-policy 403 as a context blocker, never an automatic reconnect trigger. Do not treat a successful discovery check as authenticated readiness.
3. Run one small `web_search`, then call `get_sources` for its returned session in a separate helper invocation. Require usable content and sources. A second successful invocation proves credential reuse, not token refresh.
4. Report which of `web_fetch`, `web_map` and `get_config_info` were actually exercised; redact diagnostics. Do not send setting mutations for a read-only test.
5. Test repeat setup by confirming it reuses the same connector and grant. A copied-skill check proves package completeness, not a fresh Muse scaffold or fresh consent. If the official generator lacks a safe disposable target, record fresh scaffold as untested; verifying a no-op re-run of an existing scaffold proves only no-overwrite behavior. Record fresh consent, automatic continuation, expiry, refresh rotation and concurrent refresh as **untested** until actually exercised.

The reviewed baseline successfully initialized, listed tools, searched and retrieved sources through a vaulted helper. New installs and subsequent releases require their own evidence. Publishing this recipe does not require a server restart or an automatic change to existing connectors.
