# Grok Search CLI Contract

The bundled CLI `scripts/grok-search.cjs` provides standalone web search, URL fetching, and site mapping without requiring host MCP connector registration.

## Invocations

From the installed skill directory root:

```bash
node scripts/grok-search.cjs search --query '...' [--platform <platform>] [--model <model>] [--extra-sources <n>]
node scripts/grok-search.cjs fetch --url 'https://...'
node scripts/grok-search.cjs map --url 'https://...' [--instructions '...'] [--depth 1-5] [--breadth 1-500] [--limit 1-500] [--timeout 10-150]
node scripts/grok-search.cjs auth-start [--agent-id <agent_id>] [--invite-code <invite_code>]
node scripts/grok-search.cjs auth-status
```

## Options and Validation

- `auth-start`:
  - `--agent-id` (string, optional): Short host or agent label (e.g. `muse`). Sent as `agent_id` in start request body so gateway can identify/label the issuance.
  - `--invite-code` (string, optional): Operator-supplied invite code. Sent as `invite_code` in start request body and appended to approve URL query parameter `invite=`.
- `search`:
  - `--query` (string, required): Self-contained natural-language query.
  - `--platform` (string, optional): Target platform focus (e.g. `Twitter`, `GitHub`, `Reddit`).
  - `--model` (string, optional): Specific model override.
  - `--extra-sources` (integer >= 0, optional): Additional reference hits from auxiliary providers.
- `fetch`:
  - `--url` (string, required): Full HTTP/HTTPS web address.
- `map`:
  - `--url` (string, required): Root URL to begin crawler mapping.
  - `--instructions` (string, optional): Natural-language instructions for crawler filtering.
  - `--depth` (integer, 1-5, default 1): Maximum mapping depth.
  - `--breadth` (integer, 1-500, default 20): Maximum links followed per page.
  - `--limit` (integer, 1-500, default 50): Total links processed before stopping.
  - `--timeout` (integer, 10-150, default 150): Maximum duration in seconds.
- Unknown options and positional parameters are rejected before network requests.

## Output Schema

Standard output is always exactly one JSON object:

### Success (`ok: true`)

```json
{
  "ok": true,
  "data": { ... }
}
```

Exit code: `0`.

- `search` returns `content`, `session_id`, `sources` (list of citations from `get_sources`), and `sources_count`.
- `fetch` returns `content` and `url`.
- `map` returns `content` and `url`.
- `auth-start` returns `approveUrl`, `authRunId`, `expiresAt`, `intervalSeconds`.
- `auth-status` (pending) returns `status: "pending"`, `authRunId`, `nextRetrySeconds`, `expiresAt`.
- `auth-status` (complete) returns `status: "authenticated"`, `expiresAt`.

### Error (`ok: false`)

```json
{
  "ok": false,
  "error": {
    "code": "error_code",
    "message": "Human readable message",
    "retryable": false
  }
}
```

Exit code: `1` for execution / auth / transport failures; `2` for invalid arguments / missing options.

Diagnostic logs and TTY QR rendering are directed exclusively to standard error (`stderr`).

## Transport Strategy: REST Preference with Classified 404 Fallback

For read operations (`search`, `fetch`, and `map`), the CLI follows a REST-first strategy with narrowly classified fallback:

1. **REST-first preference**: Commands issue a `POST` request to `https://search.karldigi.dev/api/v1/{search,fetch,map}` with `Accept: application/json` and Authorization header with bearer token.
2. **Success envelope**: When REST responds with `{ ok: true, data: { ... } }` under HTTP 200, the CLI returns that payload directly as stdout. For `search`, sources are embedded server-side.
3. **Classified 404 fallback**: If and only if the REST HTTP status is 404 and the response body is not a recognized JSON application error envelope (`{ ok: false, error: ... }` or `{ code: "not_found" }`), the CLI classifies the route as endpoint-unavailable (e.g. gateway/Caddy 404 on an older server) and executes exactly one hidden Streamable HTTP MCP transaction (`initialize`, `notifications/initialized`, `tools/call`).
4. **No fallback on failures**: The CLI fails closed without MCP fallback on HTTP 401, 403, 429, 5xx, timeouts, malformed JSON, application error envelopes, or fetched page 404 bodies.
5. **Stateless discovery**: No persistent fallback flag is saved; subsequent commands always attempt REST first to allow instant adaptation when the server upgrades.
6. **Bearer isolation**: The Grok bearer token is strictly sent only to the pinned service origin (`https://search.karldigi.dev`) and never attached to user-provided fetch or map URLs. Target URLs with credentials or localhost/private network destinations are rejected.

