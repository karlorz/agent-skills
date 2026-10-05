# Grok Search CLI Authentication Contract

The CLI authenticates against the hosted coordinator at `https://search.karldigi.dev` using hosted approve-and-poll.

## Credential Resolution Order

1. Environment variable: Non-empty `GROK_SEARCH_MCP_TOKEN`.
2. File token: `~/.config/grok-search/http-mcp.token`.

If the environment variable is present and rejected (HTTP 401), the CLI returns `env_token_rejected` and explains that the operator must update or unset the environment override. A file token cannot supersede an active environment variable.

If no token is found, read commands return `auth_required` instructing the user to run `auth-start`.

## State and File Permissions

- Storage directory: `~/.config/grok-search/` with permissions `0700` (POSIX).
- Token file: `~/.config/grok-search/http-mcp.token` with permissions `0600`.
- Metadata file: `~/.config/grok-search/token-meta.json` with permissions `0600`.
- Pending auth session: `~/.config/grok-search/cli-auth.json` with permissions `0600`.
- Auth lock: `~/.config/grok-search/cli-auth.lock` with permissions `0600`.
- Symbolic links are rejected.
- Files are updated using exclusive temporary files and atomic replacement.

## Auth Lifecycle

1. `auth-start`:
   - Makes a POST request to `https://search.karldigi.dev/auth/cli/start`.
   - Persists pending session state (`authRunId`, `pollSecret`, `approveUrl`, `expiresAt`, `intervalSeconds`) privately in `cli-auth.json`.
   - Emits public parameters (`approveUrl`, `authRunId`, `expiresAt`, `intervalSeconds`) to `stdout`.
   - On interactive TTY terminals, renders a scannable QR code of `approveUrl` to `stderr`.
   - `pollSecret` is strictly excluded from `stdout`, `stderr`, logs, and QR codes.

2. `auth-status`:
   - Reads private `authRunId` and `pollSecret` from `cli-auth.json`.
   - Makes a GET request to `https://search.karldigi.dev/auth/cli/check?authRunId=<id>` with `X-CLI-Poll-Secret: <pollSecret>`.
   - Maps hosted check JSON `status` (not the coordinator's internal `AuthRunState` names) as follows:
     - `pending`, `awaiting_gateway`, `claiming`: returns `{ ok: true, data: { status: "pending", ... } }` with exit code `0`. Leaves `cli-auth.json` in place.
     - `success`, `ready`, `authenticated`: token-bearing. The hosted coordinator's first successful claim is `success` plus `token`. Extracts `token` / `accessToken` / `bearer`, atomically persists `http-mcp.token` and `token-meta.json`, deletes `cli-auth.json`, and returns `{ ok: true, data: { status: "authenticated" } }` with exit code `0`.
     - `consumed`: already claimed. If `http-mcp.token` exists, deletes `cli-auth.json` and returns authenticated. If the token file is missing, exits `auth_exchange_failed` and leaves `cli-auth.json` (the bearer is not on the consumed payload).
     - `cancelled`, `expired`, `failed`: deletes `cli-auth.json` and exits with an error status.
     - Any other check status: exits `auth_failed` with `retryable: true` and leaves `cli-auth.json` so a status mismatch cannot burn the session.
