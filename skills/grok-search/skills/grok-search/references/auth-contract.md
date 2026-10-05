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
   - If pending: returns `{ ok: true, data: { status: "pending", ... } }` with exit code `0`.
   - If approved/ready: extracts token, atomically persists `http-mcp.token` and `token-meta.json`, cleans up `cli-auth.json`, and returns `{ ok: true, data: { status: "authenticated" } }` with exit code `0`.
   - If cancelled/expired: cleans up `cli-auth.json` and exits with an error status.
